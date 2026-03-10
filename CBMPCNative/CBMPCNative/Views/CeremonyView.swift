import SwiftUI

/// Displays real-time ceremony progress for DKG and signing operations.
/// Driven by CeremonyCoordinator's published state.
struct CeremonyView: View {
    @ObservedObject var coordinator: CeremonyCoordinator

    var body: some View {
        VStack(spacing: 16) {
            if let ceremony = coordinator.activeCeremony {
                activeCeremonyView(ceremony)
            } else if let last = coordinator.ceremonies.last {
                completedCeremonyView(last)
            } else {
                Text("No ceremony in progress")
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Ceremony")
    }

    @ViewBuilder
    private func activeCeremonyView(_ ceremony: CeremonySession) -> some View {
        HStack {
            Circle()
                .fill(statusColor(for: ceremony.state))
                .frame(width: 12, height: 12)

            Text(statusLabel(for: ceremony.state))
                .font(.headline)

            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)

        // Ceremony details
        VStack(alignment: .leading, spacing: 8) {
            DetailRow(label: "Type", value: ceremony.type == .dkg ? "Key Generation" : "Signing")
            DetailRow(label: "Mode", value: ceremony.participantMode == .device ? "Device + Device" : "Device + Server")
            DetailRow(label: "Party", value: "Party \(ceremony.localPartyId)")
            DetailRow(label: "Started", value: ceremony.startedAt.formatted(date: .omitted, time: .standard))
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)

        if ceremony.state == .initialized || ceremony.state == .committed {
            ProgressView()
                .scaleEffect(1.5)
                .padding()
        }
    }

    @ViewBuilder
    private func completedCeremonyView(_ ceremony: CeremonySession) -> some View {
        HStack {
            Circle()
                .fill(statusColor(for: ceremony.state))
                .frame(width: 12, height: 12)

            Text(statusLabel(for: ceremony.state))
                .font(.headline)

            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)

        if let pubkey = ceremony.publicKey {
            VStack(alignment: .leading, spacing: 8) {
                Text("Public Key")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(pubkey)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(3)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }

        if case .failed(let msg) = ceremony.state {
            VStack(alignment: .leading, spacing: 8) {
                Text("Error")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(msg)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.red)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
    }

    private func statusColor(for state: CeremonyState) -> Color {
        switch state {
        case .initialized, .committed: return .blue
        case .signed: return .orange
        case .complete: return .green
        case .failed: return .red
        }
    }

    private func statusLabel(for state: CeremonyState) -> String {
        switch state {
        case .initialized: return "Initializing..."
        case .committed: return "Exchanging commitments..."
        case .signed: return "Computing signature..."
        case .complete: return "Complete"
        case .failed(let msg): return "Failed: \(msg)"
        }
    }
}
