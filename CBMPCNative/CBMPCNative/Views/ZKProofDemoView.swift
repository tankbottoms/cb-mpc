import SwiftUI

/// Live ZK Proof demo: UC-DL proof generation and verification via Fischlin transform
struct ZKProofDemoView: View {
    @StateObject private var runner = DemoRunner()
    @State private var hasRun = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                DemoHeader(
                    title: "Zero-Knowledge Proofs",
                    description: "UC-secure discrete log proof via Fischlin transform on secp256k1.",
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
            runZKProofDemo(runner: runner)
            runner.finish()
        }
    }
}

@discardableResult
func runZKProofDemo(runner: DemoRunner? = nil) -> [DemoStep] {
    var steps: [DemoStep] = []
    let curveCode: Int32 = 714 // secp256k1

    // -- Step 1: Generate keypair --
    var pubKey = cbmpc_cmem_t()
    var privKey = cbmpc_cmem_t()

    let t0 = CFAbsoluteTimeGetCurrent()
    let genResult = cbmpc_zk_gen_keypair(curveCode, &pubKey, &privKey)
    let dt0 = CFAbsoluteTimeGetCurrent() - t0

    if genResult != 0 {
        steps.append(DemoStep(title: "1. Generate Keypair", status: .failure, detail: "cbmpc_zk_gen_keypair failed: \(genResult)", duration: dt0))
        runner?.appendStep(steps.last!)
        return steps
    }

    let pubData = Data(bytes: pubKey.data!, count: Int(pubKey.size))
    let privData = Data(bytes: privKey.data!, count: Int(privKey.size))
    let sec1Valid = pubData.count == 33 && (pubData[0] == 0x02 || pubData[0] == 0x03)

    steps.append(DemoStep(
        title: "1. Generate Keypair (w, Q=wG)",
        status: sec1Valid ? .success : .failure,
        detail: "PK (\(pubData.count)B SEC1): \(hexString(pubData).prefix(40))...\nSK (\(privData.count)B): \(hexString(privData).prefix(20))...\nCurve: secp256k1 | Format: \(sec1Valid ? "OK" : "FAIL") compressed SEC1",
        duration: dt0
    ))
    runner?.appendStep(steps.last!)

    // -- Step 2: Create proof (opaque handle) --
    let sessionIdBytes: [UInt8] = Array("zk-demo-session".utf8)
    let aux: UInt64 = 0

    let t1 = CFAbsoluteTimeGetCurrent()
    var proofHandle = cbmpc_zk_proof_t()
    var proofSize: Int32 = 0

    var sessionBuf = sessionIdBytes
    let proveResult = sessionBuf.withUnsafeMutableBufferPointer { sidBuf -> Int32 in
        var sessionCmem = cbmpc_cmem_t(data: sidBuf.baseAddress!, size: Int32(sidBuf.count))
        return cbmpc_zk_dl_prove(curveCode, pubKey, privKey, sessionCmem, aux, &proofHandle, &proofSize)
    }
    let dt1 = CFAbsoluteTimeGetCurrent() - t1

    if proveResult != 0 {
        steps.append(DemoStep(title: "2. Prove", status: .failure, detail: "cbmpc_zk_dl_prove failed: \(proveResult)", duration: dt1))
        runner?.appendStep(steps.last!)
        cbmpc_free(pubKey.data)
        cbmpc_free(privKey.data)
        return steps
    }

    steps.append(DemoStep(
        title: "2. Prove (Fischlin UC-DL)",
        status: .success,
        detail: "Proof size: \(proofSize) bytes\n32 parallel Schnorr repetitions with Fischlin hash mining\nSession: \"zk-demo-session\" | Aux: \(aux)\nOpaque handle retained for verify step",
        duration: dt1
    ))
    runner?.appendStep(steps.last!)

    // -- Step 3: Verify proof --
    let t2 = CFAbsoluteTimeGetCurrent()
    var verifySessionBuf: [UInt8] = Array("zk-demo-session".utf8)
    let verifyResult = verifySessionBuf.withUnsafeMutableBufferPointer { sidBuf -> Int32 in
        var sessionCmem = cbmpc_cmem_t(data: sidBuf.baseAddress!, size: Int32(sidBuf.count))
        return cbmpc_zk_dl_verify(curveCode, pubKey, sessionCmem, aux, &proofHandle)
    }
    let dt2 = CFAbsoluteTimeGetCurrent() - t2

    let verified = (verifyResult == 0)
    steps.append(DemoStep(
        title: "3. Verify Proof",
        status: verified ? .success : .failure,
        detail: "Verification: \(verified ? "VALID" : "INVALID (code \(verifyResult))")\nChecks: 32x (zi*G == Ai + ei*Q) + Fischlin constraint\nC++: zk::uc_dl_t::verify(Q, sid, aux)",
        duration: dt2
    ))
    runner?.appendStep(steps.last!)

    // -- Step 4: Verify with wrong session fails --
    let t3 = CFAbsoluteTimeGetCurrent()
    var wrongBuf: [UInt8] = Array("wrong-session".utf8)
    let badResult = wrongBuf.withUnsafeMutableBufferPointer { wBuf -> Int32 in
        var wrongCmem = cbmpc_cmem_t(data: wBuf.baseAddress!, size: Int32(wBuf.count))
        return cbmpc_zk_dl_verify(curveCode, pubKey, wrongCmem, aux, &proofHandle)
    }
    let dt3 = CFAbsoluteTimeGetCurrent() - t3

    let correctlyRejected = (badResult != 0)
    steps.append(DemoStep(
        title: "4. Reject Invalid Session",
        status: correctlyRejected ? .success : .failure,
        detail: "Wrong session ID: \"wrong-session\"\nResult: \(correctlyRejected ? "REJECTED (correct)" : "ACCEPTED (bug!)")\nProof is bound to session ID -- replay protection",
        duration: dt3
    ))
    runner?.appendStep(steps.last!)

    // -- Step 5: Summary --
    let totalTime = steps.reduce(0.0) { $0 + $1.duration }
    let allPass = steps.allSatisfy { $0.status == .success }
    steps.append(DemoStep(
        title: "5. Cross-Platform Verification",
        status: allPass ? .success : .failure,
        detail: "UC-secure DL proof: prove + verify + soundness check\nFischlin transform: non-interactive, 32 parallel reps\nProof: \(proofSize)B | Curve: secp256k1\nTotal: \(String(format: "%.0fms", totalTime * 1000))",
        duration: totalTime
    ))
    runner?.appendStep(steps.last!)

    // Cleanup
    cbmpc_free(pubKey.data)
    cbmpc_free(privKey.data)
    cbmpc_zk_proof_free(&proofHandle)

    return steps
}

#Preview {
    NavigationStack {
        ZKProofDemoView()
    }
}
