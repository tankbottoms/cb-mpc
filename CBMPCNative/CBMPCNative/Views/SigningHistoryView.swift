import SwiftUI

struct SigningHistoryView: View {
    @EnvironmentObject var keyStore: KeyStore

    var allSignings: [SigningRecord] {
        let real = keyStore.keys
            .flatMap { $0.signingRecords }
            .sorted { $0.timestamp > $1.timestamp }
        return real.isEmpty ? Self.sampleSignings : real
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(allSignings) { record in
                    HStack(alignment: .center, spacing: 8) {
                        if record.verified {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.red)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.timestamp.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 10, design: .monospaced))

                            VStack(alignment: .leading, spacing: 1) {
                                Text(record.messageHash)
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Text(record.signatureDisplay)
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundColor(.secondary.opacity(0.7))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.plain)
            .navigationTitle("History")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    // Sample data for when no real signings exist
    static let sampleSignings: [SigningRecord] = {
        let now = Date()
        return [
            SigningRecord(
                id: UUID(),
                messageHash: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
                signature: "3045022100a3f20e4c8b9d1a6e7f2b3c4d5e6f7081929a3b4c5d6e7f8091a2b3c4d5e6f7b7c4",
                timestamp: now.addingTimeInterval(-120),
                verified: true
            ),
            SigningRecord(
                id: UUID(),
                messageHash: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                signature: "30440220784e3a1b5c9d2e4f6a8b0c1d3e5f7a9b2c4d6e8f0a1b3c5d7e9f0a2b4c6d9a12",
                timestamp: now.addingTimeInterval(-3600),
                verified: true
            ),
            SigningRecord(
                id: UUID(),
                messageHash: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
                signature: "3046022100d8b2a1c3e5f7091b3d5f7a9c1e3f5a7b9d1e3f5a7c9e1f3a5c7e9b1d3f5a4f01",
                timestamp: now.addingTimeInterval(-7200),
                verified: true
            ),
            SigningRecord(
                id: UUID(),
                messageHash: "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592",
                signature: "3045022100e1c7b3a5d7f9012b4c6e8f0a2c4e6a8c0e2a4c6e8f0b2d4f6a8c0e2a4c6b33",
                timestamp: now.addingTimeInterval(-86400),
                verified: true
            ),
            SigningRecord(
                id: UUID(),
                messageHash: "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
                signature: "3044022039af1b3d5e7f9a1c3e5a7c9e1f3b5d7f9a1c3e5a7c9e1f3b5d7f9a1c3ec821",
                timestamp: now.addingTimeInterval(-172800),
                verified: false
            ),
        ]
    }()
}

#Preview {
    SigningHistoryView()
        .environmentObject(KeyStore())
}
