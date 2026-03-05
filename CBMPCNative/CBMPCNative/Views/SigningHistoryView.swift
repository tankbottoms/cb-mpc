import SwiftUI

struct SigningHistoryView: View {
    @EnvironmentObject var keyStore: KeyStore

    var allSignings: [SigningRecord] {
        keyStore.keys
            .flatMap { $0.signingRecords }
            .sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        NavigationStack {
            List {
                if allSignings.isEmpty {
                    #if os(macOS)
                    VStack(alignment: .center, spacing: 12) {
                        Image(systemName: "checkmark.circle.slash")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No Signatures")
                            .font(.headline)
                        Text("Sign a message to see history")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                    #else
                    ContentUnavailableView(
                        "No Signatures",
                        systemImage: "checkmark.circle.slash",
                        description: Text("Sign a message to see history")
                    )
                    #endif
                } else {
                    ForEach(allSignings) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(record.timestamp.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(.caption, design: .monospaced))

                                Spacer()

                                if record.verified {
                                    Label("Verified", systemImage: "checkmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                }
                            }

                            Text(record.messageHash.prefix(24) + "...")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Signing History")
        }
    }
}

#Preview {
    SigningHistoryView()
        .environmentObject(KeyStore())
}
