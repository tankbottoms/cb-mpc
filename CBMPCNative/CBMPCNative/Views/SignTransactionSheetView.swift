import SwiftUI
#if os(iOS)
import UIKit
#endif

struct SignTransactionSheetView: View {
    let key: ManagedKey
    @Environment(\.dismiss) var dismiss
    @AppStorage("ethereumRPC") private var ethereumRPC = "hoodi"
    @AppStorage("infuraAPIKey") private var infuraAPIKey = "65980db64d52417abbda13b49e356d97"

    @State private var nonce = "0"
    @State private var toAddress = ""
    @State private var value = "0.01"
    @State private var gasLimit = "21000"
    @State private var gasPrice = "20"
    @State private var maxPriorityFee = "1.5"
    @State private var data = ""
    @State private var showShareSheet = false

    private var chainId: String {
        switch ethereumRPC {
        case "mainnet": return "1"
        case "sepolia": return "11155111"
        default: return "560048"
        }
    }

    private var networkName: String {
        switch ethereumRPC {
        case "mainnet": return "Ethereum Mainnet"
        case "sepolia": return "Sepolia Testnet"
        default: return "Hoodi Testnet"
        }
    }

    private var transactionJSON: String {
        var tx: [String: Any] = [
            "from": "0x\(key.publicKey.suffix(40))",
            "to": toAddress,
            "value": value,
            "nonce": nonce,
            "gasLimit": gasLimit,
            "gasPrice": "\(gasPrice) gwei",
            "maxPriorityFeePerGas": "\(maxPriorityFee) gwei",
            "chainId": chainId,
            "network": networkName
        ]
        if !data.isEmpty {
            tx["data"] = data
        }
        if let jsonData = try? JSONSerialization.data(withJSONObject: tx, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        return "{}"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Network indicator
                    HStack {
                        Circle()
                            .fill(ethereumRPC == "mainnet" ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(networkName)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                        Text("Chain \(chainId)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.gray.opacity(0.1))
                    .cornerRadius(4)

                    txField(label: "NONCE", text: $nonce, placeholder: "0")
                    txField(label: "TO ADDRESS", text: $toAddress, placeholder: "0x...")
                    txField(label: "VALUE (ETH)", text: $value, placeholder: "0.01")
                    txField(label: "GAS LIMIT", text: $gasLimit, placeholder: "21000")
                    txField(label: "GAS PRICE (GWEI)", text: $gasPrice, placeholder: "20")
                    txField(label: "PRIORITY FEE (GWEI)", text: $maxPriorityFee, placeholder: "1.5")
                    txField(label: "DATA (HEX)", text: $data, placeholder: "0x (optional)")

                    // Chain ID (read-only)
                    HStack {
                        Text("CHAIN ID")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(chainId)
                            .font(.system(size: 11, design: .monospaced))
                    }
                    .padding(8)
                    .background(.gray.opacity(0.1))
                    .cornerRadius(4)

                    Spacer().frame(height: 8)

                    // Preview
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Transaction Preview")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text(transactionJSON)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.gray.opacity(0.05))
                            .cornerRadius(4)
                    }

                    HStack(spacing: 8) {
                        Button(action: {
                            #if os(iOS)
                            UIPasteboard.general.string = transactionJSON
                            #endif
                        }) {
                            Label("Copy", systemImage: "doc.on.doc")
                                .font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button(action: { showShareSheet = true }) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(toAddress.isEmpty)
                    }
                }
                .padding(16)
            }
            .navigationTitle("Sign Transaction")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: [transactionJSON])
            }
        }
    }

    @ViewBuilder
    private func txField(label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
            TextField(placeholder, text: text)
                .font(.system(size: 12, design: .monospaced))
                .padding(8)
                .background(.gray.opacity(0.1))
                .cornerRadius(4)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }
}
