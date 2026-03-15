import Foundation

// MARK: - EIP-712 Typed Data Signing

/// Implements EIP-712 structured data hashing per https://eips.ethereum.org/EIPS/eip-712
/// Produces a 32-byte hash suitable for MPC signing.
struct EIP712Signer {

    struct TypedData {
        let types: [String: [TypeField]]
        let primaryType: String
        let domain: [String: Any]
        let message: [String: Any]
    }

    struct TypeField {
        let name: String
        let type: String
    }

    /// Compute the EIP-712 hash: keccak256("\x19\x01" || domainSeparator || structHash(message))
    static func hashTypedData(_ typedData: TypedData) -> Data {
        let domainSeparator = hashStruct("EIP712Domain", data: typedData.domain, types: typedData.types)
        let messageHash = hashStruct(typedData.primaryType, data: typedData.message, types: typedData.types)

        var preimage = Data([0x19, 0x01])
        preimage.append(domainSeparator)
        preimage.append(messageHash)
        return Keccak256.hash(preimage)
    }

    /// Parse EIP-712 typed data from JSON (as returned by Uniswap, CoW, Safe APIs)
    static func parseTypedData(from json: [String: Any]) -> TypedData? {
        guard let typesRaw = json["types"] as? [String: [[String: String]]],
              let primaryType = json["primaryType"] as? String,
              let domain = json["domain"] as? [String: Any],
              let message = json["message"] as? [String: Any] else {
            return nil
        }

        var types: [String: [TypeField]] = [:]
        for (typeName, fields) in typesRaw {
            types[typeName] = fields.compactMap { field in
                guard let name = field["name"], let type = field["type"] else { return nil }
                return TypeField(name: name, type: type)
            }
        }

        return TypedData(types: types, primaryType: primaryType, domain: domain, message: message)
    }

    // MARK: - Internal

    /// hashStruct(s) = keccak256(typeHash || encodeData(s))
    private static func hashStruct(_ typeName: String, data: [String: Any], types: [String: [TypeField]]) -> Data {
        let typeHash = Keccak256.hash(Data(encodeType(typeName, types: types).utf8))
        var encoded = typeHash
        if let fields = types[typeName] {
            for field in fields {
                let value = data[field.name]
                encoded.append(encodeField(field.type, value: value, types: types))
            }
        }
        return Keccak256.hash(encoded)
    }

    /// Encode the type string recursively
    private static func encodeType(_ typeName: String, types: [String: [TypeField]]) -> String {
        guard let fields = types[typeName] else { return "" }
        let selfEncoding = "\(typeName)(\(fields.map { "\($0.type) \($0.name)" }.joined(separator: ",")))"

        // Find referenced types (excluding self and atomic types)
        var referenced = Set<String>()
        func findRefs(_ name: String) {
            guard let typeFields = types[name] else { return }
            for field in typeFields {
                let baseType = field.type.replacingOccurrences(of: "[]", with: "")
                if types[baseType] != nil && baseType != typeName && !referenced.contains(baseType) {
                    referenced.insert(baseType)
                    findRefs(baseType)
                }
            }
        }
        findRefs(typeName)

        let sortedRefs = referenced.sorted().map { refName -> String in
            guard let refFields = types[refName] else { return "" }
            return "\(refName)(\(refFields.map { "\($0.type) \($0.name)" }.joined(separator: ",")))"
        }

        return selfEncoding + sortedRefs.joined()
    }

    /// Encode a single field value to 32 bytes
    private static func encodeField(_ type: String, value: Any?, types: [String: [TypeField]]) -> Data {
        if type == "string" {
            let str = (value as? String) ?? ""
            return Keccak256.hash(Data(str.utf8))
        }
        if type == "bytes" {
            let bytes = parseBytes(value)
            return Keccak256.hash(bytes)
        }
        if type == "address" {
            let addr = (value as? String) ?? "0x0000000000000000000000000000000000000000"
            return padLeft(addressToBytes(addr), to: 32)
        }
        if type == "bool" {
            let b: Bool
            if let boolVal = value as? Bool {
                b = boolVal
            } else if let intVal = value as? Int {
                b = intVal != 0
            } else {
                b = false
            }
            return padLeft(Data([b ? 1 : 0]), to: 32)
        }
        if type.hasPrefix("uint") || type.hasPrefix("int") {
            return encodeInteger(value, type: type)
        }
        if type.hasPrefix("bytes") && type.count > 5 {
            // bytesN (fixed-size)
            let bytes = parseBytes(value)
            return padRight(bytes, to: 32)
        }
        if type.hasSuffix("[]") {
            // Array type — hash concatenation of encoded elements
            let elementType = String(type.dropLast(2))
            guard let array = value as? [Any] else {
                return Keccak256.hash(Data())
            }
            var encoded = Data()
            for item in array {
                encoded.append(encodeField(elementType, value: item, types: types))
            }
            return Keccak256.hash(encoded)
        }
        // Struct type
        if let dict = value as? [String: Any], types[type] != nil {
            return hashStruct(type, data: dict, types: types)
        }
        // Default: zero-padded
        return Data(repeating: 0, count: 32)
    }

