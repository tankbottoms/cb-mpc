import { MSG_HEADER_SIZE } from "./types";

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
  view.setUint16(5, senderPartyId, false);
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
