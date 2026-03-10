# CB-MPC Key Server -- Cloudflare Worker Design Spec

**Date:** 2026-03-10
**Status:** Approved
**Scope:** Full coordination server with active MPC participation

## Overview

A Cloudflare Worker with Durable Objects serving as an active MPC participant in the DKG protocol. The server holds a real key share and participates in threshold signing. Devices connect via WebSocket for real-time DKG message relay. The C++ cbmpc library runs as WASM inside the Worker. Cloudflare provides SSL automatically -- a hard requirement for DKG and commitment exchange.

## Architecture

### Durable Object Classes

1. **DeviceRegistry** (singleton) -- tracks all registered devices, auth tokens, online status
2. **DKGSession** (per-session) -- manages the 4-round DKG commitment exchange between parties via WebSocket, with the server itself running as one MPC party (cbmpc WASM)
3. **KeyVault** (per-key) -- stores the server's key share, handles signing requests, tracks key metadata

### Data Flow: 3-Party DKG

```
iPhone ──WebSocket──> DKGSession DO <──WebSocket── Paired Device
                          │
                     Server Party
                    (cbmpc WASM)
                          │
                     KeyVault DO
                   (stores server share)
```

1. iPhone creates DKG session via REST → gets session ID
2. Both devices + server connect as 3 parties to the DKGSession DO
3. DKG commitment exchange runs over WebSocket (4 rounds):
   - Round 1 (P1→P2): `sid1` + commitment hash (`com.msg`)
   - Round 2 (P2→P1): `sid2` + Schnorr proof (`pi_2`) + public key share (`Q2`)
   - Round 3 (P1→P2): commitment randomness (`com.rand`) + Schnorr proof (`pi_1`) + public key share (`Q1`)
   - Round 4 (implicit): all parties derive shared public key `Q`
4. Each party ends up with their key share + shared public key
5. Server's share persists in KeyVault DO (SQLite)
6. Devices store their shares locally (Keychain)

### WebSocket Message Protocol

All messages are binary frames. Each message has a fixed header:

```
[1 byte: message_type][4 bytes: session_id_prefix][2 bytes: sender_party_id][2 bytes: receiver_party_id][4 bytes: payload_length][N bytes: payload]
```

Message types:

| Type | Value | Direction | Purpose |
|------|-------|-----------|---------|
| DKG_MSG | 0x01 | device→server→device | DKG protocol message relay |
| DKG_COMPLETE | 0x02 | server→device | DKG completed, public key confirmed |
| SIGN_REQUEST | 0x03 | device→server | Request threshold signature |
| SIGN_MSG | 0x04 | bidirectional | Signing protocol message |
| SIGN_COMPLETE | 0x05 | server→device | Signature complete |
| ERROR | 0xFF | server→device | Protocol error, abort |

### REST Endpoints

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| POST | `/devices/register` | none | Register device, returns auth token |
| GET | `/devices/:id` | token | Device info + online status |
| DELETE | `/devices/:id` | token | Unregister device |
| POST | `/sessions/dkg` | token | Create DKG session (returns session ID + WS URL) |
| GET | `/sessions/:id` | token | Session status (pending/active/complete/failed) |
| WS | `/sessions/:id/ws` | token (query param) | WebSocket for DKG/signing message relay |
| POST | `/sessions/:id/sign` | token | Initiate threshold signing request |
| GET | `/keys` | token | List keys this device participates in |
| GET | `/keys/:pubkey` | token | Key metadata (participants, creation date, curve) |
| GET | `/health` | none | Health check (`{ status, version }`) |

### Authentication

- **Registration:** Device POSTs `{ device_name, device_type, public_key }`. Server generates `token = UUID + "." + HMAC-SHA256(SERVER_SECRET, device_id)`. Returns `{ device_id, token }`.
- **Subsequent requests:** `Authorization: Bearer <token>` header. Server validates by splitting token, recomputing HMAC, comparing.
- **WebSocket auth:** Token passed as `?token=<token>` query parameter on upgrade.
- **Server secret:** Stored as CF Worker secret (`wrangler secret put SERVER_SECRET`).

### WASM Module (cbmpc)

The C++ cbmpc library compiled via Emscripten to WASM, exposing:

- `cbmpc_ecdsa2p_dkg(job, curve_code, out_key)` -- 2-party DKG (server as one party)
- `cbmpc_ecdsa2p_sign(job, key_share, curve_code, message_hash, out_sig)` -- threshold sign
- `cbmpc_job_create() / cbmpc_job_send() / cbmpc_job_receive()` -- transport callbacks wired to WebSocket

**Build chain:** OpenSSL (WASM) + secp256k1 (WASM) + cbmpc (WASM) → single `.wasm` module (~2-5 MB estimated).

