import { DurableObject } from "cloudflare:workers";
import { Env } from "../types";
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

    if (path === "/devices/register" && method === "POST") {
      return this.register(request);
    }

    const parts = path.split("/").filter(Boolean);

    if (parts[0] === "devices" && parts.length === 2 && method === "GET") {
      return this.getDevice(parts[1]);
    }

    if (parts[0] === "devices" && parts.length === 2 && method === "DELETE") {
      return this.deleteDevice(parts[1]);
    }

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
        {
          error:
            "Missing required fields: device_name, device_type, public_key",
        },
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

    return Response.json(
      { device_id: deviceId, token, registered_at: now },
      { status: 201 }
    );
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
      .exec(
        "SELECT id, name, device_type, is_online, registered_at FROM devices"
      )
      .toArray();
    return Response.json({ devices: rows });
  }
}
