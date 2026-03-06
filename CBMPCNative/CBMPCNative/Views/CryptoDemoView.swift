import SwiftUI
import CommonCrypto

/// Runs the full ECDSA 2-party demo flow matching the Go demo:
/// DKG → Sign → Verify → Refresh → Re-sign → Verify
struct CryptoDemoView: View {
    @State private var steps: [DemoStep] = []
    @State private var isRunning = false
    @State private var hasRun = false

    var body: some View {
        List {
            Section("ECDSA 2-Party Demo") {
                if !hasRun {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mirrors the Go ecdsa-2pc example:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("1. Distributed Key Generation (DKG)")
                            .font(.caption2).foregroundColor(.secondary)
                        Text("2. Sign message (SHA-256 hash)")
                            .font(.caption2).foregroundColor(.secondary)
                        Text("3. Verify signature")
                            .font(.caption2).foregroundColor(.secondary)
                        Text("4. Key refresh (re-randomize shares)")
                            .font(.caption2).foregroundColor(.secondary)
                        Text("5. Sign again with refreshed key")
                            .font(.caption2).foregroundColor(.secondary)
                        Text("6. Verify new signature")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Button(action: runDemo) {
                    HStack {
                        if isRunning {
                            ProgressView()
                                .controlSize(.small)
                            Text("Running...")
                        } else {
                            Image(systemName: "play.fill")
                            Text(hasRun ? "Run Again" : "Run Demo")
                        }
                    }
                }
                .disabled(isRunning)
            }

            if !steps.isEmpty {
                Section("Results") {
                    ForEach(steps) { step in
                        DemoStepRow(step: step)
                    }
                }
            }
        }
        .navigationTitle("Crypto Demo")
    }

    private func runDemo() {
        isRunning = true
        steps = []
        hasRun = true

        DispatchQueue.global(qos: .userInitiated).async {
            let results = runECDSA2PCDemo()
            DispatchQueue.main.async {
                steps = results
                isRunning = false
            }
        }
    }
}

// MARK: - Demo Step Model

struct DemoStep: Identifiable {
    let id = UUID()
    let title: String
    let status: StepStatus
    let detail: String
    let duration: TimeInterval

