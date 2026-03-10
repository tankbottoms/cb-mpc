import SwiftUI
#if os(iOS)
import UIKit
#endif

struct SigningHistoryView: View {
    @EnvironmentObject var keyStore: KeyStore
    @State private var showClearAllAlert = false
    @State private var copiedId: String?
    @State private var selectedEntry: SigningRecord?

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
                            VStack(alignment: .leading, spacing: 4) {
                                // Line 1: verified icon + key name + key type
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

                                    Text(entry.keyName)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))

                                    Text(entry.keyType)
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .foregroundColor(.secondary)

                                    Spacer()

                                    Text(AppDateFormat.string(from: entry.record.timestamp))
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }

                                // Line 2: truncated signature
                                Text(entry.record.signature)
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundColor(.secondary.opacity(0.7))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .padding(.vertical, 2)
                            .onTapGesture {
                                selectedEntry = entry.record
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    if let key = keyStore.keys.first(where: { $0.signingRecords.contains(where: { $0.id == entry.record.id }) }) {
                                        #if os(iOS)
                                        let impact = UIImpactFeedbackGenerator(style: .medium)
                                        impact.impactOccurred()
                                        #endif
                                        keyStore.deleteSigningRecord(entry.record.id, from: key.id)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
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
            .sheet(item: $selectedEntry) { record in
                if let entry = allSignings.first(where: { $0.record.id == record.id }) {
                    SigningDetailSheetView(entry: entry, copiedId: $copiedId)
                }
            }
        }
    }

    private func fullRecordText(_ entry: (record: SigningRecord, keyName: String, keyPublicKey: String, keyType: String)) -> String {
        """
        CB-MPC Signing Record
        =====================
        Date:       \(AppDateFormat.string(from: entry.record.timestamp))
        Key:        \(entry.keyName)
        Type:       \(entry.keyType)
        Public Key: 0x\(entry.keyPublicKey)
        Verified:   \(entry.record.verified ? "Yes" : "No")
        SHA-256:    \(entry.record.messageHash)
        Signature:  \(entry.record.signature)
        """
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

// MARK: - Signing Detail Sheet

struct SigningDetailSheetView: View {
    let entry: (record: SigningRecord, keyName: String, keyPublicKey: String, keyType: String)
    @Binding var copiedId: String?
    @Environment(\.dismiss) var dismiss

    private var fullText: String {
        """
        CB-MPC Signing Record
        =====================
        Date:       \(AppDateFormat.string(from: entry.record.timestamp))
        Key:        \(entry.keyName)
        Type:       \(entry.keyType)
        Public Key: 0x\(entry.keyPublicKey)
        Verified:   \(entry.record.verified ? "Yes" : "No")
        SHA-256:    \(entry.record.messageHash)
        Signature:  \(entry.record.signature)
        """
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    detailSection("DATE", value: AppDateFormat.string(from: entry.record.timestamp), id: "dt-\(entry.record.id)")

                    detailSection("KEY", value: entry.keyName, id: "kn-\(entry.record.id)")

                    detailSection("TYPE", value: entry.keyType, id: "kt-\(entry.record.id)")

                    detailSection("PUBLIC KEY", value: "0x\(entry.keyPublicKey)", id: "pk-\(entry.record.id)")

                    HStack {
                        Text("VERIFIED")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                        if entry.record.verified {
                            Label("Yes", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.green)
                        } else {
                            Label("No", systemImage: "xmark.circle.fill")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.red)
                        }
                    }

                    detailSection("SHA-256 HASH", value: entry.record.messageHash, id: "h-\(entry.record.id)")

                    detailSection("SIGNATURE", value: entry.record.signature, id: "s-\(entry.record.id)")

                    // Copy all button
                    Button(action: {
                        #if os(iOS)
                        UIPasteboard.general.string = fullText
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                        #endif
                        copiedId = "all-\(entry.record.id)"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            if copiedId == "all-\(entry.record.id)" { copiedId = nil }
                        }
                    }) {
                        Label(copiedId == "all-\(entry.record.id)" ? "Copied" : "Copy All", systemImage: copiedId == "all-\(entry.record.id)" ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(16)
            }
            .navigationTitle("Signing Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func detailSection(_ label: String, value: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: {
                    #if os(iOS)
                    UIPasteboard.general.string = value
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                    #endif
                    copiedId = id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        if copiedId == id { copiedId = nil }
                    }
                }) {
                    Image(systemName: copiedId == id ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9))
                        .foregroundColor(copiedId == id ? .blue : .secondary)
                }
                .buttonStyle(.plain)
            }
            Text(value)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.gray.opacity(0.05))
                .cornerRadius(4)
        }
    }
}

#Preview {
    SigningHistoryView()
        .environmentObject(KeyStore())
}
