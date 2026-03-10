import { DurableObject } from "cloudflare:workers";
import { Env, MSG_TYPE } from "../types";
import { decodeMessage } from "../protocol";

// SERVER_PARTY_ID = 0xfe — used when WASM integrated (Chunk 3)

interface Participant {
  deviceId: string;
  partyId: number;
  ws: WebSocket | null;
}

export class SignSession extends DurableObject<Env> {
  private sql: SqlStorage;
  private participants: Map<number, Participant> = new Map();
  private sessionId: string = "";
  private status: "pending" | "active" | "complete" | "failed" = "pending";
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

    // POST /sessions/:id/sign -- create signing session
    if (parts.length === 3 && parts[2] === "sign" && method === "POST") {
      return this.createSession(request);
    }

    // GET /sessions/:id/sign -- status
    if (parts.length === 3 && parts[2] === "sign" && method === "GET") {
      return this.getStatus();
    }

    // GET /sessions/:id/sign/ws -- WebSocket upgrade
    if (parts.length === 4 && parts[2] === "sign" && parts[3] === "ws") {
      return this.handleWebSocket(request, url);
    }

    return Response.json({ error: "Not found" }, { status: 404 });
  }

  private async createSession(request: Request): Promise<Response> {
    const body = await request.json<{
      public_key: string;
      message_hash: string;
      device_id: string;
    }>();

    if (!body.public_key || !body.message_hash || !body.device_id) {
      return Response.json(
        { error: "Missing required fields: public_key, message_hash, device_id" },
        { status: 400 }
      );
    }

    this.sessionId =
      request.headers.get("X-Session-Id") || crypto.randomUUID();
    this.status = "pending";

    const idBytes = new TextEncoder().encode(this.sessionId);
    const hash = await crypto.subtle.digest("SHA-256", idBytes);
    this.sessionPrefix = new Uint8Array(hash).slice(0, 4);

    this.setState("session_id", this.sessionId);
    this.setState("status", this.status);
    this.setState("public_key", body.public_key);
    this.setState("message_hash", body.message_hash);
    this.setState("created_at", String(Date.now()));
    this.setState("creator_device", body.device_id);

    // Auto-cleanup alarm: 5 minutes
    await this.ctx.storage.setAlarm(Date.now() + 5 * 60 * 1000);

    return Response.json(
      {
        session_id: this.sessionId,
        status: this.status,
        public_key: body.public_key,
        message_hash: body.message_hash,
        ws_url: `/sessions/${this.sessionId}/sign/ws`,
      },
      { status: 201 }
    );
  }

  private getStatus(): Response {
    const status = this.getState("status") || "unknown";
    const publicKey = this.getState("public_key");
    const messageHash = this.getState("message_hash");
    return Response.json({
      session_id: this.getState("session_id"),
      status,
      public_key: publicKey,
      message_hash: messageHash,
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
    const partyId = this.participants.size;

    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);

    this.ctx.acceptWebSocket(server, [deviceId, String(partyId)]);

    this.participants.set(partyId, {
      deviceId,
      partyId,
      ws: server,
    });

    if (this.participants.size >= 1) {
      this.status = "active";
      this.setState("status", "active");
    }

    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(
    ws: WebSocket,
    message: ArrayBuffer | string
  ): Promise<void> {
    if (typeof message === "string") {
      try {
        const ctrl = JSON.parse(message);
        if (ctrl.type === "ping") {
          ws.send(JSON.stringify({ type: "pong" }));
        }
      } catch {
        // ignore
      }
      return;
    }

    const decoded = decodeMessage(message);

    // Audit log
    this.sql.exec(
      `INSERT INTO messages (round, sender_party_id, receiver_party_id, payload, created_at)
       VALUES (?, ?, ?, ?, ?)`,
      0,
      decoded.senderPartyId,
      decoded.receiverPartyId,
      new Uint8Array(decoded.payload),
      Date.now()
    );

    // Handle SIGN_COMPLETE
    if (decoded.type === MSG_TYPE.SIGN_COMPLETE) {
      this.status = "complete";
      this.setState("status", "complete");

      // Broadcast completion to all participants
      for (const [, p] of this.participants) {
        if (p.ws) {
          p.ws.send(message);
        }
      }
      return;
    }

    // Route: broadcast (0xff) or unicast
    if (decoded.receiverPartyId === 0xff) {
      for (const [pid, p] of this.participants) {
        if (pid !== decoded.senderPartyId && p.ws) {
          p.ws.send(message);
        }
      }
    } else {
      const target = this.participants.get(decoded.receiverPartyId);
      if (target?.ws) {
        target.ws.send(message);
      }
    }
  }

  async webSocketClose(ws: WebSocket, _code: number): Promise<void> {
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

  async webSocketError(ws: WebSocket, _error: unknown): Promise<void> {
    await this.webSocketClose(ws, 1006);
  }

  async alarm(): Promise<void> {
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
