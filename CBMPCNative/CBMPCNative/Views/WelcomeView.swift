import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var keyStore: KeyStore
    @Binding var hasCompletedOnboarding: Bool
    @State private var showCreateSheet = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo + Title
            VStack(spacing: 16) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 56))
                    .foregroundColor(CBStyle.Colors.indigoFallback)

                VStack(spacing: 8) {
                    Text("CB-MPC VAULT")
                        .font(CBStyle.Fonts.h1)
                        .tracking(2)

                    Text("Threshold key management.")
                        .font(CBStyle.Fonts.body)
                        .foregroundColor(.secondary)
                    Text("Your key never exists in one place.")
                        .font(CBStyle.Fonts.body)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Protocol info
            VStack(alignment: .leading, spacing: 8) {
                protocolRow("2-party ECDSA (secp256k1)")
                protocolRow("Distributed key generation")
                protocolRow("Threshold signing")
                protocolRow("HD key derivation (BIP-32)")
                protocolRow("Key share refresh")
            }
            .padding(.horizontal, CBStyle.pagePadding * 2)

            Spacer()

            // CTAs
            VStack(spacing: 12) {
                Button(action: {
                    showCreateSheet = true
                }) {
                    Text("Create New Vault")
                }
                .buttonStyle(BrutalistButtonStyle(color: CBStyle.Colors.indigoFallback))

                Button(action: {
                    // Placeholder — skip onboarding for now
                    hasCompletedOnboarding = true
                }) {
                    Text("Restore from Backup")
                }
                .buttonStyle(BrutalistSecondaryButtonStyle())

                Button(action: {
                    hasCompletedOnboarding = true
                }) {
                    Text("Skip")
                        .font(CBStyle.Fonts.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, CBStyle.pagePadding * 2)
            .padding(.bottom, 48)
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateKeySheetView()
                .environmentObject(keyStore)
                .onDisappear {
                    if !keyStore.keys.isEmpty {
                        hasCompletedOnboarding = true
                    }
                }
        }
    }

    @ViewBuilder
    private func protocolRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            Text(">")
                .font(CBStyle.Fonts.crypto)
                .foregroundColor(CBStyle.Colors.indigoFallback)
            Text(text)
                .font(CBStyle.Fonts.crypto)
                .foregroundColor(.secondary)
        }
    }
}
