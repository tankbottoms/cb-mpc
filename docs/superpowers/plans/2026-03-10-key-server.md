# CB-MPC Key Server Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy a Cloudflare Worker key server that acts as an active MPC participant -- running cbmpc via WASM -- with Durable Objects for device registry, DKG sessions (WebSocket), and key share storage. SSL provided by CF.

**Architecture:** Three Durable Object classes (DeviceRegistry, DKGSession, KeyVault) coordinate 3-party DKG between two iOS devices and the server. The server runs cbmpc compiled to WASM via Emscripten. Devices connect via WebSocket for real-time DKG message relay. Device auth uses HMAC tokens.

**Tech Stack:** Cloudflare Workers, Durable Objects (SQLite), TypeScript, Emscripten (C++ to WASM), cbmpc C API, WebSocket API, Wrangler CLI

**Spec:** `docs/superpowers/specs/2026-03-10-key-server-design.md`

---

## Chunk 1: CF Worker Skeleton + Health + Auth

### Task 1: Project scaffold

**Files:**
- Create: `key-server/wrangler.toml`
- Create: `key-server/tsconfig.json`
- Create: `key-server/package.json`
- Create: `key-server/src/index.ts`
- Create: `key-server/src/types.ts`

- [ ] **Step 1: Create project directory and wrangler.toml**

```bash
mkdir -p key-server/src
```

`key-server/wrangler.toml`:
```toml
name = "cb-mpc-key-server"
main = "src/index.ts"
compatibility_date = "2026-03-01"
account_id = "e8d1f015160adf1c0096e901915764e0"

[vars]
VERSION = "0.1.0"

[[durable_objects.bindings]]
name = "DEVICE_REGISTRY"
class_name = "DeviceRegistry"

[[durable_objects.bindings]]
name = "DKG_SESSION"
class_name = "DKGSession"

[[durable_objects.bindings]]
name = "KEY_VAULT"
class_name = "KeyVault"

[[migrations]]
tag = "v1"
new_sqlite_classes = ["DeviceRegistry", "DKGSession", "KeyVault"]
```

- [ ] **Step 2: Create package.json and tsconfig.json**

`key-server/package.json`:
```json
{
  "name": "cb-mpc-key-server",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "dev": "wrangler dev",
    "deploy": "wrangler deploy",
    "test": "wrangler dev --test"
  },
  "devDependencies": {
    "@cloudflare/workers-types": "^4.20260101.0",
    "wrangler": "^4.0.0"
  }
}
```

`key-server/tsconfig.json`:
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ES2022",
    "moduleResolution": "bundler",
    "lib": ["ES2022"],
    "types": ["@cloudflare/workers-types"],
    "strict": true,
    "noEmit": true,
    "skipLibCheck": true
  },
  "include": ["src/**/*.ts"]
}
```

- [ ] **Step 3: Create shared types**

`key-server/src/types.ts`:
```typescript
export interface Env {
  DEVICE_REGISTRY: DurableObjectNamespace;
  DKG_SESSION: DurableObjectNamespace;
  KEY_VAULT: DurableObjectNamespace;
  SERVER_SECRET: string;
  VERSION: string;
}

export interface DeviceRecord {
  id: string;
  name: string;
  deviceType: string;
  publicKey: string;
  tokenHash: string;
  registeredAt: number;
  lastSeenAt: number | null;
  isOnline: boolean;
}

export interface SessionState {
  id: string;
  status: "pending" | "active" | "complete" | "failed";
  participants: string[];
  curveCode: number;
  createdAt: number;
  publicKey: string | null;
  error: string | null;
}

export interface KeyRecord {
  publicKey: string;
  curveCode: number;
  serverShare: ArrayBuffer;
  participantDevices: string[];
  createdAt: number;
  lastUsedAt: number | null;
  signCount: number;
}

// WebSocket binary message types
export const MSG_TYPE = {
  DKG_MSG: 0x01,
  DKG_COMPLETE: 0x02,
  SIGN_REQUEST: 0x03,
  SIGN_MSG: 0x04,
  SIGN_COMPLETE: 0x05,
  ERROR: 0xff,
} as const;

// Binary message header: [type:1][session_prefix:4][sender:2][receiver:2][payload_len:4][payload:N]
export const MSG_HEADER_SIZE = 13;
```

- [ ] **Step 4: Create router entry point with health endpoint**

`key-server/src/index.ts`:
```typescript
import { Env } from "./types";

export { DeviceRegistry } from "./durable-objects/device-registry";
export { DKGSession } from "./durable-objects/dkg-session";
export { KeyVault } from "./durable-objects/key-vault";

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const method = request.method;

    // CORS headers for all responses
    const corsHeaders = {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
      "Access-Control-Allow-Headers": "Authorization, Content-Type",
    };

    if (method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders });
    }

    try {
      const response = await route(url, method, request, env);
      // Add CORS to all responses
      for (const [k, v] of Object.entries(corsHeaders)) {
        response.headers.set(k, v);
      }
      return response;
    } catch (err: any) {
      return Response.json(
        { error: err.message || "Internal error" },
        { status: 500, headers: corsHeaders }
      );
    }
  },
};

async function route(
  url: URL,
  method: string,
  request: Request,
  env: Env
): Promise<Response> {
  const path = url.pathname;

  // Health check -- no auth
  if (path === "/health" && method === "GET") {
    return Response.json({ status: "ok", version: env.VERSION });
  }

  // Device registration -- no auth
  if (path === "/devices/register" && method === "POST") {
    const registryId = env.DEVICE_REGISTRY.idFromName("global");
    const registry = env.DEVICE_REGISTRY.get(registryId);
    return registry.fetch(request);
  }

  // All other routes require auth
  const token = extractToken(request, url);
  if (!token) {
    return Response.json({ error: "Missing auth token" }, { status: 401 });
  }

  const valid = await validateToken(token, env.SERVER_SECRET);
  if (!valid) {
    return Response.json({ error: "Invalid auth token" }, { status: 401 });
  }

  // Device routes
  if (path.startsWith("/devices/")) {
    const registryId = env.DEVICE_REGISTRY.idFromName("global");
    const registry = env.DEVICE_REGISTRY.get(registryId);
    return registry.fetch(request);
  }

  // Session routes
  if (path.startsWith("/sessions/")) {
    const parts = path.split("/").filter(Boolean);
    // POST /sessions/dkg -> create session
    if (parts.length === 2 && parts[1] === "dkg" && method === "POST") {
      const sessionId = crypto.randomUUID();
      const doId = env.DKG_SESSION.idFromName(sessionId);
      const session = env.DKG_SESSION.get(doId);
      // Forward with session ID in header
      const newReq = new Request(request.url, {
        method: request.method,
        headers: request.headers,
        body: request.body,
      });
      newReq.headers.set("X-Session-Id", sessionId);
      return session.fetch(newReq);
    }
    // GET /sessions/:id, WS /sessions/:id/ws, POST /sessions/:id/sign
    if (parts.length >= 2) {
      const sessionId = parts[1];
      const doId = env.DKG_SESSION.idFromName(sessionId);
      const session = env.DKG_SESSION.get(doId);
      return session.fetch(request);
    }
  }

  // Key routes
  if (path.startsWith("/keys")) {
    const parts = path.split("/").filter(Boolean);
    if (parts.length === 1 && method === "GET") {
      // List keys -- route to registry
      const registryId = env.DEVICE_REGISTRY.idFromName("global");
      const registry = env.DEVICE_REGISTRY.get(registryId);
      return registry.fetch(request);
    }
    if (parts.length === 2) {
      const pubkey = parts[1];
      const vaultId = env.KEY_VAULT.idFromName(pubkey);
      const vault = env.KEY_VAULT.get(vaultId);
      return vault.fetch(request);
    }
  }

  return Response.json({ error: "Not found" }, { status: 404 });
}

