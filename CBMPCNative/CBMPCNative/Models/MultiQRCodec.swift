import Foundation
import CryptoKit

struct MultiQRCodec {
    enum CodecError: Error {
        case compressionFailed
        case decompressionFailed
        case encryptionFailed
        case decryptionFailed
        case invalidMagic
        case invalidVersion
        case crcMismatch
        case missingParts
    }

    // Header constants
    private static let magic: [UInt8] = [0x43, 0x42, 0x4D, 0x50, 0x43] // "CBMPC"
    private static let version: UInt8 = 1
    private static let commonHeaderSize = 10  // magic(5) + version(1) + part#(2) + totalParts(2)
    private static let part0ExtraSize = 22    // compression(1) + encryption(1) + origSize(4) + nonce(12) + crc32(4)
    private static let maxQRBytes = 450       // ~450 bytes binary → ~600 chars base64 → QR version 9-10 (easy to scan)

    // MARK: - Encode

    static func encode(json: Data, passphrase: String?) throws -> [Data] {
        // 1. CRC32 of original
        let checksum = crc32Checksum(json)

        // 2. Compress with zlib
        let compressed = try compress(json)

        // 3. Encrypt with AES-256-GCM
        let key: SymmetricKey
        if let passphrase = passphrase, !passphrase.isEmpty {
            key = deriveKey(from: passphrase)
        } else {
            key = SymmetricKey(size: .bits256)
        }

        let nonce = AES.GCM.Nonce()
        guard let sealedBox = try? AES.GCM.seal(compressed, using: key, nonce: nonce) else {
            throw CodecError.encryptionFailed
        }
        // FIX: Explicitly copy into fresh contiguous Data.
        // sealedBox.ciphertext + sealedBox.tag crashes when subscripted in Release builds
        // due to CryptoKit returning internal slices with non-zero startIndex.
        var encrypted = Data(sealedBox.ciphertext)
        encrypted.append(contentsOf: sealedBox.tag)

        // 4. Calculate even split across parts
        let part0PayloadMax = maxQRBytes - commonHeaderSize - part0ExtraSize
        let numParts = max(1, Int(ceil(Double(encrypted.count) / Double(part0PayloadMax))))
        let baseChunkSize = encrypted.count / numParts
        let remainder = encrypted.count % numParts

        // 5. Split evenly — first 'remainder' chunks get 1 extra byte
        var chunks: [Data] = []
        var offset = 0
        for i in 0..<numParts {
            let thisChunk = baseChunkSize + (i < remainder ? 1 : 0)
            let end = offset + thisChunk
            chunks.append(Data(encrypted[offset..<end]))
            offset = end
        }

        let totalParts = UInt16(chunks.count)
        let nonceBytes = Data(nonce)
        let origSize = UInt32(json.count)

        // 6. Build framed parts
        var parts: [Data] = []
        for (index, chunk) in chunks.enumerated() {
            var frame = Data()

            // Common header
            frame.append(contentsOf: magic)
            frame.append(version)
            frame.appendUInt16BE(UInt16(index))
            frame.appendUInt16BE(totalParts)

            // Part 0 extra header
            if index == 0 {
                frame.append(1) // compression: 1 = zlib
                frame.append(1) // encryption: 1 = AES-256-GCM
                frame.appendUInt32BE(origSize)
                frame.append(nonceBytes)
                frame.appendUInt32BE(checksum)
            }

            frame.append(chunk)
            parts.append(frame)
        }

        return parts
    }

    // MARK: - Decode

