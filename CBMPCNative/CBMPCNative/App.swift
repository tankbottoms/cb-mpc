import SwiftUI
import CoreData
import CryptoKit
import LocalAuthentication

@main
struct CBMPCApp: App {
    let persistenceController = PersistenceController.shared
    @AppStorage("useFaceID") private var useFaceID = false
    @AppStorage("keystorePasswordHash") private var keystorePasswordHash = ""
    @State private var isUnlocked = false
    @State private var passwordAttempt = ""
    @State private var passwordError: String?
    @State private var hasAttemptedBiometrics = false

    private var needsAuth: Bool {
        !isUnlocked && (useFaceID || !keystorePasswordHash.isEmpty)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                AppNavigation()
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
                    .blur(radius: needsAuth ? 20 : 0)
                    .allowsHitTesting(!needsAuth)

                if needsAuth {
                    lockOverlay
                }
            }
            .task {
                guard !isUnlocked, !hasAttemptedBiometrics else { return }
                if !useFaceID && keystorePasswordHash.isEmpty {
                    isUnlocked = true
                    return
                }
                if useFaceID {
                    hasAttemptedBiometrics = true
                    await authenticateWithBiometrics()
                }
            }
        }
    }

    private var lockOverlay: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("CB-MPC")
                .font(.system(.title2, design: .monospaced))

            if useFaceID {
                Button(action: {
                    Task { await authenticateWithBiometrics() }
                }) {
                    Label("Unlock with Face ID", systemImage: "faceid")
                        .font(.system(size: 14, design: .monospaced))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 40)
            }

            if !keystorePasswordHash.isEmpty {
                VStack(spacing: 8) {
                    SecureField("Password", text: $passwordAttempt)
                        .font(.system(.body, design: .monospaced))
                        .padding(10)
                        .background(.gray.opacity(0.15))
                        .cornerRadius(8)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { checkPassword() }

                    if let err = passwordError {
                        Text(err)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.red)
                    }

                    Button("Unlock") { checkPassword() }
                        .font(.system(size: 14, design: .monospaced))
                        .buttonStyle(.borderedProminent)
                        .disabled(passwordAttempt.isEmpty)
                }
                .padding(.horizontal, 40)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    private func authenticateWithBiometrics() async {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            if keystorePasswordHash.isEmpty {
                await MainActor.run { isUnlocked = true }
            }
            return
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Unlock CB-MPC to access your keys"
            )
            if success {
                await MainActor.run { isUnlocked = true }
            }
        } catch {
            // User cancelled or biometrics failed -- fall through to password
        }
    }

    private func checkPassword() {
        let hash = SHA256.hash(data: Data(passwordAttempt.utf8))
        let hashHex = hash.map { String(format: "%02x", $0) }.joined()
        if hashHex == keystorePasswordHash {
            isUnlocked = true
            passwordAttempt = ""
            passwordError = nil
        } else {
            passwordError = "Incorrect password"
            passwordAttempt = ""
        }
    }
}
