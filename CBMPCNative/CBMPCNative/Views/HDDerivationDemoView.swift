import SwiftUI

/// HD Key Derivation demo: HD DKG, derive children at BIP44 paths, sign and verify with child keys
struct HDDerivationDemoView: View {
    @StateObject private var runner = DemoRunner()
    @State private var hasRun = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                DemoHeader(
                    title: "HD Key Derivation",
                    description: "BIP44 HD DKG, derive child keys at m/44'/0'/0'/0/0 and /1, sign and verify.",
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
            runHDDerivationDemo(runner: runner)
            runner.finish()
        }
    }
}

@discardableResult
func runHDDerivationDemo(runner: DemoRunner? = nil) -> [DemoStep] {
    var steps: [DemoStep] = []
    let curveCode = 714 // secp256k1
    let partyNames = ["party_0", "party_1"]

    // BIP44 paths: m/44'/0'/0'/0/0 and m/44'/0'/0'/0/1
    let path0: [UInt32] = [44 | 0x80000000, 0 | 0x80000000, 0 | 0x80000000, 0, 0]
    let path1: [UInt32] = [44 | 0x80000000, 0 | 0x80000000, 0 | 0x80000000, 0, 1]

    // -- Step 1: HD DKG --
    var hdKey0: CBMPCHDKeyShare?
    var hdKey1: CBMPCHDKeyShare?

    let t0 = CFAbsoluteTimeGetCurrent()
    do {
        let (hk0, hk1) = try LocalTwoPartyRunner.run(partyNames: partyNames) { job, role in
            var keyVar = cbmpc_hd_key_t()
            let result = cbmpc_hd_ecdsa2p_dkg(job.cJob, Int32(curveCode), &keyVar)
            guard result == 0 else { throw CBMPCError.keyGenerationFailed }
            return CBMPCHDKeyShare(keyPtr: keyVar, curveCode: curveCode)
        }
        hdKey0 = hk0
        hdKey1 = hk1
        let dt = CFAbsoluteTimeGetCurrent() - t0
        steps.append(DemoStep(
            title: "1. HD DKG",
            status: .success,
            detail: "Master HD keyset generated for party_0 + party_1\nCurve: secp256k1 (NID 714)\nC++: cbmpc_hd_ecdsa2p_dkg()",
            duration: dt
        ))
        runner?.appendStep(steps.last!)
    } catch {
        steps.append(DemoStep(title: "1. HD DKG", status: .failure, detail: "\(error)", duration: CFAbsoluteTimeGetCurrent() - t0))
        runner?.appendStep(steps.last!)
        return steps
    }

    // -- Step 2: Derive child at path0 --
    var childKey0_0: CBMPCKeyShare?
    var childKey0_1: CBMPCKeyShare?
    var childPubKey0: Data?

    let t1 = CFAbsoluteTimeGetCurrent()
    do {
        let (ck0, ck1) = try LocalTwoPartyRunner.run(partyNames: partyNames) { job, role in
            let hdKey = (role == 0) ? hdKey0! : hdKey1!
            return try hdKey.derive(path: path0, job: job)
        }
        childKey0_0 = ck0
        childKey0_1 = ck1
        childPubKey0 = ck0.getPublicKey()
        let dt = CFAbsoluteTimeGetCurrent() - t1
        let pubHex = childPubKey0.map { hexString($0) } ?? "nil"
        let sec1Valid = childPubKey0 != nil && childPubKey0!.count == 33
            && (childPubKey0![0] == 0x02 || childPubKey0![0] == 0x03)
        steps.append(DemoStep(
            title: "2. Derive m/44'/0'/0'/0/0",
            status: sec1Valid ? .success : .failure,
            detail: "PK (\(childPubKey0?.count ?? 0)B SEC1): \(pubHex.prefix(40))...\nBIP44 path [0x8000002c, 0x80000000, 0x80000000, 0, 0]\nFormat: \(sec1Valid ? "OK" : "FAIL") compressed SEC1",
            duration: dt
        ))
        runner?.appendStep(steps.last!)
    } catch {
        steps.append(DemoStep(title: "2. Derive", status: .failure, detail: "\(error)", duration: CFAbsoluteTimeGetCurrent() - t1))
        runner?.appendStep(steps.last!)
        return steps
    }

    // -- Step 3: Sign with child key 0 --
    let message = "HD child key signing test".data(using: .utf8)!
    let messageHash = sha256(message)
    let sessionId = "hd-session-1".data(using: .utf8)!
    var sig0: Data?

    let t2 = CFAbsoluteTimeGetCurrent()
    do {
        let (s0, _) = try LocalTwoPartyRunner.run(partyNames: partyNames) { job, role in
            let keyShare = (role == 0) ? childKey0_0! : childKey0_1!
            let sigs = try CBMPCSigner.signMessages([messageHash], with: keyShare, sessionId: sessionId, job: job)
            return sigs.first ?? Data()
        }
        sig0 = s0
        let dt = CFAbsoluteTimeGetCurrent() - t2
        let derValid = s0.count > 0 && s0[0] == 0x30
        steps.append(DemoStep(
            title: "3. Sign with Child 0",
            status: derValid ? .success : .failure,
            detail: "SHA256: \(hexString(messageHash).prefix(32))...\nDER (\(s0.count)B): \(hexString(s0).prefix(40))...\nFormat: \(derValid ? "OK" : "FAIL") DER (0x30 tag)",
            duration: dt
        ))
        runner?.appendStep(steps.last!)
    } catch {
        steps.append(DemoStep(title: "3. Sign", status: .failure, detail: "\(error)", duration: CFAbsoluteTimeGetCurrent() - t2))
        runner?.appendStep(steps.last!)
        return steps
    }

    // -- Step 4: Verify child key 0 signature --
    let t3 = CFAbsoluteTimeGetCurrent()
    let verified0 = CBMPCCryptoEngine.verifySignature(
        curveCode: curveCode,
        publicKey: childPubKey0!,
        messageHash: messageHash,
        derSignature: sig0!
    )
    let dt3 = CFAbsoluteTimeGetCurrent() - t3
    steps.append(DemoStep(
        title: "4. Verify Child 0 Signature",
        status: verified0 ? .success : .failure,
        detail: "ECDSA verify: \(verified0 ? "VALID" : "INVALID")\nPK \(childPubKey0!.count)B + hash \(messageHash.count)B + sig \(sig0!.count)B",
        duration: dt3
    ))
    runner?.appendStep(steps.last!)
    if !verified0 { return steps }

    // -- Step 5: Derive child at path1 --
    var childKey1_0: CBMPCKeyShare?
    var childKey1_1: CBMPCKeyShare?
    var childPubKey1: Data?

    let t4 = CFAbsoluteTimeGetCurrent()
    do {
        let (ck0, ck1) = try LocalTwoPartyRunner.run(partyNames: partyNames) { job, role in
            let hdKey = (role == 0) ? hdKey0! : hdKey1!
            return try hdKey.derive(path: path1, job: job)
        }
        childKey1_0 = ck0
        childKey1_1 = ck1
        childPubKey1 = ck0.getPublicKey()
        let dt = CFAbsoluteTimeGetCurrent() - t4
        let pubHex = childPubKey1.map { hexString($0) } ?? "nil"
        let sec1Valid = childPubKey1 != nil && childPubKey1!.count == 33
            && (childPubKey1![0] == 0x02 || childPubKey1![0] == 0x03)
        steps.append(DemoStep(
            title: "5. Derive m/44'/0'/0'/0/1",
            status: sec1Valid ? .success : .failure,
            detail: "PK (\(childPubKey1?.count ?? 0)B SEC1): \(pubHex.prefix(40))...\nBIP44 path [0x8000002c, 0x80000000, 0x80000000, 0, 1]\nFormat: \(sec1Valid ? "OK" : "FAIL") compressed SEC1",
            duration: dt
        ))
        runner?.appendStep(steps.last!)
    } catch {
        steps.append(DemoStep(title: "5. Derive", status: .failure, detail: "\(error)", duration: CFAbsoluteTimeGetCurrent() - t4))
        runner?.appendStep(steps.last!)
        return steps
    }

    // -- Step 6: Sign and verify with child key 1 --
    let message2 = "Second child key signing test".data(using: .utf8)!
    let messageHash2 = sha256(message2)
    let sessionId2 = "hd-session-2".data(using: .utf8)!

    let t5 = CFAbsoluteTimeGetCurrent()
    do {
        let (s1, _) = try LocalTwoPartyRunner.run(partyNames: partyNames) { job, role in
            let keyShare = (role == 0) ? childKey1_0! : childKey1_1!
            let sigs = try CBMPCSigner.signMessages([messageHash2], with: keyShare, sessionId: sessionId2, job: job)
            return sigs.first ?? Data()
        }
        let verified1 = CBMPCCryptoEngine.verifySignature(
            curveCode: curveCode,
            publicKey: childPubKey1!,
            messageHash: messageHash2,
            derSignature: s1
        )
        let dt = CFAbsoluteTimeGetCurrent() - t5
        let derValid = s1.count > 0 && s1[0] == 0x30
        steps.append(DemoStep(
            title: "6. Sign & Verify Child 1",
            status: (verified1 && derValid) ? .success : .failure,
            detail: "DER (\(s1.count)B): \(hexString(s1).prefix(40))...\nVerify: \(verified1 ? "VALID" : "INVALID") | DER: \(derValid ? "OK" : "FAIL")",
            duration: dt
        ))
        runner?.appendStep(steps.last!)
    } catch {
        steps.append(DemoStep(title: "6. Sign/Verify", status: .failure, detail: "\(error)", duration: CFAbsoluteTimeGetCurrent() - t5))
        runner?.appendStep(steps.last!)
        return steps
    }

    // -- Step 7: Cross-platform summary --
    let keysAreDifferent = (childPubKey0 != childPubKey1)
    let totalTime = steps.reduce(0.0) { $0 + $1.duration }
    steps.append(DemoStep(
        title: "7. Cross-Platform Verification",
        status: keysAreDifferent ? .success : .failure,
        detail: "Child keys differ: \(keysAreDifferent ? "YES" : "NO") (deterministic BIP32 derivation)\nC++: cbmpc_hd_ecdsa2p_derive() with uint32[] path\nSame HD master, same paths, same format\nTotal: \(String(format: "%.0fms", totalTime * 1000))",
        duration: totalTime
    ))
    runner?.appendStep(steps.last!)

    return steps
}

#Preview {
    NavigationStack {
        HDDerivationDemoView()
    }
}