    static func decode(parts: [Data], passphrase: String?) throws -> Data {
        guard let first = parts.first, first.count >= commonHeaderSize + part0ExtraSize else {
            throw CodecError.missingParts
        }

        // Validate magic
        guard Array(first.prefix(5)) == magic else {
            throw CodecError.invalidMagic
        }
        guard first[5] == version else {
            throw CodecError.invalidVersion
        }

        let totalParts = first.readUInt16BE(at: 8)
        guard parts.count == Int(totalParts) else {
            throw CodecError.missingParts
        }

        // Parse part 0 extra header
        let extraOffset = commonHeaderSize
        // let compressionType = first[extraOffset]  // 1 = zlib
        // let encryptionType = first[extraOffset + 1]  // 1 = AES-256-GCM
        let origSize = first.readUInt32BE(at: extraOffset + 2)
        let nonceBytes = first.subdata(in: (extraOffset + 6)..<(extraOffset + 18))
        let expectedCRC = first.readUInt32BE(at: extraOffset + 18)

        // Reassemble encrypted data
        var encrypted = Data()
        for (index, part) in parts.enumerated() {
            let payloadStart = index == 0 ? commonHeaderSize + part0ExtraSize : commonHeaderSize
            encrypted.append(part.subdata(in: payloadStart..<part.count))
        }

        // Decrypt
        let key: SymmetricKey
        if let passphrase = passphrase, !passphrase.isEmpty {
            key = deriveKey(from: passphrase)
        } else {
            key = SymmetricKey(size: .bits256)
        }

        let tagSize = 16
        guard encrypted.count > tagSize else { throw CodecError.decryptionFailed }
        let ciphertext = encrypted.prefix(encrypted.count - tagSize)
        let tag = encrypted.suffix(tagSize)

        guard let nonce = try? AES.GCM.Nonce(data: nonceBytes),
              let sealedBox = try? AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag),
              let decrypted = try? AES.GCM.open(sealedBox, using: key) else {
            throw CodecError.decryptionFailed
        }

        // Decompress
        let decompressed = try decompress(decrypted, originalSize: Int(origSize))

        // Verify CRC
        let actualCRC = crc32Checksum(decompressed)
        guard actualCRC == expectedCRC else {
            throw CodecError.crcMismatch
        }

        return decompressed
    }

    // MARK: - Helpers

    static func crc32Checksum(_ data: Data) -> UInt32 {
        // Pure Swift CRC32 (IEEE 802.3 / zlib compatible)
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ (crc & 1 != 0 ? 0xEDB88320 : 0)
            }
        }
        return crc ^ 0xFFFFFFFF
    }

    private static func deriveKey(from passphrase: String) -> SymmetricKey {
        let salt = Data("CBMPC-MultiQR-v1".utf8)
        let inputKey = SymmetricKey(data: Data(passphrase.utf8))
        let derived = HKDF<SHA256>.deriveKey(inputKeyMaterial: inputKey, salt: salt, outputByteCount: 32)
        return derived
    }

    private static func compress(_ data: Data) throws -> Data {
        let nsData = data as NSData
        guard let compressed = try? nsData.compressed(using: .zlib) as Data else {
            throw CodecError.compressionFailed
        }
        return compressed
    }

    private static func decompress(_ data: Data, originalSize: Int) throws -> Data {
        let nsData = data as NSData
        guard let decompressed = try? nsData.decompressed(using: .zlib) as Data else {
            throw CodecError.decompressionFailed
        }
        return decompressed
    }
}

// MARK: - Data Extensions for Binary Encoding

extension Data {
    mutating func appendUInt16BE(_ value: UInt16) {
        var big = value.bigEndian
        append(Data(bytes: &big, count: 2))
    }

    mutating func appendUInt32BE(_ value: UInt32) {
        var big = value.bigEndian
        append(Data(bytes: &big, count: 4))
    }

    func readUInt16BE(at offset: Int) -> UInt16 {
        return (UInt16(self[offset]) << 8) | UInt16(self[offset + 1])
    }

    func readUInt32BE(at offset: Int) -> UInt32 {
        return (UInt32(self[offset]) << 24) | (UInt32(self[offset + 1]) << 16)
             | (UInt32(self[offset + 2]) << 8) | UInt32(self[offset + 3])
    }
}