    enum StepStatus {
        case success, failure
    }
}

struct DemoStepRow: View {
    let step: DemoStep

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: step.status == .success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(step.status == .success ? .green : .red)
                    .font(.caption)
                Text(step.title)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text(String(format: "%.1fms", step.duration * 1000))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Text(step.detail)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(3)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Demo Runner

/// SHA-256 hash helper
private func sha256(_ data: Data) -> Data {
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    data.withUnsafeBytes { buffer in
        _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
    }
    return Data(hash)
}

private func hexString(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
}

/// Runs the complete ECDSA 2-party demo, returns step results
func runECDSA2PCDemo() -> [DemoStep] {
    var steps: [DemoStep] = []
    let curveCode = 714 // secp256k1

    // -- Step 1: DKG --
    var key0: CBMPCKeyShare?
    var key1: CBMPCKeyShare?
    var publicKey: Data?

    let t0 = CFAbsoluteTimeGetCurrent()
    do {
        let (k0, k1) = try LocalTwoPartyRunner.run { job, role in
            var keyVar = cbmpc_ecdsa2p_key_t()
            let result = cbmpc_ecdsa2p_dkg(job.cJob, Int32(curveCode), &keyVar)
            guard result == 0 else { throw CBMPCError.keyGenerationFailed }
            return CBMPCKeyShare(keyPtr: keyVar, curveCode: curveCode)
        }
        key0 = k0
        key1 = k1
        publicKey = k0.getPublicKey()
        let dt = CFAbsoluteTimeGetCurrent() - t0
        let pubHex = publicKey.map { hexString($0) } ?? "nil"
        steps.append(DemoStep(
            title: "1. Distributed Key Generation",
            status: .success,
            detail: "Public key: \(pubHex.prefix(40))...\nParty 0 role: \(k0.getRole()), Party 1 role: \(k1.getRole())",
            duration: dt
        ))
    } catch {
        steps.append(DemoStep(title: "1. DKG", status: .failure, detail: "\(error)", duration: CFAbsoluteTimeGetCurrent() - t0))
        return steps
    }

    // -- Step 2: Sign message --
    let message = "Hello from cb-mpc iOS demo!".data(using: .utf8)!
    let messageHash = sha256(message)
    var signature0: Data?

    let t1 = CFAbsoluteTimeGetCurrent()
    do {
        let sessionId = UUID().uuidString.data(using: .utf8)!
        let (sig0, _) = try LocalTwoPartyRunner.run { job, role in
            let keyShare = (role == 0) ? key0! : key1!
            let sigs = try CBMPCSigner.signMessages([messageHash], with: keyShare, sessionId: sessionId, job: job)
            guard let sig = sigs.first else { throw CBMPCError.signingFailed }
            return sig
        }
        signature0 = sig0
        let dt = CFAbsoluteTimeGetCurrent() - t1
        steps.append(DemoStep(
            title: "2. Sign Message",
            status: .success,
            detail: "Message: \"\(String(data: message, encoding: .utf8) ?? "")\"\nHash: \(hexString(messageHash).prefix(32))...\nSig: \(hexString(sig0).prefix(40))...",
            duration: dt
        ))
    } catch {
        steps.append(DemoStep(title: "2. Sign", status: .failure, detail: "\(error)", duration: CFAbsoluteTimeGetCurrent() - t1))
        return steps
    }

    // -- Step 3: Verify signature --
    let t2 = CFAbsoluteTimeGetCurrent()
    let verified = CBMPCCryptoEngine.verifySignature(
        curveCode: curveCode,
        publicKey: publicKey!,
        messageHash: messageHash,
        derSignature: signature0!
    )
    let dt2 = CFAbsoluteTimeGetCurrent() - t2
    steps.append(DemoStep(
        title: "3. Verify Signature",
        status: verified ? .success : .failure,
        detail: "Verification: \(verified ? "VALID" : "INVALID")\nSig length: \(signature0!.count) bytes (DER)",
        duration: dt2
    ))
    if !verified { return steps }

    // -- Step 4: Key refresh --
    var refreshedKey0: CBMPCKeyShare?
    var refreshedKey1: CBMPCKeyShare?

    let t3 = CFAbsoluteTimeGetCurrent()
    do {
        let (rk0, rk1) = try LocalTwoPartyRunner.run { job, role in
            let keyShare = (role == 0) ? key0! : key1!
            var newKey = cbmpc_ecdsa2p_key_t()
            let result = cbmpc_ecdsa2p_refresh(job.cJob, &keyShare.keyPtr, &newKey)
            guard result == 0 else { throw CBMPCError.refreshFailed }
            return CBMPCKeyShare(keyPtr: newKey, curveCode: curveCode)
        }
        refreshedKey0 = rk0
        refreshedKey1 = rk1
        let newPubKey = rk0.getPublicKey()
        let dt = CFAbsoluteTimeGetCurrent() - t3
        let pubMatch = (newPubKey == publicKey) ? "MATCH" : "MISMATCH"
        steps.append(DemoStep(
            title: "4. Key Refresh",
            status: (newPubKey == publicKey) ? .success : .failure,
            detail: "Public key after refresh: \(pubMatch)\nShares re-randomized, same public key retained",
            duration: dt
        ))
        if newPubKey != publicKey { return steps }
    } catch {
        steps.append(DemoStep(title: "4. Refresh", status: .failure, detail: "\(error)", duration: CFAbsoluteTimeGetCurrent() - t3))
        return steps
    }

    // -- Step 5: Sign with refreshed key --
    let message2 = "Second signature after refresh".data(using: .utf8)!
    let messageHash2 = sha256(message2)
    var signature1: Data?

    let t4 = CFAbsoluteTimeGetCurrent()
    do {
        let sessionId2 = UUID().uuidString.data(using: .utf8)!
        let (sig0, _) = try LocalTwoPartyRunner.run { job, role in
            let keyShare = (role == 0) ? refreshedKey0! : refreshedKey1!
            let sigs = try CBMPCSigner.signMessages([messageHash2], with: keyShare, sessionId: sessionId2, job: job)
            guard let sig = sigs.first else { throw CBMPCError.signingFailed }
            return sig
        }
        signature1 = sig0
        let dt = CFAbsoluteTimeGetCurrent() - t4
        steps.append(DemoStep(
            title: "5. Sign with Refreshed Key",
            status: .success,
            detail: "Message: \"\(String(data: message2, encoding: .utf8) ?? "")\"\nSig: \(hexString(sig0).prefix(40))...",
            duration: dt
        ))
    } catch {
        steps.append(DemoStep(title: "5. Re-sign", status: .failure, detail: "\(error)", duration: CFAbsoluteTimeGetCurrent() - t4))
        return steps
    }

    // -- Step 6: Verify new signature --
    let t5 = CFAbsoluteTimeGetCurrent()
    let verified2 = CBMPCCryptoEngine.verifySignature(
        curveCode: curveCode,
        publicKey: publicKey!,
        messageHash: messageHash2,
        derSignature: signature1!
    )
    let dt5 = CFAbsoluteTimeGetCurrent() - t5
    steps.append(DemoStep(
        title: "6. Verify Refreshed Signature",
        status: verified2 ? .success : .failure,
        detail: "Verification: \(verified2 ? "VALID" : "INVALID")\nSame public key verifies both original and refreshed key signatures",
        duration: dt5
    ))

    // Summary
    let totalTime = steps.reduce(0.0) { $0 + $1.duration }
    steps.append(DemoStep(
        title: "Complete",
        status: steps.allSatisfy({ $0.status == .success }) ? .success : .failure,
        detail: "All 6 steps completed\nTotal: \(String(format: "%.0fms", totalTime * 1000))",
        duration: totalTime
    ))

    return steps
}

#Preview {
    NavigationStack {
        CryptoDemoView()
    }
}
