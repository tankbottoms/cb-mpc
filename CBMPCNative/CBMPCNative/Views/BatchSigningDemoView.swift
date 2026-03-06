import SwiftUI

/// Batch Signing demo: DKG, sign 5 messages in one protocol round, verify all individually
struct BatchSigningDemoView: View {
    @StateObject private var runner = DemoRunner()
    @State private var hasRun = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                DemoHeader(
                    title: "Batch Signing",
                    description: "Sign 5 messages in one MPC round, verify each individually.",
                    isLive: true,
                    isRunning: runner.isRunning,
                    elapsedMs: runner.elapsedMs
                )
                if !runner.isRunning && hasRun {
                    Button(action: runDemo) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.trianglehead.counterclockwise").font(.system(size: 10))
                            Text("Run Again").font(.system(size: 10))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)

            List {
                ForEach(runner.steps) { step in
                    DemoStepRow(step: step)
                }
            }
            .listStyle(.plain)
        }
        .onAppear {
            if !hasRun { runDemo() }
        }
    }

    private func runDemo() {
        guard !runner.isRunning else { return }
        hasRun = true
        runner.start()

        DispatchQueue.global(qos: .userInitiated).async {
            runBatchSigningDemo(runner: runner)
            runner.finish()
        }
    }
}

@discardableResult
func runBatchSigningDemo(runner: DemoRunner? = nil) -> [DemoStep] {
    var steps: [DemoStep] = []
    let curveCode = 714 // secp256k1
    let messageCount = 5
    let partyNames = ["party_0", "party_1"]

    // -- Step 1: DKG --
    var key0: CBMPCKeyShare?
    var key1: CBMPCKeyShare?
    var publicKey: Data?

    let t0 = CFAbsoluteTimeGetCurrent()
    do {
        let (k0, k1) = try LocalTwoPartyRunner.run(partyNames: partyNames) { job, role in
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
        let pubKeyValid = publicKey != nil && publicKey!.count == 33
            && (publicKey![0] == 0x02 || publicKey![0] == 0x03)
        steps.append(DemoStep(
            title: "1. Key Generation (DKG)",
            status: pubKeyValid ? .success : .failure,
            detail: "PK (\(publicKey?.count ?? 0)B SEC1): \(pubHex.prefix(40))...\nFormat: \(pubKeyValid ? "OK" : "FAIL") compressed SEC1 (0x\(String(format: "%02x", publicKey?[0] ?? 0)) prefix)",
            duration: dt
        ))
        runner?.appendStep(steps.last!)
    } catch {
        steps.append(DemoStep(title: "1. DKG", status: .failure, detail: "\(error)", duration: CFAbsoluteTimeGetCurrent() - t0))
        runner?.appendStep(steps.last!)
        return steps
    }

    // -- Step 2: Batch sign 5 messages --
    let messages = (0..<messageCount).map { i in
        "Batch message \(i + 1) of \(messageCount)".data(using: .utf8)!
    }
    let messageHashes = messages.map { sha256($0) }
    var signatures: [Data] = []
    let sessionId = "batch-session".data(using: .utf8)!

    let t1 = CFAbsoluteTimeGetCurrent()
    do {
        let (sigs0, sigs1) = try LocalTwoPartyRunner.run(partyNames: partyNames) { job, role in
            let keyShare = (role == 0) ? key0! : key1!
            return try CBMPCSigner.signMessages(messageHashes, with: keyShare, sessionId: sessionId, job: job)
        }
        signatures = sigs0
        let dt = CFAbsoluteTimeGetCurrent() - t1
        let perMsg = dt / Double(messageCount)
        let allDER = sigs0.allSatisfy { $0.count > 0 && $0[0] == 0x30 }
        let p1Empty = sigs1.isEmpty
        steps.append(DemoStep(
            title: "2. Batch Sign \(messageCount) Messages",
            status: (allDER && (p1Empty || sigs1.allSatisfy { $0.isEmpty })) ? .success : .failure,
            detail: "Total: \(String(format: "%.1fms", dt * 1000)) | Per msg: \(String(format: "%.1fms", perMsg * 1000))\nAll DER (0x30): \(allDER ? "OK" : "FAIL") | Sizes: \(sigs0.map { "\($0.count)B" }.joined(separator: ", "))\nSingle protocol round, \(messageCount) sigs produced",
            duration: dt
        ))
        runner?.appendStep(steps.last!)
    } catch {
        steps.append(DemoStep(title: "2. Batch Sign", status: .failure, detail: "\(error)", duration: CFAbsoluteTimeGetCurrent() - t1))
        runner?.appendStep(steps.last!)
        return steps
    }

    // -- Step 3: Verify all signatures --
    let t2 = CFAbsoluteTimeGetCurrent()
    var allValid = true
    var verifyDetails: [String] = []

    for i in 0..<messageCount {
        let valid = CBMPCCryptoEngine.verifySignature(
            curveCode: curveCode,
            publicKey: publicKey!,
            messageHash: messageHashes[i],
            derSignature: signatures[i]
        )
        if !valid { allValid = false }
        verifyDetails.append("Msg \(i + 1): \(valid ? "OK" : "FAIL") (\(signatures[i].count)B DER)")
    }

    let dt2 = CFAbsoluteTimeGetCurrent() - t2
    steps.append(DemoStep(
        title: "3. Verify All \(messageCount) Signatures",
        status: allValid ? .success : .failure,
        detail: verifyDetails.joined(separator: " | "),
        duration: dt2
    ))
    runner?.appendStep(steps.last!)

    // -- Step 4: Summary --
    let totalTime = steps.reduce(0.0) { $0 + $1.duration }
    let batchTime = steps[1].duration
    let throughput = Double(messageCount) / batchTime
    steps.append(DemoStep(
        title: "4. Summary",
        status: allValid ? .success : .failure,
        detail: "Throughput: \(String(format: "%.1f", throughput)) msgs/sec\nAll \(messageCount) signed+verified | Total: \(String(format: "%.0fms", totalTime * 1000))\nGo: same cbmpc_ecdsa2p_sign with multiple digests",
        duration: totalTime
    ))
    runner?.appendStep(steps.last!)

    return steps
}

#Preview {
    NavigationStack {
        BatchSigningDemoView()
    }
}
