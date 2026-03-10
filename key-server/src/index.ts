import { Env } from "./types";
import { extractToken, validateToken } from "./auth";

export { DeviceRegistry } from "./durable-objects/device-registry";
export { DKGSession } from "./durable-objects/dkg-session";
export { KeyVault } from "./durable-objects/key-vault";
export { SignSession } from "./durable-objects/sign-session";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Authorization, Content-Type",
};

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders });
    }

    try {
      const response = await route(url, request, env);
      for (const [k, v] of Object.entries(corsHeaders)) {
        response.headers.set(k, v);
      }
      return response;
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : "Internal error";
      return Response.json({ error: msg }, { status: 500, headers: corsHeaders });
    }
  },
};

async function route(url: URL, request: Request, env: Env): Promise<Response> {
  const path = url.pathname;
  const method = request.method;

  // Health -- no auth
  if (path === "/health" && method === "GET") {
    return Response.json({ status: "ok", version: env.VERSION });
  }

  // Registration -- no auth
  if (path === "/devices/register" && method === "POST") {
    const id = env.DEVICE_REGISTRY.idFromName("global");
    return env.DEVICE_REGISTRY.get(id).fetch(request);
  }

  // Everything else requires auth
  const token = extractToken(request, url);
  if (!token) {
    return Response.json({ error: "Missing auth token" }, { status: 401 });
  }
  if (!(await validateToken(token, env.SERVER_SECRET))) {
    return Response.json({ error: "Invalid auth token" }, { status: 401 });
  }

  // Device routes
  if (path.startsWith("/devices/")) {
    const id = env.DEVICE_REGISTRY.idFromName("global");
    return env.DEVICE_REGISTRY.get(id).fetch(request);
  }

  // Session routes
  if (path.startsWith("/sessions/")) {
    const parts = path.split("/").filter(Boolean);

    // POST /sessions/dkg
    if (parts.length === 2 && parts[1] === "dkg" && method === "POST") {
      const sessionId = crypto.randomUUID();
      const doId = env.DKG_SESSION.idFromName(sessionId);
      const newHeaders = new Headers(request.headers);
      newHeaders.set("X-Session-Id", sessionId);
      const newReq = new Request(request.url, {
        method: request.method,
        headers: newHeaders,
        body: request.body,
      });
      return env.DKG_SESSION.get(doId).fetch(newReq);
    }

    // /sessions/:id/sign, /sessions/:id/sign/ws -- signing session
    if (parts.length >= 3 && parts[2] === "sign") {
      const sessionId = parts[1];
      const signId = `sign-${sessionId}`;
      const doId = env.SIGN_SESSION.idFromName(signId);
      const newHeaders = new Headers(request.headers);
      newHeaders.set("X-Session-Id", signId);
      const newReq = new Request(request.url, {
        method: request.method,
        headers: newHeaders,
        body: request.body,
      });
      return env.SIGN_SESSION.get(doId).fetch(newReq);
    }

    // /sessions/:id, /sessions/:id/ws -- DKG session
    if (parts.length >= 2) {
      const sessionId = parts[1];
      const doId = env.DKG_SESSION.idFromName(sessionId);
      return env.DKG_SESSION.get(doId).fetch(request);
    }
  }

  // Key routes
  if (path.startsWith("/keys")) {
    const parts = path.split("/").filter(Boolean);
    if (parts.length === 1 && method === "GET") {
      const id = env.DEVICE_REGISTRY.idFromName("global");
      return env.DEVICE_REGISTRY.get(id).fetch(request);
    }
    if (parts.length === 2) {
      const vaultId = env.KEY_VAULT.idFromName(parts[1]);
      return env.KEY_VAULT.get(vaultId).fetch(request);
    }
  }

  return Response.json({ error: "Not found" }, { status: 404 });
}
