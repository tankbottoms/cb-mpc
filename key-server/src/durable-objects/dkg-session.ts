import { DurableObject } from "cloudflare:workers";
import { Env, MSG_TYPE } from "../types";
import { encodeMessage, decodeMessage } from "../protocol";

const SERVER_PARTY_ID = 0xfe; // server is always party 254

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
  private curveCode: number = 714;
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

    // POST /sessions/:id/sign
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

    this.sessionId =
      request.headers.get("X-Session-Id") || crypto.randomUUID();
    this.curveCode = body.curve_code || 714;
    this.status = "pending";

    const idBytes = new TextEncoder().encode(this.sessionId);
    const hash = await crypto.subtle.digest("SHA-256", idBytes);
    this.sessionPrefix = new Uint8Array(hash).slice(0, 4);

    this.setState("session_id", this.sessionId);
    this.setState("status", this.status);
    this.setState("curve_code", String(this.curveCode));
    this.setState("created_at", String(Date.now()));
    this.setState("creator_device", body.device_id);

    // Auto-cleanup alarm: 5 minutes
    await this.ctx.storage.setAlarm(Date.now() + 5 * 60 * 1000);

    return Response.json(
      {
        session_id: this.sessionId,
        status: this.status,
        curve_code: this.curveCode,
        ws_url: `/sessions/${this.sessionId}/ws`,
      },
      { status: 201 }
    );
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

    // TODO: When WASM is integrated (Chunk 3), the server party
    // processes messages here via cbmpc WASM and generates responses
  }

  async webSocketClose(ws: WebSocket, code: number): Promise<void> {
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
