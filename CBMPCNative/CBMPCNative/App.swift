import SwiftUI
import CoreData
import CryptoKit
import LocalAuthentication

@main
struct CBMPCApp: App {
    let persistenceController = PersistenceController.shared
    @AppStorage("useFaceID") private var useFaceID = false
    @AppStorage("keystorePasswordHash") private var keystorePasswordHash = ""
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var isUnlocked = false
    @State private var passwordAttempt = ""
    @State private var passwordError: String?
    @State private var hasAttemptedBiometrics = false
    @State private var showOnboarding = false

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
            .onAppear {
                if !hasCompletedOnboarding {
                    showOnboarding = true
                }
            }
            .sheet(isPresented: $showOnboarding) {
                OnboardingView(
                    useFaceID: $useFaceID,
                    keystorePasswordHash: $keystorePasswordHash,
                    keystorePasswordSetDate: Binding(
                        get: { UserDefaults.standard.string(forKey: "keystorePasswordSetDate") ?? "" },
                        set: { UserDefaults.standard.set($0, forKey: "keystorePasswordSetDate") }
                    ),
                    hasCompletedOnboarding: $hasCompletedOnboarding
                )
                .interactiveDismissDisabled()
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

// MARK: - First-Run Onboarding

struct OnboardingView: View {
    @Binding var useFaceID: Bool
    @Binding var keystorePasswordHash: String
    @Binding var keystorePasswordSetDate: String
    @Binding var hasCompletedOnboarding: Bool
    @Environment(\.dismiss) var dismiss

    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var passwordError: String?
    @State private var step = 0 // 0 = welcome, 1 = password, 2 = face id

    private var passwordsMatch: Bool {
        !newPassword.isEmpty && !confirmPassword.isEmpty && newPassword == confirmPassword
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if step == 0 {
                    welcomeStep
                } else if step == 1 {
                    passwordStep
                } else {
                    faceIdStep
                }
            }
            .navigationTitle("Setup")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundColor(.blue)

            Text("CB-MPC")
                .font(.system(.title, design: .monospaced))

            Text("Multi-Party Computation\nKey Management")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                Label("Keys never exist in a single location", systemImage: "key.horizontal.fill")
                    .font(.system(size: 12, design: .monospaced))
                Label("Threshold signing with MPC shares", systemImage: "signature")
                    .font(.system(size: 12, design: .monospaced))
                Label("iCloud backup with Web3 V3 format", systemImage: "icloud.fill")
                    .font(.system(size: 12, design: .monospaced))
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 24)

            Spacer()

            Button(action: { withAnimation { step = 1 } }) {
                Text("Get Started")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }

    private var passwordStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("SET KEYSTORE PASSWORD")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))

                Text("Protect your keystore with a password. This is required when Face ID is unavailable.")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(.blue.opacity(0.05))
            .cornerRadius(6)

            SecureField("Password (min 4 characters)", text: $newPassword)
                .font(.system(.body, design: .monospaced))
                .padding(10)
                .background(.gray.opacity(0.1))
                .cornerRadius(6)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SecureField("Confirm Password", text: $confirmPassword)
                .font(.system(.body, design: .monospaced))
                .padding(10)
                .background(.gray.opacity(0.1))
                .cornerRadius(6)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !newPassword.isEmpty && !confirmPassword.isEmpty && newPassword != confirmPassword {
                Text("Passwords do not match")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.red)
            } else if passwordsMatch {
                Text("Passwords match")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.green)
            }

            if let err = passwordError {
                Text(err)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.red)
            }

            Spacer()

            VStack(spacing: 8) {
                Button(action: setPasswordAndContinue) {
                    Text("Set Password")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!passwordsMatch)

                Button(action: { withAnimation { step = 2 } }) {
                    Text("Skip")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 32)
        }
        .padding(16)
    }

    private var faceIdStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "faceid")
                .font(.system(size: 56))
                .foregroundColor(.blue)

            Text("Enable Face ID")
                .font(.system(size: 18, weight: .semibold, design: .monospaced))

            Text("Use Face ID to quickly unlock the app and protect your keys.")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 8) {
                Button(action: {
                    useFaceID = true
                    completeOnboarding()
                }) {
                    Text("Enable Face ID")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(action: {
                    useFaceID = false
                    completeOnboarding()
                }) {
                    Text("Not Now")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }

    private func setPasswordAndContinue() {
        passwordError = nil
        guard newPassword == confirmPassword else {
            passwordError = "Passwords do not match"
            return
        }
        guard newPassword.count >= 4 else {
            passwordError = "Minimum 4 characters"
            return
        }

        let hash = SHA256.hash(data: Data(newPassword.utf8))
        keystorePasswordHash = hash.map { String(format: "%02x", $0) }.joined()
        keystorePasswordSetDate = AppDateFormat.string(from: Date())
        newPassword = ""
        confirmPassword = ""
        withAnimation { step = 2 }
    }

    private func completeOnboarding() {
        hasCompletedOnboarding = true
        dismiss()
    }
}
