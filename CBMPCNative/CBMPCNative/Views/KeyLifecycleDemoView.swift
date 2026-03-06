import SwiftUI

/// Key Lifecycle demo: DKG, serialize, deserialize, sign/verify, refresh, verify same pubkey, re-serialize
struct KeyLifecycleDemoView: View {
    @StateObject private var runner = DemoRunner()
    @State private var hasRun = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                DemoHeader(
                    title: "Key Lifecycle",
                    description: "DKG, serialize, deserialize, sign, refresh, verify PK unchanged.",
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
            runKeyLifecycleDemo(runner: runner)
            runner.finish()
        }
    }
}

@discardableResult
func runKeyLifecycleDemo(runner: DemoRunner? = nil) -> [DemoStep] {
    var steps: [DemoStep] = []
    let curveCode = 714 // secp256k1
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
        let sec1Valid = publicKey != nil && publicKey!.count == 33
            && (publicKey![0] == 0x02 || publicKey![0] == 0x03)
        steps.append(DemoStep(
            title: "1. Key Generation (DKG)",
            status: sec1Valid ? .success : .failure,
            detail: "PK (\(publicKey?.count ?? 0)B SEC1): \(pubHex.prefix(40))...\nFormat: \(sec1Valid ? "OK" : "FAIL") compressed SEC1",
            duration: dt
        ))
        runner?.appendStep(steps.last!)
    } catch {
        steps.append(DemoStep(title: "1. DKG", status: .failure, detail: "\(error)", duration: CFAbsoluteTimeGetCurrent() - t0))
        runner?.appendStep(steps.last!)
        return steps
    }

    // -- Step 2: Serialize --
    let t1 = CFAbsoluteTimeGetCurrent()
    guard let serialized0 = key0!.serialize() else {
        steps.append(DemoStep(title: "2. Serialize", status: .failure, detail: "Failed to serialize key share", duration: CFAbsoluteTimeGetCurrent() - t1))
        runner?.appendStep(steps.last!)
        return steps
    }
    let dt1 = CFAbsoluteTimeGetCurrent() - t1
    steps.append(DemoStep(
        title: "2. Serialize Key Share",
        status: .success,
        detail: "\(serialized0.count) bytes | First 16: \(hexString(serialized0.prefix(16)))...\nC++: cbmpc_ecdsa2p_key_serialize() -> cbmpc_cmem_t",
        duration: dt1
    ))
    runner?.appendStep(steps.last!)

    // -- Step 3: Deserialize --
    var deserializedKey0: CBMPCKeyShare?
    let t2 = CFAbsoluteTimeGetCurrent()
    do {
        deserializedKey0 = try CBMPCKeyShare.deserialize(serialized0, curveCode: curveCode)
        let dt = CFAbsoluteTimeGetCurrent() - t2
        let roundtripPubKey = deserializedKey0!.getPublicKey()
        let pubMatch = (roundtripPubKey == publicKey)
        steps.append(DemoStep(
            title: "3. Deserialize Key Share",
            status: pubMatch ? .success : .failure,
            detail: "Roundtrip PK: \(pubMatch ? "MATCH" : "MISMATCH") (byte-for-byte)\nDeserialized \(serialized0.count) bytes -> same SEC1 public key",
            duration: dt
        ))
        runner?.appendStep(steps.last!)
        if !pubMatch { return steps }
    } catch {
        steps.append(DemoStep(title: "3. Deserialize", status: .failure, detail: "\(error)", duration: CFAbsoluteTimeGetCurrent() - t2))
        runner?.appendStep(steps.last!)
        return steps
    }

    // -- Step 4: Sign and verify with deserialized key --
    let message = "Signing with deserialized key".data(using: .utf8)!
    let messageHash = sha256(message)
    let sessionId = "lifecycle-session".data(using: .utf8)!

    let t3 = CFAbsoluteTimeGetCurrent()
    do {
        let (sig0, _) = try LocalTwoPartyRunner.run(partyNames: partyNames) { job, role in
            let keyShare = (role == 0) ? deserializedKey0! : key1!
            let sigs = try CBMPCSigner.signMessages([messageHash], with: keyShare, sessionId: sessionId, job: job)
            return sigs.first ?? Data()
        }
        let verified = CBMPCCryptoEngine.verifySignature(
            curveCode: curveCode,
            publicKey: publicKey!,
            messageHash: messageHash,
            derSignature: sig0
        )
        let dt = CFAbsoluteTimeGetCurrent() - t3
        let derValid = sig0.count > 0 && sig0[0] == 0x30
        steps.append(DemoStep(
            title: "4. Sign & Verify (Deserialized)",
            status: (verified && derValid) ? .success : .failure,
            detail: "DER (\(sig0.count)B): \(hexString(sig0).prefix(40))...\nVerify: \(verified ? "VALID" : "INVALID") | DER: \(derValid ? "OK" : "FAIL")",
            duration: dt
        ))
        runner?.appendStep(steps.last!)
        if !verified { return steps }
    } catch {
        steps.append(DemoStep(title: "4. Sign/Verify", status: .failure, detail: "\(error)", duration: CFAbsoluteTimeGetCurrent() - t3))
        runner?.appendStep(steps.last!)
        return steps
    }

    // -- Step 5: Refresh --
    var refreshedKey0: CBMPCKeyShare?
    var refreshedKey1: CBMPCKeyShare?

    let t4 = CFAbsoluteTimeGetCurrent()
    do {
        let (rk0, rk1) = try LocalTwoPartyRunner.run(partyNames: partyNames) { job, role in
            let keyShare = (role == 0) ? deserializedKey0! : key1!
            var newKey = cbmpc_ecdsa2p_key_t()
            let result = cbmpc_ecdsa2p_refresh(job.cJob, &keyShare.keyPtr, &newKey)
            guard result == 0 else { throw CBMPCError.refreshFailed }
            return CBMPCKeyShare(keyPtr: newKey, curveCode: curveCode)
        }
        refreshedKey0 = rk0
        refreshedKey1 = rk1
        let dt = CFAbsoluteTimeGetCurrent() - t4
        steps.append(DemoStep(
            title: "5. Refresh Key Shares",
            status: .success,
            detail: "Shares re-randomized | Go invariant: G*(x0'+x1') = Q\nC++: cbmpc_ecdsa2p_refresh()",
            duration: dt
        ))
        runner?.appendStep(steps.last!)
    } catch {
        steps.append(DemoStep(title: "5. Refresh", status: .failure, detail: "\(error)", duration: CFAbsoluteTimeGetCurrent() - t4))
        runner?.appendStep(steps.last!)
        return steps
    }

    // -- Step 6: Verify same public key --
    let t5 = CFAbsoluteTimeGetCurrent()
    let refreshedPubKey = refreshedKey0!.getPublicKey()
    let pubMatch = (refreshedPubKey == publicKey)
    let dt5 = CFAbsoluteTimeGetCurrent() - t5
    steps.append(DemoStep(
        title: "6. Verify PK Unchanged",
        status: pubMatch ? .success : .failure,
        detail: "PK after refresh: \(pubMatch ? "MATCH" : "MISMATCH") (byte-for-byte)\nGo test: origQ.Equals(newQ0) == true",
        duration: dt5
    ))
    runner?.appendStep(steps.last!)
    if !pubMatch { return steps }

    // -- Step 7: Serialize refreshed key --
    let t6 = CFAbsoluteTimeGetCurrent()
    guard let refreshedSerialized = refreshedKey0!.serialize() else {
        steps.append(DemoStep(title: "7. Serialize Refreshed", status: .failure, detail: "Failed", duration: CFAbsoluteTimeGetCurrent() - t6))
        runner?.appendStep(steps.last!)
        return steps
    }
    let dt6 = CFAbsoluteTimeGetCurrent() - t6
    let bytesChanged = (refreshedSerialized != serialized0)
    steps.append(DemoStep(
        title: "7. Serialize Refreshed Key",
        status: bytesChanged ? .success : .failure,
        detail: "\(refreshedSerialized.count) bytes | Bytes differ: \(bytesChanged ? "YES" : "NO")\nSame PK, different share data (re-randomized)",
        duration: dt6
    ))
    runner?.appendStep(steps.last!)

    // -- Step 8: Cross-platform summary --
    let totalTime = steps.reduce(0.0) { $0 + $1.duration }
    steps.append(DemoStep(
        title: "8. Cross-Platform Verification",
        status: steps.allSatisfy({ $0.status == .success }) ? .success : .failure,
        detail: "DKG -> Serialize -> Deserialize -> Sign -> Refresh -> Verify -> Re-serialize\nAll C++ APIs matched: serialize/deserialize roundtrip, refresh invariant\nTotal: \(String(format: "%.0fms", totalTime * 1000))",
        duration: totalTime
    ))
    runner?.appendStep(steps.last!)

    return steps
}

#Preview {
    NavigationStack {
        KeyLifecycleDemoView()
    }
}
