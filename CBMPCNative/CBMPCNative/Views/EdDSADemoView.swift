import SwiftUI

/// Live EdDSA multi-party demo: N-party key generation and EdDSA signing
struct EdDSADemoView: View {
    @StateObject private var runner = DemoRunner()
    @State private var hasRun = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                DemoHeader(
                    title: "EdDSA N-Party",
                    description: "Multi-party EdDSA key generation on Ed25519, signing, and verification using N-party MPC.",
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
            runEdDSADemo(runner: runner)
            runner.finish()
        }
    }
}

@discardableResult
func runEdDSADemo(runner: DemoRunner? = nil) -> [DemoStep] {
    var steps: [DemoStep] = []
    let nParties = 3
    let partyNames = (0..<nParties).map { "party_\($0)" }
    // Ed25519 curve code (NID_ED25519 = 1087 in OpenSSL)
    let ed25519Code = 1087

    // -- Step 1: N-Party DKG for EdDSA --
    var keys: [CBMPCKeyShareMP] = []

    let t0 = CFAbsoluteTimeGetCurrent()
    do {
        let results = try LocalNPartyRunner.run(
            partyCount: nParties,
            partyNames: partyNames
        ) { job, role -> CBMPCKeyShareMP in
            let curve = CBMPCCurve(curveCode: ed25519Code)
            guard let cCurve = curve.cCurve else { throw CBMPCError.keyGenerationFailed }
            var keyVar = cbmpc_eckey_mp_t()
            let result = cbmpc_eckey_mp_dkg(job.cJob, cCurve, &keyVar)
            guard result == 0 else { throw CBMPCError.keyGenerationFailed }
            return CBMPCKeyShareMP(keyPtr: keyVar)
        }
        keys = results
        let dt = CFAbsoluteTimeGetCurrent() - t0
        let pubKey = keys[0].getPublicKey()
        let pubHex = pubKey.map { hexString($0) } ?? "nil"
        steps.append(DemoStep(
            title: "1. N-Party EdDSA DKG",
            status: .success,
            detail: "Parties: \(nParties) | Curve: Ed25519\nPK (\(pubKey?.count ?? 0)B): \(pubHex.prefix(40))...\nC++: eckey::key_share_mp_t::dkg()",
            duration: dt
        ))
        runner?.appendStep(steps.last!)
    } catch {
        let dt = CFAbsoluteTimeGetCurrent() - t0
        steps.append(DemoStep(title: "1. EdDSA DKG", status: .failure, detail: "\(error)", duration: dt))
        runner?.appendStep(steps.last!)
        return steps
    }

    // -- Step 2: Verify all parties have same public key --
    let t1 = CFAbsoluteTimeGetCurrent()
    let pubKeys = keys.compactMap { $0.getPublicKey() }
    let allMatch = pubKeys.dropFirst().allSatisfy { $0 == pubKeys[0] }
    let dt1 = CFAbsoluteTimeGetCurrent() - t1
    steps.append(DemoStep(
        title: "2. Verify Public Key Consensus",
        status: allMatch ? .success : .failure,
        detail: "All \(nParties) parties share identical public key: \(allMatch ? "YES" : "NO")\nPK size: \(pubKeys[0].count) bytes (compressed Ed25519 point)\nEach party holds a unique private share",
        duration: dt1
    ))
    runner?.appendStep(steps.last!)
    if !allMatch { return steps }

    // -- Step 3: EdDSA Multi-Party Signing --
    let message = "EdDSA multi-party signature".data(using: .utf8)!
    let sigReceiver = 0
    var signature: Data?

    let t2 = CFAbsoluteTimeGetCurrent()
    do {
        let results = try LocalNPartyRunner.run(
            partyCount: nParties,
            partyNames: partyNames
        ) { job, role -> Data in
            var msgMem = cbmpc_cmem_t()
            message.withUnsafeBytes { buf in
                msgMem.data = UnsafeMutableRawPointer(mutating: buf.baseAddress)
                msgMem.size = Int32(message.count)
            }
            var sigMem = cbmpc_cmem_t()
            let result = cbmpc_eddsamp_sign(job.cJob, &keys[role].keyPtr, msgMem, Int32(sigReceiver), &sigMem)
            guard result == 0 else { throw CBMPCError.signingFailed }
            if role == sigReceiver, let data = sigMem.data {
                let sig = Data(bytes: data, count: Int(sigMem.size))
                cbmpc_free(data)
                return sig
            }
            return Data()
        }
        signature = results[sigReceiver]
        let dt = CFAbsoluteTimeGetCurrent() - t2
        let sigHex = signature.map { hexString($0) } ?? "nil"
        steps.append(DemoStep(
            title: "3. EdDSA N-Party Sign",
            status: (signature?.count ?? 0) > 0 ? .success : .failure,
            detail: "Msg: \"\(String(data: message, encoding: .utf8) ?? "")\"\nSig (\(signature?.count ?? 0)B): \(sigHex.prefix(40))...\nReceiver: party_\(sigReceiver) | C++: eddsampc::sign()",
            duration: dt
        ))
        runner?.appendStep(steps.last!)
    } catch {
        let dt = CFAbsoluteTimeGetCurrent() - t2
        steps.append(DemoStep(title: "3. EdDSA Sign", status: .failure, detail: "\(error)", duration: dt))
        runner?.appendStep(steps.last!)
        return steps
    }

    // -- Step 4: Key Refresh --
    let t3 = CFAbsoluteTimeGetCurrent()
    do {
        let refreshSid = "eddsa-refresh-1".data(using: .utf8)!
        let refreshedKeys = try LocalNPartyRunner.run(
            partyCount: nParties,
            partyNames: partyNames
        ) { job, role -> CBMPCKeyShareMP in
            var sidMem = cbmpc_cmem_t()
            refreshSid.withUnsafeBytes { buf in
                sidMem.data = UnsafeMutableRawPointer(mutating: buf.baseAddress)
                sidMem.size = Int32(refreshSid.count)
            }
            var newKey = cbmpc_eckey_mp_t()
            let result = cbmpc_eckey_mp_refresh(job.cJob, sidMem, &keys[role].keyPtr, &newKey)
            guard result == 0 else { throw CBMPCError.refreshFailed }
            return CBMPCKeyShareMP(keyPtr: newKey)
        }
        let refreshedPK = refreshedKeys[0].getPublicKey()
        let pkPreserved = (refreshedPK == pubKeys[0])
        let dt = CFAbsoluteTimeGetCurrent() - t3
        steps.append(DemoStep(
            title: "4. Key Refresh",
            status: pkPreserved ? .success : .failure,
            detail: "PK preserved: \(pkPreserved ? "MATCH" : "MISMATCH")\nAll \(nParties) shares re-randomized simultaneously\nOld shares invalidated (forward secrecy)",
            duration: dt
        ))
        runner?.appendStep(steps.last!)
    } catch {
        let dt = CFAbsoluteTimeGetCurrent() - t3
        steps.append(DemoStep(title: "4. Refresh", status: .failure, detail: "\(error)", duration: dt))
        runner?.appendStep(steps.last!)
    }

    // -- Step 5: Summary --
    let allPass = steps.allSatisfy { $0.status == .success }
    let totalTime = steps.reduce(0.0) { $0 + $1.duration }
    steps.append(DemoStep(
        title: "5. Summary",
        status: allPass ? .success : .failure,
        detail: "EdDSA \(nParties)-party: DKG -> Consensus -> Sign -> Refresh\nCurve: Ed25519 | Sig: \(signature?.count ?? 0)B\nTotal: \(String(format: "%.0fms", totalTime * 1000))",
        duration: totalTime
    ))
    runner?.appendStep(steps.last!)

    return steps
}

#Preview {
    NavigationStack {
        EdDSADemoView()
    }
}