**Transport adapter:** The WASM module's send/receive callbacks are wired to the Durable Object's WebSocket. When the server party calls `send(party_id, data)`, the DO routes the message to the correct device's WebSocket connection. When a device sends a message, the DO calls `receive()` on the WASM module.

### Storage Schema (Durable Object SQLite)

**DeviceRegistry DO:**

```sql
CREATE TABLE devices (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  device_type TEXT NOT NULL,  -- 'iphone', 'ipad', 'mac'
  public_key TEXT NOT NULL,   -- device's X25519 public key (hex)
  token_hash TEXT NOT NULL,   -- SHA256 of auth token
  registered_at INTEGER NOT NULL,
  last_seen_at INTEGER,
  is_online INTEGER DEFAULT 0
);
```

**DKGSession DO:**

```sql
CREATE TABLE session_state (
  key TEXT PRIMARY KEY,
  value BLOB
);
-- Stores: participants list, current round, messages per round,
-- server party state (serialized WASM memory snapshot), result

CREATE TABLE messages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  round INTEGER NOT NULL,
  sender_party_id INTEGER NOT NULL,
  receiver_party_id INTEGER NOT NULL,
  payload BLOB NOT NULL,
  created_at INTEGER NOT NULL
);
```

**KeyVault DO:**

```sql
CREATE TABLE keys (
  public_key TEXT PRIMARY KEY,  -- compressed SEC1 hex (33 bytes for secp256k1)
  curve_code INTEGER NOT NULL,  -- 714 = secp256k1
  server_share BLOB NOT NULL,   -- server's key share (encrypted at rest)
  participant_devices TEXT NOT NULL,  -- JSON array of device IDs
  created_at INTEGER NOT NULL,
  last_used_at INTEGER,
  sign_count INTEGER DEFAULT 0
);
```

### Security

- **SSL:** Cloudflare provides TLS termination on `*.workers.dev` and custom domains. All endpoints HTTPS-only. WebSocket upgrades from HTTPS (wss://). Hard requirement satisfied.
- **Key share at rest:** Server's key share encrypted with a derived key from SERVER_SECRET before SQLite storage. Server alone cannot produce a valid signature (needs threshold cooperation).
- **Session expiry:** DKGSession DOs auto-delete after 5 minutes of inactivity (alarm-based cleanup).
- **Rate limiting:** CF Worker rate limiting rules on `/devices/register` to prevent abuse.
- **No key material in logs:** All logging strips binary payloads, only logs metadata (session ID, round number, party ID).

### Error Handling

- **Device disconnects mid-DKG:** Session enters `failed` state. Other participants notified via WebSocket `ERROR` message. Session auto-cleans after timeout.
- **Invalid commitment:** Server verifies commitment hashes. If verification fails, session aborts with `COMMITMENT_MISMATCH` error.
- **WASM panic:** Caught by the JS wrapper, session marked `failed`, error logged.
- **Token invalid:** 401 response, WebSocket close with code 4001.

## Project Structure

```
key-server/
  wrangler.toml
  src/
    index.ts              -- Worker entry point, router
    auth.ts               -- Token generation, validation
    durable-objects/
      device-registry.ts  -- DeviceRegistry DO class
      dkg-session.ts      -- DKGSession DO class
      key-vault.ts        -- KeyVault DO class
    wasm/
      cbmpc.wasm          -- Compiled WASM module
      cbmpc-wrapper.ts    -- JS bindings for WASM functions
    types.ts              -- Shared types
    protocol.ts           -- Message encoding/decoding
  build/
    build-wasm.sh         -- Emscripten build script for cbmpc
```

## Deployment

```toml
# wrangler.toml
name = "cb-mpc-key-server"
main = "src/index.ts"
compatibility_date = "2026-03-01"

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

Deploy: `wrangler deploy` → `https://cb-mpc-key-server.<account>.workers.dev`

## iOS Integration

After deployment, the server URL is added to:

1. **ServerRegistrationView** -- pre-populated as default server
2. **KeyStore** -- new `createKeyWithServer(serverURL:)` method that initiates 3-party DKG
3. **PairingManager** -- server URL shared during device pairing so both devices know the coordination endpoint
4. **Info.plist** -- `CFBundleURLTypes` or app config for the server base URL

## Success Criteria

- [ ] `GET /health` returns `{ status: "ok", version: "0.1.0" }` over HTTPS
- [ ] Device registration returns valid auth token
- [ ] Two iOS devices + server complete 3-party DKG via WebSocket
- [ ] Resulting public key matches across all three parties
- [ ] Server's key share persists across DO hibernation
- [ ] Threshold signing produces valid ECDSA signature
- [ ] Commitment verification catches tampered messages
