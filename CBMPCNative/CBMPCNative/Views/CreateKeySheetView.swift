import SwiftUI

struct CreateKeySheetView: View {
    @EnvironmentObject var keyStore: KeyStore
    @Environment(\.dismiss) var dismiss

    @State private var keyName = "My Key"
    @State private var keyType: KeyType = .simple
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Key Name")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)

                    TextField("Key Name", text: $keyName)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .background(.gray.opacity(0.1))
                        .cornerRadius(4)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Key Type")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)

                    Picker("Key Type", selection: $keyType) {
                        Text("Simple Key").tag(KeyType.simple)
                        // HD Master support coming soon
                        // Text("HD Master").tag(KeyType.hdMaster)
                    }
                    .pickerStyle(.segmented)
                }

                Spacer()

                Button(action: createKey) {
                    if isCreating {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Creating...")
                        }
                    } else {
                        Label("Create Key", systemImage: "plus.circle.fill")
                    }
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent)
                .disabled(isCreating || keyName.isEmpty)
            }
            .padding(16)
            .navigationTitle("Create New Key")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func createKey() {
        isCreating = true

        // Generate key on main thread (KeyStore is MainActor)
        do {
            let newKey = try keyStore.generateCryptographicKey(name: keyName, keyType: keyType)
            isCreating = false
            dismiss()
        } catch {
            print("Key generation failed: \(error)")
            isCreating = false
        }
    }
}

#Preview {
    CreateKeySheetView()
        .environmentObject(KeyStore())
}
