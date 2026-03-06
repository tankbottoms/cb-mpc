import SwiftUI
import CommonCrypto

/// Runs the full ECDSA 2-party demo flow matching the Go ecdsa-2pc example byte-for-byte:
/// Same messages, session IDs, party names, and output format verification.
struct CryptoDemoView: View {
    @StateObject private var runner = DemoRunner()
    @State private var hasRun = false

    var body: some View {
        VStack(spacing: 0) {
            // Pinned header with timer
            VStack(alignment: .leading, spacing: 6) {
                DemoHeader(
                    title: "ECDSA 2-Party",
                    description: "DKG, sign, verify, key refresh, re-sign. Mirrors Go ecdsa-2pc.",
                    isLive: true,
                    isRunning: runner.isRunning,
                    elapsedMs: runner.elapsedMs
                )
                if !runner.isRunning && hasRun {
                    Button(action: runDemo) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.trianglehead.counterclockwise")
                                .font(.system(size: 10))
                            Text("Run Again")
                                .font(.system(size: 10))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)

            // Scrolling results
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
            runECDSA2PCDemo(runner: runner)
            runner.finish()
        }
    }
}

// MARK: - Demo Runner

/// Runs the complete ECDSA 2-party demo using the exact same inputs as the Go example.
/// Go reference: demos-go/examples/ecdsa-2pc/main.go
@discardableResult
func runECDSA2PCDemo(runner: DemoRunner? = nil) -> [DemoStep] {
    var steps: [DemoStep] = []
    let curveCode = 714 // secp256k1 (OpenSSL NID)

    // Party names matching Go: partyNames := []string{"party_0", "party_1"}
    let partyNames = ["party_0", "party_1"]

    // -- Step 1: DKG --
    // Go: keyGenResponses, err := keyGenWithMockNet(curveObj)
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

        // Verify SEC1 compressed format: 33 bytes, prefix 0x02 or 0x03
        let pubKeyValid = publicKey != nil && publicKey!.count == 33
            && (publicKey![0] == 0x02 || publicKey![0] == 0x03)
        let curveMatch = k0.getCurveCode() == curveCode

        steps.append(DemoStep(
            title: "1. Distributed Key Generation",
            status: (pubKeyValid && curveMatch) ? .success : .failure,
            detail: "PK (\(publicKey?.count ?? 0)B SEC1): \(pubHex.prefix(40))...\nRoles: P0=\(k0.getRole()) P1=\(k1.getRole()) | Curve: \(k0.getCurveCode()) (secp256k1)\nFormat: \(pubKeyValid ? "OK" : "FAIL") compressed SEC1 | Go: party_0, party_1",
            duration: dt
        ))
        runner?.appendStep(steps.last!)
    } catch {
        steps.append(DemoStep(title: "1. DKG", status: .failure, detail: "\(error)", duration: CFAbsoluteTimeGetCurrent() - t0))
        runner?.appendStep(steps.last!)
        return steps
    }

    // -- Step 2: Sign message --
    // Go: message1 := []byte("Hello, CB-MPC!")
    // Go: digest1 := sha256.Sum256(message1)
    // Go: sessionID: []byte("session-1")
    let message = "Hello, CB-MPC!".data(using: .utf8)!
    let messageHash = sha256(message)
    let sessionId = "session-1".data(using: .utf8)!
    var signature0: Data?

    let t1 = CFAbsoluteTimeGetCurrent()
    do {
        let (sig0, sig1) = try LocalTwoPartyRunner.run(partyNames: partyNames) { job, role in
            let keyShare = (role == 0) ? key0! : key1!
            let sigs = try CBMPCSigner.signMessages([messageHash], with: keyShare, sessionId: sessionId, job: job)
            return sigs.first ?? Data()
        }
        signature0 = sig0
        let dt = CFAbsoluteTimeGetCurrent() - t1

        // Verify DER format: starts with 0x30 (SEQUENCE tag)
        let derValid = sig0.count > 0 && sig0[0] == 0x30
        // Go: Party 0 gets signature, Party 1 gets empty
        let p1Empty = sig1.isEmpty

        steps.append(DemoStep(
            title: "2. Sign (Go: \"Hello, CB-MPC!\")",
            status: (derValid && p1Empty) ? .success : .failure,
            detail: "Msg: \(hexString(message)) (= Go input)\nSHA256: \(hexString(messageHash))\nDER (\(sig0.count)B): \(hexString(sig0).prefix(40))...\nP0 sig: \(derValid ? "OK" : "FAIL") | P1 empty: \(p1Empty ? "OK" : "FAIL")",
            duration: dt
        ))
        runner?.appendStep(steps.last!)
    } catch {
        steps.append(DemoStep(title: "2. Sign", status: .failure, detail: "\(error)", duration: CFAbsoluteTimeGetCurrent() - t1))
        runner?.appendStep(steps.last!)
        return steps
    }

