export interface Env {
  DEVICE_REGISTRY: DurableObjectNamespace;
  DKG_SESSION: DurableObjectNamespace;
  KEY_VAULT: DurableObjectNamespace;
  SIGN_SESSION: DurableObjectNamespace;
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

export interface SignSessionState {
  id: string;
  status: "pending" | "active" | "complete" | "failed";
  publicKey: string;
  messageHash: string;
  participants: string[];
  createdAt: number;
}

// Binary message header: [type:1][session_prefix:4][sender:2][receiver:2][payload_len:4][payload:N]
export const MSG_HEADER_SIZE = 13;
