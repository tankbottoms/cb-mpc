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
      // DO responses have immutable headers — create a new Response to add CORS
      return new Response(response.body, {
        status: response.status,
        statusText: response.statusText,
        headers: { ...Object.fromEntries(response.headers), ...corsHeaders },
      });
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

  // Privacy policy -- no auth
  if (path === "/privacy" && method === "GET") {
    return new Response(privacyPolicyHTML(), {
      headers: { "Content-Type": "text/html;charset=UTF-8" },
    });
  }

  // Privacy policy JSON -- no auth
  if (path === "/privacy.json" && method === "GET") {
    return Response.json(privacyPolicyJSON());
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

function privacyPolicyJSON() {
  return {
    name: "Key MGMT wCB-MPC",
    bundleId: "xyz.atsignhandle.cb-mpc",
    developer: "atsignhandle, LLC",
    contact: {
      email: "rooot [at] atsignhandle [dot] xyz",
    },
    effectiveDate: "2026-03-10",
    dataCollection: "none",
    analytics: false,
    tracking: false,
    thirdPartySharing: false,
    openSource: {
      repository: "https://github.com/tankbottoms/cb-mpc",
      license: "MIT",
      selfHostable: true,
    },
    summary:
      "This application does not collect, store, transmit, or share any personal data, usage analytics, or tracking information. All cryptographic operations occur entirely on-device. The complete source code is open source and available for audit, forking, and self-hosting.",
  };
}

function privacyPolicyHTML(): string {
  const updated = "March 10, 2026";
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Privacy Policy — Key MGMT wCB-MPC</title>
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, "SF Pro", system-ui, sans-serif; max-width: 680px; margin: 2rem auto; padding: 0 1.5rem; line-height: 1.6; color: #1d1d1f; }
  h1 { font-size: 1.8rem; margin-bottom: 0.25rem; }
  h2 { font-size: 1.2rem; margin-top: 2rem; border-bottom: 1px solid #e5e5e5; padding-bottom: 0.4rem; }
  .updated { color: #86868b; font-size: 0.9rem; margin-bottom: 2rem; }
  ul { padding-left: 1.5rem; }
  li { margin-bottom: 0.4rem; }
  a { color: #0066cc; }
  .contact { background: #f5f5f7; padding: 1rem 1.25rem; border-radius: 8px; margin-top: 2rem; }
  .contact p { margin: 0.25rem 0; }
  footer { margin-top: 3rem; font-size: 0.85rem; color: #86868b; }
</style>
</head>
<body>
<h1>Privacy Policy</h1>
<p class="updated">Last updated: ${updated}</p>

<p><strong>Key MGMT wCB-MPC</strong> ("the App") is a threshold cryptographic key management application. This policy explains how we handle your data — in short, we don't collect any.</p>

<h2>No Data Collection</h2>
<p>The App does not collect, store, or transmit any personal data whatsoever. Specifically:</p>
<ul>
  <li>No personal information is collected (name, email, phone, location, identifiers)</li>
  <li>No usage analytics or telemetry are gathered</li>
  <li>No advertising identifiers or tracking pixels are used</li>
  <li>No cookies or fingerprinting techniques are employed</li>
  <li>No crash reports are sent to external services</li>
</ul>

<h2>On-Device Processing</h2>
<p>All cryptographic operations — key generation, signing, verification, and derivation — occur entirely on your device. Private key shares are stored in your device's Keychain and optionally synced to your personal iCloud Keychain (controlled by your Apple ID settings). At no point does key material leave your device except when you explicitly initiate a transfer (QR export, peer pairing, or server registration).</p>

<h2>Optional Server Communication</h2>
<p>If you choose to register an MPC key server for co-signing, the App communicates with that server over WebSocket to perform threshold signing protocols. The server stores only the key share you explicitly provision to it. No personal data, device identifiers, or usage information are transmitted during this process.</p>

<h2>Local Network &amp; Camera</h2>
<p>The App requests local network access for peer-to-peer device pairing (MultipeerConnectivity) and camera access for QR code scanning. These permissions are used solely for their stated purpose and no data from these subsystems is logged or transmitted.</p>

<h2>No Logs</h2>
<p>Neither the App nor the optional key server maintain access logs, request logs, or any form of persistent logging that could identify users or their activities.</p>

<h2>Open Source</h2>
<p>The complete source code for both the iOS application and the key server is open source and available for public audit. You are free to fork the repository, modify the code, and host your own key server instance.</p>
<p>Repository: <a href="https://github.com/tankbottoms/cb-mpc">github.com/tankbottoms/cb-mpc</a></p>

<h2>Third-Party Services</h2>
<p>The App integrates with Etherscan's public API for address lookups on Ethereum networks. These requests are made directly from your device and are subject to <a href="https://etherscan.io/privacyPolicy">Etherscan's privacy policy</a>. No personal data is included in these requests beyond the public blockchain address you choose to look up.</p>

<h2>Children's Privacy</h2>
<p>The App is not directed at children under 13 and does not knowingly collect information from children.</p>

<h2>Changes to This Policy</h2>
<p>If this policy changes, the updated version will be posted at this URL with a revised date. Since we collect no data, meaningful changes are unlikely.</p>

<div class="contact">
  <strong>Contact</strong>
  <p>Email: rooot [at] atsignhandle [dot] xyz</p>
</div>

<footer>
  <p>Key MGMT wCB-MPC &middot; Bundle ID: xyz.atsignhandle.cb-mpc &middot; &copy; 2026 atsignhandle, LLC</p>
</footer>
</body>
</html>`;
}
