import SwiftUI

/// Live ECDSA multi-party demo: N-party DKG, signing, and verification
struct ECDSAMPDemoView: View {
    @StateObject private var runner = DemoRunner()
    @State private var hasRun = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                DemoHeader(
                    title: "ECDSA N-Party",
                    description: "Multi-party ECDSA key generation, threshold signing, and verification with N parties.",
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
            runECDSAMPDemo(runner: runner)
            runner.finish()
        }
    }
}

@discardableResult
func runECDSAMPDemo(runner: DemoRunner? = nil) -> [DemoStep] {
    var steps: [DemoStep] = []
    let nParties = 4
    let partyNames = (0..<nParties).map { "p\($0)" }
    let curveCode = 714 // secp256k1

    // -- Step 1: N-Party DKG --
    var keys: [CBMPCKeyShareMP] = []

    let t0 = CFAbsoluteTimeGetCurrent()
    do {
        let results = try LocalNPartyRunner.run(
            partyCount: nParties,
            partyNames: partyNames
        ) { job, role -> CBMPCKeyShareMP in
            let curve = CBMPCCurve(curveCode: curveCode)
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
            title: "1. \(nParties)-Party ECDSA DKG",
            status: .success,
            detail: "Parties: \(partyNames.joined(separator: ", "))\nPK (\(pubKey?.count ?? 0)B): \(pubHex.prefix(40))...\nCurve: secp256k1 | C++: eckey::key_share_mp_t::dkg()",
            duration: dt
        ))
        runner?.appendStep(steps.last!)
    } catch {
        let dt = CFAbsoluteTimeGetCurrent() - t0
        steps.append(DemoStep(title: "1. DKG", status: .failure, detail: "\(error)", duration: dt))
        runner?.appendStep(steps.last!)
        return steps
    }

    // -- Step 2: Verify public key consensus --
    let t1 = CFAbsoluteTimeGetCurrent()
    let pubKeys = keys.compactMap { $0.getPublicKey() }
    let allMatch = pubKeys.dropFirst().allSatisfy { $0 == pubKeys[0] }
    let partyNamesStr = keys.compactMap { $0.getPartyName() }.joined(separator: ", ")
    let dt1 = CFAbsoluteTimeGetCurrent() - t1
    steps.append(DemoStep(
        title: "2. Public Key Consensus",
        status: allMatch ? .success : .failure,
        detail: "All \(nParties) parties agree on PK: \(allMatch ? "YES" : "NO")\nParty names: \(partyNamesStr)\nEach party holds unique x_share, Qis",
        duration: dt1
    ))
    runner?.appendStep(steps.last!)

    // -- Step 3: ECDSA Multi-Party Signing --
    let message = "ECDSA multi-party threshold signature".data(using: .utf8)!
    let messageHash = sha256(message)
    let sigReceiver = 0
    var signature: Data?

    let t2 = CFAbsoluteTimeGetCurrent()
    do {
        let results = try LocalNPartyRunner.run(
            partyCount: nParties,
            partyNames: partyNames
        ) { job, role -> Data in
            var msgMem = cbmpc_cmem_t()
            messageHash.withUnsafeBytes { buf in
                msgMem.data = UnsafeMutableRawPointer(mutating: buf.baseAddress)
                msgMem.size = Int32(messageHash.count)
            }
            var sigMem = cbmpc_cmem_t()
            let result = cbmpc_ecdsamp_sign(job.cJob, &keys[role].keyPtr, msgMem, Int32(sigReceiver), &sigMem)
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
        let derValid = (signature?.first == 0x30)
        steps.append(DemoStep(
            title: "3. \(nParties)-Party ECDSA Sign",
            status: derValid ? .success : .failure,
            detail: "Msg: \"\(String(data: message, encoding: .utf8) ?? "")\"\nDER (\(signature?.count ?? 0)B): \(sigHex.prefix(40))...\nReceiver: p\(sigReceiver) | Format: \(derValid ? "OK" : "FAIL") DER",
            duration: dt
        ))
        runner?.appendStep(steps.last!)
    } catch {
        let dt = CFAbsoluteTimeGetCurrent() - t2
        steps.append(DemoStep(title: "3. Sign", status: .failure, detail: "\(error)", duration: dt))
        runner?.appendStep(steps.last!)
        return steps
    }

    // -- Step 4: Verify signature --
    let t3 = CFAbsoluteTimeGetCurrent()
    guard let sigToVerify = signature, !sigToVerify.isEmpty else {
        let dt3 = CFAbsoluteTimeGetCurrent() - t3
        steps.append(DemoStep(title: "4. Verify", status: .failure, detail: "No signature to verify", duration: dt3))
        runner?.appendStep(steps.last!)
        return steps
    }
    let verified = CBMPCCryptoEngine.verifySignature(
        curveCode: curveCode,
        publicKey: pubKeys[0],
        messageHash: messageHash,
        derSignature: sigToVerify
    )
    let dt3 = CFAbsoluteTimeGetCurrent() - t3
    steps.append(DemoStep(
        title: "4. Verify N-Party Signature",
        status: verified ? .success : .failure,
        detail: "ECDSA verify: \(verified ? "VALID" : "INVALID")\nStandard secp256k1 verification against MPC public key\nC++: cbmpc_ecdsa_verify()",
        duration: dt3
    ))
    runner?.appendStep(steps.last!)

    // -- Step 5: Serialize/Deserialize key shares --
    let t4 = CFAbsoluteTimeGetCurrent()
    var serOK = true
    for i in 0..<min(2, nParties) {
        guard let ser = keys[i].serialize() else { serOK = false; break }
        do {
            let restored = try CBMPCKeyShareMP.deserialize(ser)
            let restoredPK = restored.getPublicKey()
            if restoredPK != pubKeys[0] { serOK = false }
        } catch { serOK = false }
    }
    let dt4 = CFAbsoluteTimeGetCurrent() - t4
    steps.append(DemoStep(
        title: "5. Serialize Key Shares",
        status: serOK ? .success : .failure,
        detail: "Serialized \(min(2, nParties)) key shares to bytes and restored\nPublic key preserved after deserialization: \(serOK ? "YES" : "NO")\nFields: x_share, Q, Qis, curve, party_name",
        duration: dt4
    ))
    runner?.appendStep(steps.last!)

    // -- Step 6: Summary --
    let allPass = steps.allSatisfy { $0.status == .success }
    let totalTime = steps.reduce(0.0) { $0 + $1.duration }
    steps.append(DemoStep(
        title: "6. Summary",
        status: allPass ? .success : .failure,
        detail: "ECDSA \(nParties)-party: DKG -> Consensus -> Sign -> Verify -> Serialize\nCurve: secp256k1 | DER sig: \(sigToVerify.count)B\nTotal: \(String(format: "%.0fms", totalTime * 1000))",
        duration: totalTime
    ))
    runner?.appendStep(steps.last!)

    return steps
}

#Preview {
    NavigationStack {
        ECDSAMPDemoView()
    }
}