function extractToken(request: Request, url: URL): string | null {
  const authHeader = request.headers.get("Authorization");
  if (authHeader?.startsWith("Bearer ")) {
    return authHeader.slice(7);
  }
  return url.searchParams.get("token");
}

async function validateToken(
  token: string,
  secret: string
): Promise<boolean> {
  const dot = token.indexOf(".");
  if (dot === -1) return false;
  const deviceId = token.slice(0, dot);
  const hmac = token.slice(dot + 1);
  const expected = await computeHmac(deviceId, secret);
  return hmac === expected;
}

async function computeHmac(
  data: string,
  secret: string
): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const sig = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(data)
  );
  return Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// Exported for use by DOs
export { computeHmac };
```

- [ ] **Step 5: Install dependencies and verify build**

```bash
cd key-server && npm install
npx wrangler deploy --dry-run
```

Expected: no TypeScript errors (DO classes will be stubs initially).

- [ ] **Step 6: Commit**

```bash
git add key-server/
git commit -m "feat(key-server): scaffold CF Worker with router, types, health endpoint"
```

---

### Task 2: DeviceRegistry Durable Object

**Files:**
- Create: `key-server/src/durable-objects/device-registry.ts`
- Create: `key-server/src/auth.ts`

- [ ] **Step 1: Create auth utility module**

`key-server/src/auth.ts`:
```typescript
export async function computeHmac(
  data: string,
  secret: string
): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const sig = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(data)
  );
  return Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

export async function hashToken(token: string): Promise<string> {
  const buf = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(token)
  );
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
```

- [ ] **Step 2: Create DeviceRegistry Durable Object**

`key-server/src/durable-objects/device-registry.ts`:
```typescript
import { DurableObject } from "cloudflare:workers";
import { Env, DeviceRecord } from "../types";
import { computeHmac, hashToken } from "../auth";

export class DeviceRegistry extends DurableObject<Env> {
  private sql: SqlStorage;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.sql = ctx.storage.sql;
    this.sql.exec(`
      CREATE TABLE IF NOT EXISTS devices (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        device_type TEXT NOT NULL,
        public_key TEXT NOT NULL,
        token_hash TEXT NOT NULL,
        registered_at INTEGER NOT NULL,
        last_seen_at INTEGER,
        is_online INTEGER DEFAULT 0
      )
    `);
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;
    const method = request.method;

    // POST /devices/register
    if (path === "/devices/register" && method === "POST") {
      return this.register(request);
    }

    // GET /devices/:id
    const parts = path.split("/").filter(Boolean);
    if (parts[0] === "devices" && parts.length === 2 && method === "GET") {
      return this.getDevice(parts[1]);
    }

    // DELETE /devices/:id
    if (parts[0] === "devices" && parts.length === 2 && method === "DELETE") {
      return this.deleteDevice(parts[1]);
    }

    // GET /keys (list keys for device -- forwarded from main router)
    if (path === "/keys" && method === "GET") {
      return this.listDevices();
    }

    return Response.json({ error: "Not found" }, { status: 404 });
  }

  private async register(request: Request): Promise<Response> {
    const body = await request.json<{
      device_name: string;
      device_type: string;
      public_key: string;
    }>();

    if (!body.device_name || !body.device_type || !body.public_key) {
      return Response.json(
        { error: "Missing required fields: device_name, device_type, public_key" },
        { status: 400 }
      );
    }

    const deviceId = crypto.randomUUID();
    const token = `${deviceId}.${await computeHmac(deviceId, this.env.SERVER_SECRET)}`;
    const tokenH = await hashToken(token);
    const now = Date.now();

    this.sql.exec(
      `INSERT INTO devices (id, name, device_type, public_key, token_hash, registered_at)
       VALUES (?, ?, ?, ?, ?, ?)`,
      deviceId,
      body.device_name,
      body.device_type,
      body.public_key,
      tokenH,
      now
    );

    return Response.json({
      device_id: deviceId,
      token: token,
      registered_at: now,
    }, { status: 201 });
  }

  private getDevice(id: string): Response {
    const rows = this.sql
      .exec("SELECT * FROM devices WHERE id = ?", id)
      .toArray();
    if (rows.length === 0) {
      return Response.json({ error: "Device not found" }, { status: 404 });
    }
    const d = rows[0];
    return Response.json({
      id: d.id,
      name: d.name,
      device_type: d.device_type,
      public_key: d.public_key,
      registered_at: d.registered_at,
      last_seen_at: d.last_seen_at,
      is_online: Boolean(d.is_online),
    });
  }

  private deleteDevice(id: string): Response {
    const result = this.sql.exec("DELETE FROM devices WHERE id = ?", id);
    if (result.rowsWritten === 0) {
      return Response.json({ error: "Device not found" }, { status: 404 });
    }
    return Response.json({ deleted: true });
  }

  private listDevices(): Response {
    const rows = this.sql
      .exec("SELECT id, name, device_type, is_online, registered_at FROM devices")
      .toArray();
    return Response.json({ devices: rows });
  }
}
```

- [ ] **Step 3: Update index.ts to import auth from module (remove inline computeHmac)**

In `key-server/src/index.ts`, replace the inline `computeHmac` function and add:
```typescript
import { computeHmac } from "./auth";
```
Remove the duplicate `computeHmac` function and the `export { computeHmac }` line at the bottom.

- [ ] **Step 4: Commit**

```bash
git add key-server/src/auth.ts key-server/src/durable-objects/device-registry.ts key-server/src/index.ts
git commit -m "feat(key-server): add DeviceRegistry DO with registration, auth tokens"
```

---

### Task 3: DKGSession Durable Object (stub + WebSocket)

**Files:**
- Create: `key-server/src/durable-objects/dkg-session.ts`
- Create: `key-server/src/protocol.ts`

- [ ] **Step 1: Create protocol message encoder/decoder**

`key-server/src/protocol.ts`:
```typescript
import { MSG_TYPE, MSG_HEADER_SIZE } from "./types";

export function encodeMessage(
  type: number,
  sessionPrefix: Uint8Array, // 4 bytes
  senderPartyId: number,
  receiverPartyId: number,
  payload: Uint8Array
): ArrayBuffer {
  const buf = new ArrayBuffer(MSG_HEADER_SIZE + payload.byteLength);
  const view = new DataView(buf);
  const bytes = new Uint8Array(buf);

  view.setUint8(0, type);
  bytes.set(sessionPrefix.slice(0, 4), 1);
  view.setUint16(5, senderPartyId, false); // big-endian
  view.setUint16(7, receiverPartyId, false);
  view.setUint32(9, payload.byteLength, false);
  bytes.set(payload, MSG_HEADER_SIZE);

  return buf;
}

export function decodeMessage(buf: ArrayBuffer): {
  type: number;
  sessionPrefix: Uint8Array;
  senderPartyId: number;
  receiverPartyId: number;
  payload: Uint8Array;
} {
  const view = new DataView(buf);
  const bytes = new Uint8Array(buf);

  return {
    type: view.getUint8(0),
    sessionPrefix: bytes.slice(1, 5),
    senderPartyId: view.getUint16(5, false),
    receiverPartyId: view.getUint16(7, false),
    payload: bytes.slice(MSG_HEADER_SIZE),
  };
}
```

- [ ] **Step 2: Create DKGSession Durable Object with WebSocket handling**

`key-server/src/durable-objects/dkg-session.ts`:
```typescript
import { DurableObject } from "cloudflare:workers";
import { Env, MSG_TYPE } from "../types";
import { encodeMessage, decodeMessage } from "../protocol";

