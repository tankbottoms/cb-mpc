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

    if (parts.length === 2 && method === "GET") {
      return this.getKey(parts[1]);
    }

    if (parts.length === 2 && method === "POST") {
      return this.storeKey(request, parts[1]);
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

  private async storeKey(request: Request, pubkey: string): Promise<Response> {
    const body = await request.json<{
      curve_code: number;
      server_share: string; // base64
      participant_devices: string[];
    }>();

    if (!body.curve_code || !body.server_share || !body.participant_devices) {
      return Response.json(
        { error: "Missing required fields: curve_code, server_share, participant_devices" },
        { status: 400 }
      );
    }

    // Decode base64 server_share to ArrayBuffer
    const binaryStr = atob(body.server_share);
    const shareBytes = new Uint8Array(binaryStr.length);
    for (let i = 0; i < binaryStr.length; i++) {
      shareBytes[i] = binaryStr.charCodeAt(i);
    }

    await this.storeShare(
      pubkey,
      body.curve_code,
      shareBytes.buffer,
      body.participant_devices
    );

    return Response.json(
      { public_key: pubkey, stored: true },
      { status: 201 }
    );
  }

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

  async getShare(publicKey: string): Promise<ArrayBuffer | null> {
    const rows = this.sql
      .exec("SELECT server_share FROM keys WHERE public_key = ?", publicKey)
      .toArray();
    if (rows.length === 0) return null;

    this.sql.exec(
      "UPDATE keys SET last_used_at = ?, sign_count = sign_count + 1 WHERE public_key = ?",
      Date.now(),
      publicKey
    );

    const raw = rows[0].server_share;
    if (raw instanceof ArrayBuffer) return raw;
    if (ArrayBuffer.isView(raw)) return raw.buffer as ArrayBuffer;
    return null;
  }
}