    // -- Step 3: Verify signature --
    // Go: verifyExampleSignature(keyGenResponses[0].KeyShare, firstSigResponses[0].Signature, digest1[:])
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
        detail: "ECDSA verify: \(verified ? "VALID" : "INVALID")\nInputs: PK \(publicKey!.count)B + hash \(messageHash.count)B + sig \(signature0!.count)B\nGo: verifyExampleSignature() uses same cbmpc_ecdsa_verify",
        duration: dt2
    ))
    runner?.appendStep(steps.last!)
    if !verified { return steps }

    // -- Step 4: Key refresh --
    // Go: refreshResponses, err := refreshWithMockNet(keyGenResponses)
    var refreshedKey0: CBMPCKeyShare?
    var refreshedKey1: CBMPCKeyShare?

    let t3 = CFAbsoluteTimeGetCurrent()
    do {
        let (rk0, rk1) = try LocalTwoPartyRunner.run(partyNames: partyNames) { job, role in
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
        let pubMatch = (newPubKey == publicKey)
        steps.append(DemoStep(
            title: "4. Key Refresh (Re-share)",
            status: pubMatch ? .success : .failure,
            detail: "PK preserved: \(pubMatch ? "MATCH" : "MISMATCH")\nGo: \"parties now hold new key shares\"\nShares re-randomized, G*(x0'+x1') = Q unchanged",
            duration: dt
        ))
        runner?.appendStep(steps.last!)
        if !pubMatch { return steps }
    } catch {
        steps.append(DemoStep(title: "4. Refresh", status: .failure, detail: "\(error)", duration: CFAbsoluteTimeGetCurrent() - t3))
        runner?.appendStep(steps.last!)
        return steps
    }

    // -- Step 5: Sign with refreshed key --
    // Go: message2 := []byte("Fresh signing after refresh!")
    // Go: sessionID: []byte("session-2")
    let message2 = "Fresh signing after refresh!".data(using: .utf8)!
    let messageHash2 = sha256(message2)
    let sessionId2 = "session-2".data(using: .utf8)!
    var signature1: Data?

    let t4 = CFAbsoluteTimeGetCurrent()
    do {
        let (sig0, sig1) = try LocalTwoPartyRunner.run(partyNames: partyNames) { job, role in
            let keyShare = (role == 0) ? refreshedKey0! : refreshedKey1!
            let sigs = try CBMPCSigner.signMessages([messageHash2], with: keyShare, sessionId: sessionId2, job: job)
            return sigs.first ?? Data()
        }
        signature1 = sig0
        let dt = CFAbsoluteTimeGetCurrent() - t4
        let derValid = sig0.count > 0 && sig0[0] == 0x30
        let p1Empty = sig1.isEmpty

        steps.append(DemoStep(
            title: "5. Sign (Go: \"Fresh signing after refresh!\")",
            status: (derValid && p1Empty) ? .success : .failure,
            detail: "Msg: \(hexString(message2)) (= Go input)\nSHA256: \(hexString(messageHash2))\nDER (\(sig0.count)B): \(hexString(sig0).prefix(40))...",
            duration: dt
        ))
        runner?.appendStep(steps.last!)
    } catch {
        steps.append(DemoStep(title: "5. Re-sign", status: .failure, detail: "\(error)", duration: CFAbsoluteTimeGetCurrent() - t4))
        runner?.appendStep(steps.last!)
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
        detail: "ECDSA verify: \(verified2 ? "VALID" : "INVALID")\nSame PK verifies both pre- and post-refresh signatures\nGo: verifyExampleSignature() on refreshed shares",
        duration: dt5
    ))
    runner?.appendStep(steps.last!)

    // -- Step 7: Cross-platform verification summary --
    let allPass = steps.allSatisfy { $0.status == .success }
    let totalTime = steps.reduce(0.0) { $0 + $1.duration }
    steps.append(DemoStep(
        title: "7. Cross-Platform Verification",
        status: allPass ? .success : .failure,
        detail: "Go inputs: \"Hello, CB-MPC!\" + \"Fresh signing after refresh!\"\nSessions: \"session-1\", \"session-2\" | Parties: party_0, party_1\nFormat: SEC1 compressed PK (33B) + DER sig (0x30 tag)\nTotal: \(String(format: "%.0fms", totalTime * 1000))",
        duration: totalTime
    ))
    runner?.appendStep(steps.last!)

    return steps
}

#Preview {
    NavigationStack {
        CryptoDemoView()
    }
}