interface Participant {
  deviceId: string;
  partyId: number;
  ws: WebSocket | null;
}

export class DKGSession extends DurableObject<Env> {
  private sql: SqlStorage;
  private participants: Map<number, Participant> = new Map();
  private sessionId: string = "";
  private status: "pending" | "active" | "complete" | "failed" = "pending";
  private curveCode: number = 714; // secp256k1 default
  private sessionPrefix: Uint8Array = new Uint8Array(4);

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.sql = ctx.storage.sql;
    this.sql.exec(`
      CREATE TABLE IF NOT EXISTS session_state (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    `);
    this.sql.exec(`
      CREATE TABLE IF NOT EXISTS messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        round INTEGER NOT NULL,
        sender_party_id INTEGER NOT NULL,
        receiver_party_id INTEGER NOT NULL,
        payload BLOB NOT NULL,
        created_at INTEGER NOT NULL
      )
    `);
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;
    const method = request.method;
    const parts = path.split("/").filter(Boolean);

    // POST /sessions/dkg -- create session
    if (parts[1] === "dkg" && method === "POST") {
      return this.createSession(request);
    }

    // GET /sessions/:id -- status
    if (parts.length === 2 && method === "GET") {
      return this.getStatus();
    }

    // GET /sessions/:id/ws -- WebSocket upgrade
    if (parts.length === 3 && parts[2] === "ws") {
      return this.handleWebSocket(request, url);
    }

    // POST /sessions/:id/sign -- signing (future)
    if (parts.length === 3 && parts[2] === "sign" && method === "POST") {
      return Response.json(
        { error: "Signing not yet implemented" },
        { status: 501 }
      );
    }

