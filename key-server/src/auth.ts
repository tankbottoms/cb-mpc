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

export function extractToken(request: Request, url: URL): string | null {
  const authHeader = request.headers.get("Authorization");
  if (authHeader?.startsWith("Bearer ")) {
    return authHeader.slice(7);
  }
  return url.searchParams.get("token");
}

export async function validateToken(
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