    private static func encodeInteger(_ value: Any?, type: String) -> Data {
        let bigVal: UInt64
        if let intVal = value as? Int { bigVal = UInt64(intVal) }
        else if let uint = value as? UInt64 { bigVal = uint }
        else if let str = value as? String {
            if str.hasPrefix("0x") {
                bigVal = UInt64(str.dropFirst(2), radix: 16) ?? 0
            } else {
                bigVal = UInt64(str) ?? 0
            }
        } else { bigVal = 0 }

        var bytes = Data(repeating: 0, count: 32)
        var val = bigVal
        for i in stride(from: 31, through: 24, by: -1) {
            bytes[i] = UInt8(val & 0xFF)
            val >>= 8
        }
        return bytes
    }

    private static func addressToBytes(_ addr: String) -> Data {
        let hex = addr.hasPrefix("0x") ? String(addr.dropFirst(2)) : addr
        return hexToData(hex)
    }

    private static func parseBytes(_ value: Any?) -> Data {
        if let data = value as? Data { return data }
        if let str = value as? String {
            let hex = str.hasPrefix("0x") ? String(str.dropFirst(2)) : str
            return hexToData(hex)
        }
        return Data()
    }

    private static func hexToData(_ hex: String) -> Data {
        var data = Data()
        var i = hex.startIndex
        while i < hex.endIndex {
            let next = hex.index(i, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            if let byte = UInt8(hex[i..<next], radix: 16) {
                data.append(byte)
            }
            i = next
        }
        return data
    }

    private static func padLeft(_ data: Data, to size: Int) -> Data {
        if data.count >= size { return Data(data.prefix(size)) }
        return Data(repeating: 0, count: size - data.count) + data
    }

    private static func padRight(_ data: Data, to size: Int) -> Data {
        if data.count >= size { return Data(data.prefix(size)) }
        return data + Data(repeating: 0, count: size - data.count)
    }
}

// MARK: - Keccak-256

/// Pure Swift Keccak-256 implementation (Ethereum's hash function).
/// This is NOT NIST SHA3-256 — Ethereum uses the original Keccak with 0x01 padding,
/// not NIST's 0x06 padding.
struct Keccak256 {

    static func hash(_ data: Data) -> Data {
        var state = [UInt64](repeating: 0, count: 25)
        let rate = 136 // (1600 - 2*256) / 8 = 136 bytes
        var input = Array(data)

        // Pad: Keccak uses 0x01...0x80 (NOT SHA3's 0x06...0x80)
        input.append(0x01)
        while input.count % rate != (rate - 1) {
            input.append(0x00)
        }
        input.append(0x80)

        // Absorb
        for offset in stride(from: 0, to: input.count, by: rate) {
            for i in 0..<(rate / 8) {
                let idx = offset + i * 8
                var word: UInt64 = 0
                for b in 0..<8 {
                    word |= UInt64(input[idx + b]) << (b * 8)
                }
                state[i] ^= word
            }
            keccakF1600(&state)
        }

        // Squeeze (256 bits = 32 bytes = 4 words)
        var result = Data(capacity: 32)
        for i in 0..<4 {
            var word = state[i]
            for _ in 0..<8 {
                result.append(UInt8(word & 0xFF))
                word >>= 8
            }
        }
        return result
    }

    // MARK: - Keccak-f[1600] permutation

    private static let roundConstants: [UInt64] = [
        0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
        0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
        0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
        0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
        0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
        0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
    ]

    private static let rotationOffsets: [Int] = [
         0,  1, 62, 28, 27,
        36, 44,  6, 55, 20,
         3, 10, 43, 25, 39,
        41, 45, 15, 21,  8,
        18,  2, 61, 56, 14,
    ]

    private static let piIndices: [Int] = [
         0, 10, 20,  5, 15,
        16,  1, 11, 21,  6,
         7, 17,  2, 12, 22,
        23,  8, 18,  3, 13,
        14, 24,  9, 19,  4,
    ]

    private static func keccakF1600(_ state: inout [UInt64]) {
        for round in 0..<24 {
            // Theta
            var c = [UInt64](repeating: 0, count: 5)
            for x in 0..<5 {
                c[x] = state[x] ^ state[x + 5] ^ state[x + 10] ^ state[x + 15] ^ state[x + 20]
            }
            for x in 0..<5 {
                let d = c[(x + 4) % 5] ^ rotl64(c[(x + 1) % 5], 1)
                for y in stride(from: 0, to: 25, by: 5) {
                    state[y + x] ^= d
                }
            }

            // Rho + Pi
            var b = [UInt64](repeating: 0, count: 25)
            for i in 0..<25 {
                b[piIndices[i]] = rotl64(state[i], rotationOffsets[i])
            }

            // Chi
            for y in stride(from: 0, to: 25, by: 5) {
                for x in 0..<5 {
                    state[y + x] = b[y + x] ^ (~b[y + (x + 1) % 5] & b[y + (x + 2) % 5])
                }
            }

            // Iota
            state[0] ^= roundConstants[round]
        }
    }

    private static func rotl64(_ x: UInt64, _ n: Int) -> UInt64 {
        (x << n) | (x >> (64 - n))
    }
}