    return Response.json({ error: "Not found" }, { status: 404 });
  }

  private async createSession(request: Request): Promise<Response> {
    const body = await request.json<{
      curve_code?: number;
      device_id: string;
      party_count?: number;
    }>();

    this.sessionId = request.headers.get("X-Session-Id") || crypto.randomUUID();
    this.curveCode = body.curve_code || 714;
    this.status = "pending";

    // Generate 4-byte session prefix from session ID
    const idBytes = new TextEncoder().encode(this.sessionId);
    const hash = await crypto.subtle.digest("SHA-256", idBytes);
    this.sessionPrefix = new Uint8Array(hash).slice(0, 4);

    // Store state
    this.setState("session_id", this.sessionId);
    this.setState("status", this.status);
    this.setState("curve_code", String(this.curveCode));
    this.setState("created_at", String(Date.now()));
    this.setState("creator_device", body.device_id);

    // Set auto-cleanup alarm (5 minutes)
    await this.ctx.storage.setAlarm(Date.now() + 5 * 60 * 1000);

    return Response.json({
      session_id: this.sessionId,
      status: this.status,
      curve_code: this.curveCode,
      ws_url: `/sessions/${this.sessionId}/ws`,
    }, { status: 201 });
  }

  private getStatus(): Response {
    const status = this.getState("status") || "unknown";
    const publicKey = this.getState("public_key");
    return Response.json({
      session_id: this.getState("session_id"),
      status,
      curve_code: Number(this.getState("curve_code") || 714),
      public_key: publicKey,
      participant_count: this.participants.size,
    });
  }

  private handleWebSocket(request: Request, url: URL): Response {
    const upgradeHeader = request.headers.get("Upgrade");
    if (upgradeHeader !== "websocket") {
      return Response.json(
        { error: "Expected WebSocket upgrade" },
        { status: 426 }
      );
    }

    const deviceId = url.searchParams.get("device_id") || "unknown";
    const partyId = this.participants.size; // assign sequential party IDs

    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);

    this.ctx.acceptWebSocket(server, [deviceId, String(partyId)]);

    this.participants.set(partyId, {
      deviceId,
      partyId,
      ws: server,
    });

    // If we have enough participants (2 devices + server = 3), start DKG
    // For now: 2-party prototype (1 device + server)
    if (this.participants.size >= 1) {
      this.status = "active";
      this.setState("status", "active");
    }

    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(ws: WebSocket, message: ArrayBuffer | string): Promise<void> {
    if (typeof message === "string") {
      // Text messages used for control
      try {
        const ctrl = JSON.parse(message);
        if (ctrl.type === "ping") {
          ws.send(JSON.stringify({ type: "pong" }));
        }
      } catch {
        // ignore malformed text
      }
      return;
    }

    // Binary message -- DKG protocol
    const decoded = decodeMessage(message);

    // Store message for replay/audit
    this.sql.exec(
      `INSERT INTO messages (round, sender_party_id, receiver_party_id, payload, created_at)
       VALUES (?, ?, ?, ?, ?)`,
      0, // round tracking TBD with WASM integration
      decoded.senderPartyId,
      decoded.receiverPartyId,
      new Uint8Array(decoded.payload),
      Date.now()
    );

    // Route message to target party
    if (decoded.receiverPartyId === 0xff) {
      // Broadcast to all except sender
      for (const [pid, p] of this.participants) {
        if (pid !== decoded.senderPartyId && p.ws) {
          p.ws.send(message);
        }
      }
    } else {
      // Unicast
      const target = this.participants.get(decoded.receiverPartyId);
      if (target?.ws) {
        target.ws.send(message);
      }
    }

    // TODO: When WASM is integrated, the server party processes
    // messages here and generates responses
  }

  async webSocketClose(ws: WebSocket, code: number): Promise<void> {
    // Remove from participants
    for (const [pid, p] of this.participants) {
      if (p.ws === ws) {
        this.participants.delete(pid);
        break;
      }
    }
    if (this.participants.size === 0 && this.status === "active") {
      this.status = "failed";
      this.setState("status", "failed");
    }
  }

  async webSocketError(ws: WebSocket, error: unknown): Promise<void> {
    await this.webSocketClose(ws, 1006);
  }

  async alarm(): Promise<void> {
    // Auto-cleanup: close all connections and mark failed if still pending/active
    if (this.status === "pending" || this.status === "active") {
      this.status = "failed";
      this.setState("status", "failed");
      for (const [, p] of this.participants) {
        try {
          p.ws?.close(4008, "Session timeout");
        } catch {}
      }
      this.participants.clear();
    }
  }

  // Helpers
  private setState(key: string, value: string): void {
    this.sql.exec(
      `INSERT OR REPLACE INTO session_state (key, value) VALUES (?, ?)`,
      key,
      value
    );
  }

  private getState(key: string): string | null {
    const rows = this.sql
      .exec("SELECT value FROM session_state WHERE key = ?", key)
      .toArray();
    return rows.length > 0 ? (rows[0].value as string) : null;
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add key-server/src/protocol.ts key-server/src/durable-objects/dkg-session.ts
git commit -m "feat(key-server): add DKGSession DO with WebSocket relay, message protocol"
```

---

### Task 4: KeyVault Durable Object (stub)

**Files:**
- Create: `key-server/src/durable-objects/key-vault.ts`

- [ ] **Step 1: Create KeyVault Durable Object**

`key-server/src/durable-objects/key-vault.ts`:
```typescript
import { DurableObject } from "cloudflare:workers";
import { Env } from "../types";

export class KeyVault extends DurableObject<Env> {
  private sql: SqlStorage;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.sql = ctx.storage.sql;
    this.sql.exec(`
      CREATE TABLE IF NOT EXISTS keys (
        public_key TEXT PRIMARY KEY,
        curve_code INTEGER NOT NULL,
        server_share BLOB NOT NULL,
        participant_devices TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        last_used_at INTEGER,
        sign_count INTEGER DEFAULT 0
      )
    `);
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const parts = url.pathname.split("/").filter(Boolean);
    const method = request.method;

    // GET /keys/:pubkey
    if (parts.length === 2 && method === "GET") {
      return this.getKey(parts[1]);
    }

    return Response.json({ error: "Not found" }, { status: 404 });
  }

  private getKey(pubkey: string): Response {
    const rows = this.sql
      .exec(
        "SELECT public_key, curve_code, participant_devices, created_at, last_used_at, sign_count FROM keys WHERE public_key = ?",
        pubkey
      )
      .toArray();

    if (rows.length === 0) {
      return Response.json({ error: "Key not found" }, { status: 404 });
    }

    const k = rows[0];
    return Response.json({
      public_key: k.public_key,
      curve_code: k.curve_code,
      participant_devices: JSON.parse(k.participant_devices as string),
      created_at: k.created_at,
      last_used_at: k.last_used_at,
      sign_count: k.sign_count,
    });
  }

  // Called internally by DKGSession after successful DKG
  async storeShare(
    publicKey: string,
    curveCode: number,
    serverShare: ArrayBuffer,
    participantDevices: string[]
  ): Promise<void> {
    this.sql.exec(
      `INSERT OR REPLACE INTO keys (public_key, curve_code, server_share, participant_devices, created_at)
       VALUES (?, ?, ?, ?, ?)`,
      publicKey,
      curveCode,
      new Uint8Array(serverShare),
      JSON.stringify(participantDevices),
      Date.now()
    );
  }

  // Called during threshold signing
  async getShare(publicKey: string): Promise<ArrayBuffer | null> {
    const rows = this.sql
      .exec("SELECT server_share FROM keys WHERE public_key = ?", publicKey)
      .toArray();
    if (rows.length === 0) return null;

    // Update usage stats
    this.sql.exec(
      "UPDATE keys SET last_used_at = ?, sign_count = sign_count + 1 WHERE public_key = ?",
      Date.now(),
      publicKey
    );

    return (rows[0].server_share as Uint8Array).buffer;
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add key-server/src/durable-objects/key-vault.ts
git commit -m "feat(key-server): add KeyVault DO for server share storage"
```

---

### Task 5: Deploy and verify health endpoint

- [ ] **Step 1: Install dependencies**

```bash
cd key-server && npm install
```

- [ ] **Step 2: Set server secret**

```bash
cd key-server && npx wrangler secret put SERVER_SECRET
# Enter a random 64-char hex string
```

- [ ] **Step 3: Deploy**

```bash
cd key-server && npx wrangler deploy
```

Expected output: `Published cb-mpc-key-server to https://cb-mpc-key-server.<account>.workers.dev`

- [ ] **Step 4: Verify health endpoint**

```bash
curl https://cb-mpc-key-server.<subdomain>.workers.dev/health
```

Expected: `{"status":"ok","version":"0.1.0"}`

- [ ] **Step 5: Verify device registration**

```bash
curl -X POST https://cb-mpc-key-server.<subdomain>.workers.dev/devices/register \
  -H "Content-Type: application/json" \
  -d '{"device_name":"Test iPhone","device_type":"iphone","public_key":"deadbeef"}'
```

Expected: `{"device_id":"<uuid>","token":"<uuid>.<hmac>","registered_at":<timestamp>}`

- [ ] **Step 6: Commit deploy confirmation (update wrangler.toml with final URL if needed)**

```bash
git add key-server/
git commit -m "feat(key-server): deploy v0.1.0, health + registration verified"
```

---

## Chunk 2: WASM Build Pipeline

### Task 6: Emscripten build script for cbmpc

**Files:**
- Create: `key-server/build/build-wasm.sh`
- Create: `key-server/build/openssl-wasm.sh`
- Modify: `CMakeLists.txt` (add WASM source target)
- Create: `src/cbmpc/wasm/cbmpc_wasm.h`
- Create: `src/cbmpc/wasm/cbmpc_wasm.cpp`
- Create: `src/cbmpc/wasm/CMakeLists.txt`

- [ ] **Step 1: Create OpenSSL WASM build script**

`key-server/build/openssl-wasm.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

# Build OpenSSL 3.2.0 for WASM via Emscripten
# Requires: emsdk installed and activated

OPENSSL_VERSION="3.2.0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/../.build/openssl-wasm"
INSTALL_DIR="${SCRIPT_DIR}/../.build/openssl-wasm-install"

if [ ! -d "${BUILD_DIR}" ]; then
  mkdir -p "${BUILD_DIR}"
  cd "${BUILD_DIR}"
  curl -LO "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz"
  tar xzf "openssl-${OPENSSL_VERSION}.tar.gz"
fi

cd "${BUILD_DIR}/openssl-${OPENSSL_VERSION}"

# Configure for WASM -- no-asm, no-threads, static only
emconfigure ./Configure \
  linux-generic32 \
  no-asm \
  no-threads \
  no-shared \
  no-dso \
  no-engine \
  no-hw \
  no-dgram \
  no-sock \
  no-posix-io \
  no-afalgeng \
  no-ui-console \
  no-stdio \
  --prefix="${INSTALL_DIR}" \
  -DNO_SYSLOG \
  CFLAGS="-O3 -fPIC"

emmake make -j$(nproc 2>/dev/null || sysctl -n hw.ncpu) build_libs
emmake make install_dev

echo "OpenSSL WASM built at: ${INSTALL_DIR}"
echo "  Include: ${INSTALL_DIR}/include"
echo "  Lib:     ${INSTALL_DIR}/lib or ${INSTALL_DIR}/lib64"
```

- [ ] **Step 2: Create WASM FFI layer**

`src/cbmpc/wasm/cbmpc_wasm.h`:
```c
#ifndef CBMPC_WASM_H
#define CBMPC_WASM_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Memory management
void* cbmpc_wasm_malloc(int size);
void cbmpc_wasm_free(void* ptr);

// Transport -- JS provides callbacks via function pointers
typedef int (*cbmpc_wasm_send_f)(int receiver, const uint8_t* data, int size);
typedef int (*cbmpc_wasm_recv_f)(int sender, uint8_t** out_data, int* out_size);

// 2-party DKG -- returns 0 on success
// role: 0 or 1 (server is typically role 1)
// curve_code: 714 = secp256k1
// out_key_data/out_key_size: serialized key share
// out_pubkey/out_pubkey_size: 33-byte compressed public key
int cbmpc_wasm_ecdsa2p_dkg(
    int role,
    int curve_code,
    cbmpc_wasm_send_f send_fn,
    cbmpc_wasm_recv_f recv_fn,
    uint8_t** out_key_data,
    int* out_key_size,
    uint8_t** out_pubkey,
    int* out_pubkey_size
);

// 2-party sign
// key_data/key_size: serialized key share from DKG
// msg_hash: 32-byte message hash
// out_sig/out_sig_size: DER-encoded signature
int cbmpc_wasm_ecdsa2p_sign(
    int role,
    int curve_code,
    const uint8_t* key_data,
    int key_size,
    const uint8_t* session_id,
    int session_id_size,
    const uint8_t* msg_hash,
    int msg_hash_size,
    cbmpc_wasm_send_f send_fn,
    cbmpc_wasm_recv_f recv_fn,
    uint8_t** out_sig,
    int* out_sig_size
);

// Stateless verification (no transport needed)
int cbmpc_wasm_ecdsa_verify(
    int curve_code,
    const uint8_t* pub_key,
    int pub_key_size,
    const uint8_t* hash,
    int hash_size,
    const uint8_t* der_sig,
    int der_sig_size
);

#ifdef __cplusplus
}
#endif

#endif // CBMPC_WASM_H
```

`src/cbmpc/wasm/cbmpc_wasm.cpp`:
```cpp
#include "cbmpc_wasm.h"
#include "cbmpc/ios/cbmpc_ios.h"  // Reuse the C API
#include <cstdlib>
#include <cstring>

extern "C" {

void* cbmpc_wasm_malloc(int size) {
    return cbmpc_malloc(size);
}

void cbmpc_wasm_free(void* ptr) {
    cbmpc_free(ptr);
}

// Adapter: wrap JS function pointers into cbmpc_transport_t callbacks
struct wasm_transport_ctx {
    cbmpc_wasm_send_f send_fn;
    cbmpc_wasm_recv_f recv_fn;
};

static int wasm_send_adapter(void* ctx, int receiver, cbmpc_cmem_t message) {
    auto* tc = static_cast<wasm_transport_ctx*>(ctx);
    return tc->send_fn(receiver, static_cast<const uint8_t*>(message.data), message.size);
}

static int wasm_recv_adapter(void* ctx, int sender, cbmpc_cmem_t* out) {
    auto* tc = static_cast<wasm_transport_ctx*>(ctx);
    uint8_t* data = nullptr;
    int size = 0;
    int err = tc->recv_fn(sender, &data, &size);
    if (err != 0) return err;
    out->data = data;
    out->size = size;
    return 0;
}

int cbmpc_wasm_ecdsa2p_dkg(
    int role,
    int curve_code,
    cbmpc_wasm_send_f send_fn,
    cbmpc_wasm_recv_f recv_fn,
    uint8_t** out_key_data,
    int* out_key_size,
    uint8_t** out_pubkey,
    int* out_pubkey_size
) {
    wasm_transport_ctx tc = { send_fn, recv_fn };

    cbmpc_transport_t transport;
    transport.send_fn = wasm_send_adapter;
    transport.receive_fn = wasm_recv_adapter;
    transport.receive_all_fn = nullptr; // 2-party doesn't need broadcast

    const char* names[2] = { "party0", "party1" };
    cbmpc_job2p_t* job = cbmpc_job2p_new(&transport, &tc, role, names, 2);
    if (!job) return -1;

    cbmpc_ecdsa2p_key_t key;
    int err = cbmpc_ecdsa2p_dkg(job, curve_code, &key);
    cbmpc_job2p_free(job);

    if (err != 0) return err;

    // Serialize key share
    cbmpc_cmem_t serialized = cbmpc_ecdsa2p_key_serialize(&key);
    *out_key_data = static_cast<uint8_t*>(cbmpc_wasm_malloc(serialized.size));
    memcpy(*out_key_data, serialized.data, serialized.size);
    *out_key_size = serialized.size;
    cbmpc_free(serialized.data);

    // Extract public key
    cbmpc_cmem_t pubkey = cbmpc_ecdsa2p_key_pubkey(&key);
    *out_pubkey = static_cast<uint8_t*>(cbmpc_wasm_malloc(pubkey.size));
    memcpy(*out_pubkey, pubkey.data, pubkey.size);
    *out_pubkey_size = pubkey.size;
    cbmpc_free(pubkey.data);

    cbmpc_ecdsa2p_key_free(key);
    return 0;
}

int cbmpc_wasm_ecdsa2p_sign(
    int role,
    int curve_code,
    const uint8_t* key_data,
    int key_size,
    const uint8_t* session_id,
    int session_id_size,
    const uint8_t* msg_hash,
    int msg_hash_size,
    cbmpc_wasm_send_f send_fn,
    cbmpc_wasm_recv_fn recv_fn,
    uint8_t** out_sig,
    int* out_sig_size
) {
    // Deserialize key
    cbmpc_cmem_t key_mem = { const_cast<uint8_t*>(key_data), key_size };
    cbmpc_ecdsa2p_key_t key;
    int err = cbmpc_ecdsa2p_key_deserialize(key_mem, &key);
    if (err != 0) return err;

    // Setup transport
    wasm_transport_ctx tc = { send_fn, recv_fn };
    cbmpc_transport_t transport;
    transport.send_fn = wasm_send_adapter;
    transport.receive_fn = wasm_recv_adapter;
    transport.receive_all_fn = nullptr;

    const char* names[2] = { "party0", "party1" };
    cbmpc_job2p_t* job = cbmpc_job2p_new(&transport, &tc, role, names, 2);
    if (!job) {
        cbmpc_ecdsa2p_key_free(key);
        return -1;
    }

    // Sign
    cbmpc_cmem_t sid = {
        const_cast<uint8_t*>(session_id),
        session_id_size
    };
    cbmpc_cmem_t msg = {
        const_cast<uint8_t*>(msg_hash),
        msg_hash_size
    };
    cbmpc_cmems_t msgs;
    msgs.count = 1;
    msgs.data = msg.data;
    msgs.sizes = &msg.size;

    cbmpc_cmems_t sigs;
    err = cbmpc_ecdsa2p_sign(job, sid, &key, msgs, &sigs);

    cbmpc_job2p_free(job);
    cbmpc_ecdsa2p_key_free(key);

    if (err != 0) return err;

    // Copy signature out
    *out_sig = static_cast<uint8_t*>(cbmpc_wasm_malloc(sigs.sizes[0]));
    memcpy(*out_sig, sigs.data, sigs.sizes[0]);
    *out_sig_size = sigs.sizes[0];
    cbmpc_free(sigs.data);
    cbmpc_free(sigs.sizes);

    return 0;
}

int cbmpc_wasm_ecdsa_verify(
    int curve_code,
    const uint8_t* pub_key,
    int pub_key_size,
    const uint8_t* hash,
    int hash_size,
    const uint8_t* der_sig,
    int der_sig_size
) {
    cbmpc_cmem_t pub = { const_cast<uint8_t*>(pub_key), pub_key_size };
    cbmpc_cmem_t h = { const_cast<uint8_t*>(hash), hash_size };
    cbmpc_cmem_t sig = { const_cast<uint8_t*>(der_sig), der_sig_size };
    return cbmpc_ecdsa_verify(curve_code, pub, h, sig);
}

} // extern "C"
```

`src/cbmpc/wasm/CMakeLists.txt`:
```cmake
add_library(cbmpc_wasm OBJECT
    cbmpc_wasm.cpp
)

target_include_directories(cbmpc_wasm PUBLIC ${SRC_DIR})
```

- [ ] **Step 3: Update main CMakeLists.txt to include WASM target**

In `CMakeLists.txt`, after the iOS block (line ~98), add:
```cmake
# WASM FFI layer
if(IS_WASM)
  add_subdirectory(src/cbmpc/wasm)
endif()
```

Update the `add_library(cbmpc STATIC ...)` call to include WASM objects:
```cmake
add_library(
  cbmpc STATIC $<TARGET_OBJECTS:cbmpc_core> $<TARGET_OBJECTS:cbmpc_crypto>
               $<TARGET_OBJECTS:cbmpc_zk> $<TARGET_OBJECTS:cbmpc_protocol>
               $<TARGET_OBJECTS:cbmpc_ffi>
               $<$<OR:$<BOOL:${IS_IOS}>,$<BOOL:${IS_IOS_SIMULATOR}>,$<BOOL:${IS_MACOS}>>:$<TARGET_OBJECTS:cbmpc_ios>>
               $<$<BOOL:${IS_WASM}>:$<TARGET_OBJECTS:cbmpc_wasm>>)
```

- [ ] **Step 4: Create main WASM build script**

`key-server/build/build-wasm.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

# Build cbmpc as WASM module for Cloudflare Workers
# Requires: emsdk installed and activated, OpenSSL WASM built

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/../.."
BUILD_DIR="${SCRIPT_DIR}/../.build/cbmpc-wasm"
OPENSSL_DIR="${SCRIPT_DIR}/../.build/openssl-wasm-install"
OUTPUT_DIR="${SCRIPT_DIR}/../src/wasm"

if [ ! -d "${OPENSSL_DIR}" ]; then
  echo "Error: OpenSSL WASM not built. Run ./openssl-wasm.sh first."
  exit 1
fi

# Find OpenSSL lib directory
OPENSSL_LIB="${OPENSSL_DIR}/lib"
if [ ! -f "${OPENSSL_LIB}/libcrypto.a" ]; then
  OPENSSL_LIB="${OPENSSL_DIR}/lib64"
fi

mkdir -p "${BUILD_DIR}" "${OUTPUT_DIR}"
cd "${BUILD_DIR}"

# Configure with Emscripten
emcmake cmake "${ROOT_DIR}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_TESTS=OFF \
  -DCBMPC_OPENSSL_ROOT="${OPENSSL_DIR}" \
  -DCMAKE_C_FLAGS="-O3 -fPIC" \
  -DCMAKE_CXX_FLAGS="-O3 -fPIC"

emmake make -j$(nproc 2>/dev/null || sysctl -n hw.ncpu) cbmpc

# Link into WASM module with exported functions
emcc \
  -O3 \
  -s WASM=1 \
  -s MODULARIZE=1 \
  -s EXPORT_ES6=1 \
  -s EXPORT_NAME="createCBMPC" \
  -s EXPORTED_FUNCTIONS='["_cbmpc_wasm_malloc","_cbmpc_wasm_free","_cbmpc_wasm_ecdsa2p_dkg","_cbmpc_wasm_ecdsa2p_sign","_cbmpc_wasm_ecdsa_verify"]' \
  -s EXPORTED_RUNTIME_METHODS='["ccall","cwrap","addFunction","removeFunction","HEAPU8","setValue","getValue"]' \
  -s ALLOW_TABLE_GROWTH=1 \
  -s ALLOW_MEMORY_GROWTH=1 \
  -s INITIAL_MEMORY=16777216 \
  -s MAXIMUM_MEMORY=134217728 \
  -s ENVIRONMENT=web \
  -s NO_FILESYSTEM=1 \
  -s SINGLE_FILE=0 \
  --no-entry \
  "${BUILD_DIR}/lib/Release/libcbmpc.a" \
  "${OPENSSL_LIB}/libcrypto.a" \
  -o "${OUTPUT_DIR}/cbmpc.js"

echo ""
echo "WASM build complete:"
ls -la "${OUTPUT_DIR}/cbmpc.js" "${OUTPUT_DIR}/cbmpc.wasm"
echo ""
echo "Copy these to key-server/src/wasm/ for deployment"
```

- [ ] **Step 5: Make scripts executable**

```bash
chmod +x key-server/build/build-wasm.sh key-server/build/openssl-wasm.sh
```

- [ ] **Step 6: Commit**

```bash
git add src/cbmpc/wasm/ key-server/build/ CMakeLists.txt
git commit -m "feat(wasm): add WASM FFI layer and Emscripten build scripts for cbmpc"
```

---

### Task 7: WASM JS wrapper for CF Worker

**Files:**
- Create: `key-server/src/wasm/cbmpc-wrapper.ts`

- [ ] **Step 1: Create TypeScript wrapper for WASM module**

`key-server/src/wasm/cbmpc-wrapper.ts`:
```typescript
// TypeScript wrapper for cbmpc WASM module
// The WASM binary is loaded at worker startup

interface CBMPCModule {
  _cbmpc_wasm_malloc(size: number): number;
  _cbmpc_wasm_free(ptr: number): void;
  _cbmpc_wasm_ecdsa2p_dkg(
    role: number,
    curveCode: number,
    sendFn: number,
    recvFn: number,
    outKeyData: number,
    outKeySize: number,
    outPubkey: number,
    outPubkeySize: number
  ): number;
  _cbmpc_wasm_ecdsa2p_sign(
    role: number,
    curveCode: number,
    keyData: number,
    keySize: number,
    sessionId: number,
    sessionIdSize: number,
    msgHash: number,
    msgHashSize: number,
    sendFn: number,
    recvFn: number,
    outSig: number,
    outSigSize: number
  ): number;
  _cbmpc_wasm_ecdsa_verify(
    curveCode: number,
    pubKey: number,
    pubKeySize: number,
    hash: number,
    hashSize: number,
    derSig: number,
    derSigSize: number
  ): number;
  HEAPU8: Uint8Array;
  addFunction(fn: Function, sig: string): number;
  removeFunction(ptr: number): void;
  setValue(ptr: number, value: number, type: string): void;
  getValue(ptr: number, type: string): number;
}

let wasmModule: CBMPCModule | null = null;

export async function initWasm(wasmBinary: ArrayBuffer): Promise<void> {
  // Dynamic import of the Emscripten-generated JS glue
  // In CF Worker, the WASM binary is bundled as a static asset
  const createCBMPC = (await import("./cbmpc.js")).default;
  wasmModule = await createCBMPC({ wasmBinary });
}

function getModule(): CBMPCModule {
  if (!wasmModule) throw new Error("WASM module not initialized. Call initWasm() first.");
  return wasmModule;
}

// Copy JS Uint8Array into WASM heap, returns pointer
function copyToWasm(data: Uint8Array): number {
  const mod = getModule();
  const ptr = mod._cbmpc_wasm_malloc(data.byteLength);
  mod.HEAPU8.set(data, ptr);
  return ptr;
}

// Copy from WASM heap to JS Uint8Array
function copyFromWasm(ptr: number, size: number): Uint8Array {
  const mod = getModule();
  return new Uint8Array(mod.HEAPU8.buffer, ptr, size).slice();
}

export type SendCallback = (receiver: number, data: Uint8Array) => number;
export type RecvCallback = (sender: number) => { data: Uint8Array; error: number };

export interface DKGResult {
  keyShare: Uint8Array;
  publicKey: Uint8Array;
}

export async function runDKG(
  role: number,
  curveCode: number,
  sendCb: SendCallback,
  recvCb: RecvCallback
): Promise<DKGResult> {
  const mod = getModule();

  // Wrap JS callbacks as C function pointers
  const sendFnPtr = mod.addFunction(
    (receiver: number, dataPtr: number, size: number): number => {
      const data = copyFromWasm(dataPtr, size);
      return sendCb(receiver, data);
    },
    "iiii" // returns int, takes (int, ptr, int)
  );

  const recvFnPtr = mod.addFunction(
    (sender: number, outDataPtr: number, outSizePtr: number): number => {
      const result = recvCb(sender);
      if (result.error !== 0) return result.error;
      const wasmPtr = copyToWasm(result.data);
      mod.setValue(outDataPtr, wasmPtr, "i32");
      mod.setValue(outSizePtr, result.data.byteLength, "i32");
      return 0;
    },
    "iiii"
  );

  // Allocate output pointers
  const outKeyDataPtr = mod._cbmpc_wasm_malloc(4);
  const outKeySizePtr = mod._cbmpc_wasm_malloc(4);
  const outPubkeyPtr = mod._cbmpc_wasm_malloc(4);
  const outPubkeySizePtr = mod._cbmpc_wasm_malloc(4);

  try {
    const err = mod._cbmpc_wasm_ecdsa2p_dkg(
      role,
      curveCode,
      sendFnPtr,
      recvFnPtr,
      outKeyDataPtr,
      outKeySizePtr,
      outPubkeyPtr,
      outPubkeySizePtr
    );

    if (err !== 0) {
      throw new Error(`DKG failed with error code: ${err}`);
    }

    const keyDataAddr = mod.getValue(outKeyDataPtr, "i32");
    const keySize = mod.getValue(outKeySizePtr, "i32");
    const pubkeyAddr = mod.getValue(outPubkeyPtr, "i32");
    const pubkeySize = mod.getValue(outPubkeySizePtr, "i32");

    const keyShare = copyFromWasm(keyDataAddr, keySize);
    const publicKey = copyFromWasm(pubkeyAddr, pubkeySize);

    // Free WASM-allocated output buffers
    mod._cbmpc_wasm_free(keyDataAddr);
    mod._cbmpc_wasm_free(pubkeyAddr);

    return { keyShare, publicKey };
  } finally {
    mod._cbmpc_wasm_free(outKeyDataPtr);
    mod._cbmpc_wasm_free(outKeySizePtr);
    mod._cbmpc_wasm_free(outPubkeyPtr);
    mod._cbmpc_wasm_free(outPubkeySizePtr);
    mod.removeFunction(sendFnPtr);
    mod.removeFunction(recvFnPtr);
  }
}

export async function runSign(
  role: number,
  curveCode: number,
  keyShare: Uint8Array,
  sessionId: Uint8Array,
  msgHash: Uint8Array,
  sendCb: SendCallback,
  recvCb: RecvCallback
): Promise<Uint8Array> {
  const mod = getModule();

  const keyPtr = copyToWasm(keyShare);
  const sidPtr = copyToWasm(sessionId);
  const hashPtr = copyToWasm(msgHash);

  const sendFnPtr = mod.addFunction(
    (receiver: number, dataPtr: number, size: number): number => {
      const data = copyFromWasm(dataPtr, size);
      return sendCb(receiver, data);
    },
    "iiii"
  );

  const recvFnPtr = mod.addFunction(
    (sender: number, outDataPtr: number, outSizePtr: number): number => {
      const result = recvCb(sender);
      if (result.error !== 0) return result.error;
      const wasmPtr = copyToWasm(result.data);
      mod.setValue(outDataPtr, wasmPtr, "i32");
      mod.setValue(outSizePtr, result.data.byteLength, "i32");
      return 0;
    },
    "iiii"
  );

  const outSigPtr = mod._cbmpc_wasm_malloc(4);
  const outSigSizePtr = mod._cbmpc_wasm_malloc(4);

  try {
    const err = mod._cbmpc_wasm_ecdsa2p_sign(
      role,
      curveCode,
      keyPtr,
      keyShare.byteLength,
      sidPtr,
      sessionId.byteLength,
      hashPtr,
      msgHash.byteLength,
      sendFnPtr,
      recvFnPtr,
      outSigPtr,
      outSigSizePtr
    );

    if (err !== 0) {
      throw new Error(`Sign failed with error code: ${err}`);
    }

    const sigAddr = mod.getValue(outSigPtr, "i32");
    const sigSize = mod.getValue(outSigSizePtr, "i32");
    const sig = copyFromWasm(sigAddr, sigSize);
    mod._cbmpc_wasm_free(sigAddr);

    return sig;
  } finally {
    mod._cbmpc_wasm_free(keyPtr);
    mod._cbmpc_wasm_free(sidPtr);
    mod._cbmpc_wasm_free(hashPtr);
    mod._cbmpc_wasm_free(outSigPtr);
    mod._cbmpc_wasm_free(outSigSizePtr);
    mod.removeFunction(sendFnPtr);
    mod.removeFunction(recvFnPtr);
  }
}

export function verify(
  curveCode: number,
  publicKey: Uint8Array,
  hash: Uint8Array,
  derSig: Uint8Array
): boolean {
  const mod = getModule();
  const pubPtr = copyToWasm(publicKey);
  const hashPtr = copyToWasm(hash);
  const sigPtr = copyToWasm(derSig);

  try {
    return mod._cbmpc_wasm_ecdsa_verify(
      curveCode,
      pubPtr, publicKey.byteLength,
      hashPtr, hash.byteLength,
      sigPtr, derSig.byteLength
    ) === 0;
  } finally {
    mod._cbmpc_wasm_free(pubPtr);
    mod._cbmpc_wasm_free(hashPtr);
    mod._cbmpc_wasm_free(sigPtr);
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add key-server/src/wasm/cbmpc-wrapper.ts
git commit -m "feat(key-server): add TypeScript WASM wrapper for cbmpc DKG/sign/verify"
```

---

### Task 8: Build WASM module

- [ ] **Step 1: Install Emscripten if not present**

```bash
if ! command -v emcc &>/dev/null; then
  brew install emscripten
fi
emcc --version
```

- [ ] **Step 2: Build OpenSSL for WASM**

```bash
cd key-server && bash build/openssl-wasm.sh
```

Expected: OpenSSL builds without errors, `libcrypto.a` exists in `.build/openssl-wasm-install/lib/`.

- [ ] **Step 3: Build cbmpc WASM**

```bash
cd key-server && bash build/build-wasm.sh
```

Expected: `src/wasm/cbmpc.js` and `src/wasm/cbmpc.wasm` created.

- [ ] **Step 4: Verify WASM module size**

```bash
ls -lh key-server/src/wasm/cbmpc.wasm
```

Expected: 2-5 MB. CF Workers support up to 10 MB for paid plans.

- [ ] **Step 5: Commit WASM artifacts (or add to .gitignore if too large)**

```bash
# If < 5MB, commit directly
git add key-server/src/wasm/cbmpc.wasm key-server/src/wasm/cbmpc.js
git commit -m "feat(key-server): add compiled cbmpc WASM module"

# If too large, add to .gitignore and document build steps
echo "key-server/src/wasm/cbmpc.wasm" >> .gitignore
echo "key-server/src/wasm/cbmpc.js" >> .gitignore
git add .gitignore
git commit -m "chore: gitignore large WASM build artifacts"
```

---

## Chunk 3: Wire WASM into DKGSession + iOS Integration

### Task 9: Integrate WASM into DKGSession DO

**Files:**
- Modify: `key-server/src/durable-objects/dkg-session.ts`

- [ ] **Step 1: Add WASM initialization and server party logic to DKGSession**

Update `dkg-session.ts` to import and use the WASM wrapper. The server acts as party 1 (role=1). When a device connects and sends DKG messages, the server party processes them through the WASM module and sends responses back.

Key changes:
- Import `initWasm`, `runDKG` from `../wasm/cbmpc-wrapper`
- Add message queue for the server party (incoming messages from device)
- On receiving a DKG_MSG for the server party, enqueue it
- The WASM `recv_fn` callback dequeues messages
- The WASM `send_fn` callback sends via WebSocket to the device

```typescript
// Add to DKGSession class:
private serverKeyShare: Uint8Array | null = null;
private incomingQueue: Map<number, Uint8Array[]> = new Map(); // sender -> messages

// In webSocketMessage, when message targets server party (receiverPartyId matches server):
// 1. Enqueue the payload
// 2. If DKG is running, the recv callback will pick it up

// After enough participants join, start DKG:
private async startServerDKG(): Promise<void> {
  const curveCode = Number(this.getState("curve_code") || 714);

  const sendCb = (receiver: number, data: Uint8Array): number => {
    const target = this.participants.get(receiver);
    if (!target?.ws) return -1;
    const msg = encodeMessage(
      MSG_TYPE.DKG_MSG,
      this.sessionPrefix,
      SERVER_PARTY_ID,
      receiver,
      data
    );
    target.ws.send(msg);
    return 0;
  };

  const recvCb = (sender: number) => {
    const queue = this.incomingQueue.get(sender);
    if (!queue || queue.length === 0) {
      return { data: new Uint8Array(0), error: -1 };
    }
    return { data: queue.shift()!, error: 0 };
  };

  const result = await runDKG(1, curveCode, sendCb, recvCb);
  this.serverKeyShare = result.keyShare;

  // Store in KeyVault
  const pubkeyHex = Array.from(result.publicKey)
    .map(b => b.toString(16).padStart(2, "0"))
    .join("");
  this.setState("public_key", pubkeyHex);
  this.setState("status", "complete");
  this.status = "complete";

  // Notify devices
  for (const [, p] of this.participants) {
    if (p.ws) {
      const completeMsg = encodeMessage(
        MSG_TYPE.DKG_COMPLETE,
        this.sessionPrefix,
        SERVER_PARTY_ID,
        p.partyId,
        result.publicKey
      );
      p.ws.send(completeMsg);
    }
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add key-server/src/durable-objects/dkg-session.ts
git commit -m "feat(key-server): wire WASM cbmpc into DKGSession for server-side DKG"
```

---

### Task 10: Add server URL to iOS app

**Files:**
- Modify: `CBMPCNative/CBMPCNative/Models/PairingManager.swift`
- Modify: `CBMPCNative/CBMPCNative/Views/ServerRegistrationView.swift`
- Modify: `CBMPCNative/CBMPCNative/Views/SettingsView.swift`

- [ ] **Step 1: Add default server URL constant**

In `PairingManager.swift`, add a constant for the deployed key server URL:
```swift
static let defaultKeyServerURL = "https://cb-mpc-key-server.<subdomain>.workers.dev"
```

The exact URL will be filled in after deployment (Task 5).

- [ ] **Step 2: Pre-populate server URL in ServerRegistrationView**

Update `ServerRegistrationView.swift` to show the default key server as a pre-populated option:
```swift
@State private var serverURL: String = PairingManager.defaultKeyServerURL
```

- [ ] **Step 3: Add server status indicator to SettingsView**

Add a row in SettingsView that shows the key server connection status (pings `/health`).

- [ ] **Step 4: Bump version**

Update `project.pbxproj`:
- `MARKETING_VERSION` = "0.7.0" (new feature: server integration)
- `CURRENT_PROJECT_VERSION` = increment by 1

- [ ] **Step 5: Build and verify**

```bash
cd CBMPCNative && xcodebuild -project CBMPCNative.xcodeproj -scheme CBMPCNative -sdk iphoneos -configuration Release -destination 'generic/platform=iOS' -allowProvisioningUpdates build
```

- [ ] **Step 6: Commit**

```bash
git add CBMPCNative/
git commit -m "feat(ios): v0.7.0 -- add key server URL, pre-populate registration"
```

---

### Task 11: WebSocket transport adapter for iOS

**Files:**
- Create: `CBMPCNative/CBMPCNative/Models/WebSocketTransport.swift`

- [ ] **Step 1: Create WebSocket transport that implements CBMPCTransportInterface**

```swift
import Foundation

/// Transport adapter that sends/receives MPC protocol messages over WebSocket
/// to the CF Worker key server. Replaces LocalPartyTransportAdapter for
/// server-backed DKG and signing.
actor WebSocketTransport {
    private let url: URL
    private let token: String
    private let deviceId: String
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var incomingQueue: [Data] = []
    private var continuation: CheckedContinuation<Data, Error>?

    init(serverURL: String, sessionId: String, token: String, deviceId: String) {
        var urlStr = "\(serverURL)/sessions/\(sessionId)/ws"
        urlStr += "?token=\(token)&device_id=\(deviceId)"
        self.url = URL(string: urlStr)!
        self.token = token
        self.deviceId = deviceId
    }

    func connect() async throws {
        let session = URLSession(configuration: .default)
        self.session = session
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        // Start receive loop
        Task { await receiveLoop() }
    }

    func send(to partyId: Int, data: Data) async throws {
        guard let task = task else { throw TransportError.notConnected }
        // Encode as binary protocol message
        var header = Data(count: 13)
        header[0] = 0x01 // DKG_MSG
        // session prefix (4 bytes) -- server will validate
        header[1] = 0; header[2] = 0; header[3] = 0; header[4] = 0
        // sender party ID (2 bytes, big-endian) -- 0 for device
        header[5] = 0; header[6] = 0
        // receiver party ID
        header[7] = UInt8((partyId >> 8) & 0xFF)
        header[8] = UInt8(partyId & 0xFF)
        // payload length (4 bytes, big-endian)
        let len = UInt32(data.count)
        header[9] = UInt8((len >> 24) & 0xFF)
        header[10] = UInt8((len >> 16) & 0xFF)
        header[11] = UInt8((len >> 8) & 0xFF)
        header[12] = UInt8(len & 0xFF)

        var message = header
        message.append(data)
        try await task.send(.data(message))
    }

    func receive(from partyId: Int) async throws -> Data {
        if !incomingQueue.isEmpty {
            return incomingQueue.removeFirst()
        }
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
        }
    }

    func disconnect() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        session = nil
    }

    private func receiveLoop() async {
        guard let task = task else { return }
        do {
            while true {
                let message = try await task.receive()
                switch message {
                case .data(let data):
                    if let cont = continuation {
                        self.continuation = nil
                        // Strip header, return payload
                        if data.count > 13 {
                            cont.resume(returning: Data(data[13...]))
                        } else {
                            cont.resume(returning: data)
                        }
                    } else {
                        if data.count > 13 {
                            incomingQueue.append(Data(data[13...]))
                        }
                    }
                case .string:
                    break // ignore text messages
                @unknown default:
                    break
                }
            }
        } catch {
            if let cont = continuation {
                self.continuation = nil
                cont.resume(throwing: error)
            }
        }
    }

    enum TransportError: Error {
        case notConnected
        case timeout
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add CBMPCNative/CBMPCNative/Models/WebSocketTransport.swift
git commit -m "feat(ios): add WebSocket transport adapter for server-backed MPC"
```

---

### Task 12: Deploy final version with WASM

- [ ] **Step 1: Update wrangler.toml to include WASM binding**

Add to `key-server/wrangler.toml`:
```toml
[wasm_modules]
CBMPC_WASM = "src/wasm/cbmpc.wasm"
```

- [ ] **Step 2: Deploy**

```bash
cd key-server && npx wrangler deploy
```

- [ ] **Step 3: Smoke test -- register device + create DKG session**

```bash
# Register
TOKEN=$(curl -s -X POST https://cb-mpc-key-server.<subdomain>.workers.dev/devices/register \
  -H "Content-Type: application/json" \
  -d '{"device_name":"Test","device_type":"iphone","public_key":"aa"}' | jq -r '.token')

# Create DKG session
curl -s -X POST https://cb-mpc-key-server.<subdomain>.workers.dev/sessions/dkg \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"device_id":"test","curve_code":714}'
```

Expected: 201 with session_id and ws_url.

- [ ] **Step 4: Record deployed URL and update iOS constant**

Update `PairingManager.swift` with the actual deployed URL.

- [ ] **Step 5: Final commit**

```bash
git add key-server/ CBMPCNative/
git commit -m "feat(key-server): deploy v0.1.0 with WASM DKG, update iOS server URL"
```

---

## Summary

| Chunk | Tasks | What it delivers |
|-------|-------|-----------------|
| 1 | Tasks 1-5 | Deployed CF Worker with health, device registration, DKG session relay (no WASM yet), key vault stub |
| 2 | Tasks 6-8 | WASM build pipeline: OpenSSL + cbmpc compiled to WASM, JS wrapper |
| 3 | Tasks 9-12 | WASM wired into DKGSession, iOS WebSocket transport, server URL in app, final deployment |

Chunk 1 can be deployed and tested independently -- the server works as a relay even without WASM. Chunk 2 is the heaviest lift (Emscripten toolchain). Chunk 3 wires everything together.
