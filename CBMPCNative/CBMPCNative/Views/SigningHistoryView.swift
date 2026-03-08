import SwiftUI
#if os(iOS)
import UIKit
#endif

struct SigningHistoryView: View {
    @EnvironmentObject var keyStore: KeyStore
    @State private var showClearAllAlert = false
    @State private var copiedId: String?

    var allSignings: [(record: SigningRecord, keyName: String, keyPublicKey: String, keyType: String)] {
        keyStore.keys.flatMap { key in
            key.signingRecords.map { record in
                (record: record, keyName: key.name, keyPublicKey: key.publicKey, keyType: key.displayKeyType)
            }
        }
        .sorted { $0.record.timestamp > $1.record.timestamp }
    }

    var body: some View {
        NavigationStack {
            Group {
                if allSignings.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No signing history")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text("Sign a message from any key to see records here")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(Array(allSignings.enumerated()), id: \.element.record.id) { _, entry in
                            VStack(alignment: .leading, spacing: 6) {
                                // Timestamp + key type + delete + wallet info
                                HStack {
                                    if entry.record.verified {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 10))
                                            .foregroundColor(.green)
                                    } else {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 10))
                                            .foregroundColor(.red)
                                    }

                                    Text(AppDateFormat.string(from: entry.record.timestamp))
                                        .font(.system(size: 9, design: .monospaced))

                                    Text(entry.keyType)
                                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                                        .foregroundColor(.secondary)

                                    // Delete glyph right after wallet type
                                    Button(action: {
                                        if let key = keyStore.keys.first(where: { $0.signingRecords.contains(where: { $0.id == entry.record.id }) }) {
                                            keyStore.deleteSigningRecord(entry.record.id, from: key.id)
                                        }
                                    }) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 8))
                                            .foregroundColor(.red.opacity(0.5))
                                    }
                                    .buttonStyle(.plain)

                                    Spacer()

                                    Text(entry.keyName)
                                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }

                                // Full public key - no truncation
                                Text(entry.keyPublicKey)
                                    .font(.system(size: 7, design: .monospaced))
                                    .foregroundColor(.secondary.opacity(0.7))
                                    .fixedSize(horizontal: false, vertical: true)

                                // Full hash with copy - no truncation
                                HStack(alignment: .top, spacing: 4) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("SHA-256")
                                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                                            .foregroundColor(.secondary)
                                        Text(entry.record.messageHash)
                                            .font(.system(size: 7, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 4)
                                    copyButton(entry.record.messageHash, id: "h-\(entry.record.id)")
                                }

                                // Full signature with copy - no truncation
                                HStack(alignment: .top, spacing: 4) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("SIGNATURE")
                                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                                            .foregroundColor(.secondary)
                                        Text(entry.record.signature)
                                            .font(.system(size: 7, design: .monospaced))
                                            .foregroundColor(.secondary.opacity(0.7))
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 4)
                                    copyButton(entry.record.signature, id: "s-\(entry.record.id)")
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("History")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if !allSignings.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: { showClearAllAlert = true }) {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .alert("Clear All History", isPresented: $showClearAllAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Clear All", role: .destructive) {
                    keyStore.clearAllSigningRecords()
                }
            } message: {
                Text("This will permanently delete all signing history records.")
            }
        }
    }

    @ViewBuilder
    private func copyButton(_ text: String, id: String) -> some View {
        Button(action: {
            #if os(iOS)
            UIPasteboard.general.string = text
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            #endif
            copiedId = id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if copiedId == id { copiedId = nil }
            }
        }) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 8))
                .foregroundColor(copiedId == id ? .blue : .secondary)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SigningHistoryView()
        .environmentObject(KeyStore())
}
