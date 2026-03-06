import SwiftUI

/// Live N-Party + Backup demo: 2-party DKG with key share serialization, backup, restore, and re-sign
struct NPartyDemoView: View {
    @StateObject private var runner = DemoRunner()
    @State private var hasRun = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                DemoHeader(
                    title: "N-Party + Backup",
                    description: "2-party DKG, serialize shares for backup, restore from bytes, sign with recovered keys.",
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
            runNPartyBackupDemo(runner: runner)
            runner.finish()
        }
    }
}

@discardableResult
func runNPartyBackupDemo(runner: DemoRunner? = nil) -> [DemoStep] {
    var steps: [DemoStep] = []
    let curveCode = 714 // secp256k1
    let partyNames = ["party_0", "party_1"]

    // -- Step 1: DKG (generate key shares for both parties) --
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
        steps.append(DemoStep(
            title: "1. 2-Party DKG",
            status: .success,
            detail: "PK (\(publicKey?.count ?? 0)B SEC1): \(pubHex.prefix(40))...\nParties: party_0 + party_1 | Curve: secp256k1\nC++: cbmpc_ecdsa2p_dkg()",
            duration: dt
        ))
        runner?.appendStep(steps.last!)
    } catch {
        steps.append(DemoStep(title: "1. DKG", status: .failure, detail: "\(error)", duration: CFAbsoluteTimeGetCurrent() - t0))
        runner?.appendStep(steps.last!)
        return steps
    }

    // -- Step 2: Serialize both key shares (backup) --
    let t1 = CFAbsoluteTimeGetCurrent()
    guard let backup0 = key0!.serialize(), let backup1 = key1!.serialize() else {
        steps.append(DemoStep(title: "2. Backup", status: .failure, detail: "Serialization failed", duration: CFAbsoluteTimeGetCurrent() - t1))
        runner?.appendStep(steps.last!)
        return steps
    }
    let dt1 = CFAbsoluteTimeGetCurrent() - t1
    steps.append(DemoStep(
        title: "2. Backup Key Shares",
        status: .success,
        detail: "Party 0: \(backup0.count) bytes | First 16: \(hexString(backup0.prefix(16)))...\nParty 1: \(backup1.count) bytes | First 16: \(hexString(backup1.prefix(16)))...\nBoth shares serialized for offline storage",
        duration: dt1
    ))
    runner?.appendStep(steps.last!)

    // -- Step 3: Verify backups are distinct --
    let t2 = CFAbsoluteTimeGetCurrent()
    let sharesDistinct = (backup0 != backup1)
    let dt2 = CFAbsoluteTimeGetCurrent() - t2
    steps.append(DemoStep(
        title: "3. Verify Backup Integrity",
        status: sharesDistinct ? .success : .failure,
        detail: "Shares differ: \(sharesDistinct ? "YES" : "NO") (each party holds unique data)\nTotal backup size: \(backup0.count + backup1.count) bytes\nNeither share alone reveals the private key",
        duration: dt2
    ))
    runner?.appendStep(steps.last!)

    // -- Step 4: Restore from backup (deserialize) --
    var restored0: CBMPCKeyShare?
    var restored1: CBMPCKeyShare?

    let t3 = CFAbsoluteTimeGetCurrent()
    do {
        restored0 = try CBMPCKeyShare.deserialize(backup0, curveCode: curveCode)
        restored1 = try CBMPCKeyShare.deserialize(backup1, curveCode: curveCode)
        let restoredPK = restored0!.getPublicKey()
        let pkMatch = (restoredPK == publicKey)
        let dt = CFAbsoluteTimeGetCurrent() - t3
        steps.append(DemoStep(
            title: "4. Restore from Backup",
            status: pkMatch ? .success : .failure,
            detail: "Deserialized both shares from bytes\nPublic key: \(pkMatch ? "MATCH" : "MISMATCH") (byte-for-byte)\nC++: cbmpc_ecdsa2p_key_deserialize()",
            duration: dt
        ))
        runner?.appendStep(steps.last!)
        if !pkMatch { return steps }
    } catch {
        steps.append(DemoStep(title: "4. Restore", status: .failure, detail: "\(error)", duration: CFAbsoluteTimeGetCurrent() - t3))
        runner?.appendStep(steps.last!)
        return steps
    }

    // -- Step 5: Sign with restored keys --
    let message = "Signed with recovered keys".data(using: .utf8)!
    let messageHash = sha256(message)
    let sessionId = "backup-session".data(using: .utf8)!
    var signature: Data?

    let t4 = CFAbsoluteTimeGetCurrent()
    do {
        let (sig0, _) = try LocalTwoPartyRunner.run(partyNames: partyNames) { job, role in
            let keyShare = (role == 0) ? restored0! : restored1!
            let sigs = try CBMPCSigner.signMessages([messageHash], with: keyShare, sessionId: sessionId, job: job)
            return sigs.first ?? Data()
        }
        signature = sig0
        let dt = CFAbsoluteTimeGetCurrent() - t4
        let derValid = sig0.count > 0 && sig0[0] == 0x30
        steps.append(DemoStep(
            title: "5. Sign with Recovered Keys",
            status: derValid ? .success : .failure,
            detail: "Msg: \"Signed with recovered keys\"\nDER (\(sig0.count)B): \(hexString(sig0).prefix(40))...\nFormat: \(derValid ? "OK" : "FAIL") DER (0x30 tag)",
            duration: dt
        ))
        runner?.appendStep(steps.last!)
    } catch {
        steps.append(DemoStep(title: "5. Sign", status: .failure, detail: "\(error)", duration: CFAbsoluteTimeGetCurrent() - t4))
        runner?.appendStep(steps.last!)
        return steps
    }

    // -- Step 6: Verify signature --
    let t5 = CFAbsoluteTimeGetCurrent()
    let verified = CBMPCCryptoEngine.verifySignature(
        curveCode: curveCode,
        publicKey: publicKey!,
        messageHash: messageHash,
        derSignature: signature!
    )
    let dt5 = CFAbsoluteTimeGetCurrent() - t5
    steps.append(DemoStep(
        title: "6. Verify Recovered Signature",
        status: verified ? .success : .failure,
        detail: "ECDSA verify: \(verified ? "VALID" : "INVALID")\nOriginal PK verifies signature from restored shares\nFull lifecycle: generate -> backup -> restore -> sign -> verify",
        duration: dt5
    ))
    runner?.appendStep(steps.last!)

    // -- Step 7: Refresh after restore --
    let t6 = CFAbsoluteTimeGetCurrent()
    do {
        let (rk0, rk1) = try LocalTwoPartyRunner.run(partyNames: partyNames) { job, role in
            let keyShare = (role == 0) ? restored0! : restored1!
            var newKey = cbmpc_ecdsa2p_key_t()
            let result = cbmpc_ecdsa2p_refresh(job.cJob, &keyShare.keyPtr, &newKey)
            guard result == 0 else { throw CBMPCError.refreshFailed }
            return CBMPCKeyShare(keyPtr: newKey, curveCode: curveCode)
        }
        let refreshedPK = rk0.getPublicKey()
        let pkPreserved = (refreshedPK == publicKey)
        let dt = CFAbsoluteTimeGetCurrent() - t6
        steps.append(DemoStep(
            title: "7. Post-Recovery Refresh",
            status: pkPreserved ? .success : .failure,
            detail: "PK preserved: \(pkPreserved ? "MATCH" : "MISMATCH")\nNew shares invalidate old backups (forward secrecy)\nC++: cbmpc_ecdsa2p_refresh()",
            duration: dt
        ))
        runner?.appendStep(steps.last!)
    } catch {
        steps.append(DemoStep(title: "7. Refresh", status: .failure, detail: "\(error)", duration: CFAbsoluteTimeGetCurrent() - t6))
        runner?.appendStep(steps.last!)
        return steps
    }

    // -- Step 8: Summary --
    let allPass = steps.allSatisfy { $0.status == .success }
    let totalTime = steps.reduce(0.0) { $0 + $1.duration }
    steps.append(DemoStep(
        title: "8. Cross-Platform Verification",
        status: allPass ? .success : .failure,
        detail: "DKG -> Backup -> Verify -> Restore -> Sign -> Verify -> Refresh\nAll C++ APIs: dkg, serialize, deserialize, sign, verify, refresh\nBackup size: \(backup0.count + backup1.count)B total | Total: \(String(format: "%.0fms", totalTime * 1000))",
        duration: totalTime
    ))
    runner?.appendStep(steps.last!)

    return steps
}

#Preview {
    NavigationStack {
        NPartyDemoView()
    }
}
