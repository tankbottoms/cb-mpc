import SwiftUI
import os

private let demoLogger = Logger(subsystem: "xyz.atsignhandle.cb-mpc", category: "DemoTest")

enum DemoCategory: String, CaseIterable, Identifiable {
    case ecdsa2pc = "ECDSA 2-Party"
    case ecdsaMP = "ECDSA N-Party"
    case eddsaMP = "EdDSA N-Party"
    case hdDerivation = "HD Key Derivation"
    case batchSigning = "Batch Signing"
    case keyLifecycle = "Key Lifecycle"
    case zkProofs = "ZK Proofs"
    case nPartyBackup = "N-Party + Backup"
    case agreeRandom = "AgreeRandom"
    case accessStructures = "Access Structures"

    var id: String { rawValue }

    var isLive: Bool {
        switch self {
        case .ecdsa2pc, .ecdsaMP, .eddsaMP, .hdDerivation, .batchSigning, .keyLifecycle,
             .agreeRandom, .zkProofs, .nPartyBackup, .accessStructures:
            return true
        }
    }

    var groupLabel: String {
        isLive ? "Live" : "Conceptual"
    }
}

struct DemoHubView: View {
    @State private var selectedDemo: DemoCategory = .ecdsa2pc
    @State private var hasRunAllTests = false

    var body: some View {
        VStack(spacing: 0) {
            demoContent
        }
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            if !hasRunAllTests {
                hasRunAllTests = true
                DispatchQueue.global(qos: .userInitiated).async {
                    var log = ""

                    func logSteps(_ name: String, _ steps: [DemoStep]) {
                        let pass = steps.allSatisfy { $0.status == .success }
                        log += "\(name): \(pass ? "PASS" : "FAIL") (\(steps.count) steps)\n"
                        for step in steps {
                            log += "  \(step.title): \(step.status == .success ? "OK" : "FAIL") | \(step.detail.replacingOccurrences(of: "\n", with: " | "))\n"
                        }
                    }

                    logSteps("ZK Proofs", runZKProofDemo())
                    logSteps("ECDSA N-Party", runECDSAMPDemo())
                    logSteps("EdDSA N-Party", runEdDSADemo())

                    if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                        try? log.write(to: dir.appendingPathComponent("test_results.txt"), atomically: true, encoding: .utf8)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    ForEach(DemoCategory.allCases) { demo in
                        Button {
                            selectedDemo = demo
                        } label: {
                            if demo == selectedDemo {
                                Label(demo.rawValue, systemImage: "checkmark")
                            } else {
                                Text(demo.rawValue)
                            }
                        }
                    }
                } label: {
                    Text(selectedDemo.rawValue)
                        .font(.system(size: 10, weight: .medium))
                }
            }
        }
    }

    @ViewBuilder
    private var demoContent: some View {
        switch selectedDemo {
        case .ecdsa2pc:
            CryptoDemoView()
        case .ecdsaMP:
            ECDSAMPDemoView()
        case .eddsaMP:
            EdDSADemoView()
        case .hdDerivation:
            HDDerivationDemoView()
        case .batchSigning:
            BatchSigningDemoView()
        case .keyLifecycle:
            KeyLifecycleDemoView()
        case .zkProofs:
            ZKProofDemoView()
        case .nPartyBackup:
            NPartyDemoView()
        case .agreeRandom:
            AgreeRandomDemoView()
        case .accessStructures:
            AccessStructureDemoView()
        }
    }
}

#if DEBUG
private func runAllDemoTests() {
    DispatchQueue.global(qos: .userInitiated).async {
        NSLog("[DEMO-TEST] === DEMO TEST SUITE START ===")
        demoLogger.info("=== DEMO TEST SUITE START ===")
        var testLog = "=== DEMO TEST SUITE START ===\n"

        // Run ZK test FIRST (isolated, no MPC threading needed)
        // Test 5: ZK Proofs
        NSLog("[DEMO-TEST] ZK Proofs: starting...")
        demoLogger.info("[TEST] ZK Proofs: starting...")
        let zkSteps = runZKProofDemo()
        let zkPass = zkSteps.allSatisfy { $0.status == .success }
        NSLog("[DEMO-TEST] ZK Proofs: %@ (%d steps)", zkPass ? "PASS" : "FAIL", zkSteps.count)
        demoLogger.info("[TEST] ZK Proofs: \(zkPass ? "PASS" : "FAIL") (\(zkSteps.count) steps)")
        for step in zkSteps {
            demoLogger.info("  \(step.title): \(step.status == .success ? "OK" : step.status == .failure ? "FAIL" : "INFO")")
        }

        // Write ZK results immediately
        testLog += "ZK Proofs: \(zkPass ? "PASS" : "FAIL") (\(zkSteps.count) steps)\n"
        for step in zkSteps {
            testLog += "  \(step.title): \(step.status == .success ? "OK" : "FAIL") | \(step.detail.replacingOccurrences(of: "\n", with: " | "))\n"
        }
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? testLog.write(to: dir.appendingPathComponent("test_results.txt"), atomically: true, encoding: .utf8)
        }

        // Remaining tests (may deadlock with concurrent MPC, run after ZK)

        // Test 1: HD Derivation
        demoLogger.info("[TEST] HD Derivation: starting...")
        let hdSteps = runHDDerivationDemo()
        let hdPass = hdSteps.allSatisfy { $0.status == .success }
        demoLogger.info("[TEST] HD Derivation: \(hdPass ? "PASS" : "FAIL") (\(hdSteps.count) steps)")
        for step in hdSteps {
            demoLogger.info("  \(step.title): \(step.status == .success ? "OK" : step.status == .failure ? "FAIL" : "INFO")")
        }

        // Test 2: Batch Signing
        demoLogger.info("[TEST] Batch Signing: starting...")
        let batchSteps = runBatchSigningDemo()
        let batchPass = batchSteps.allSatisfy { $0.status == .success }
        demoLogger.info("[TEST] Batch Signing: \(batchPass ? "PASS" : "FAIL") (\(batchSteps.count) steps)")
        for step in batchSteps {
            demoLogger.info("  \(step.title): \(step.status == .success ? "OK" : step.status == .failure ? "FAIL" : "INFO")")
        }

        // Test 3: Key Lifecycle
        demoLogger.info("[TEST] Key Lifecycle: starting...")
        let lifecycleSteps = runKeyLifecycleDemo()
        let lifecyclePass = lifecycleSteps.allSatisfy { $0.status == .success }
        demoLogger.info("[TEST] Key Lifecycle: \(lifecyclePass ? "PASS" : "FAIL") (\(lifecycleSteps.count) steps)")
        for step in lifecycleSteps {
            demoLogger.info("  \(step.title): \(step.status == .success ? "OK" : step.status == .failure ? "FAIL" : "INFO")")
        }

        // Test 4: AgreeRandom
        demoLogger.info("[TEST] AgreeRandom: starting...")
        let agreeSteps = runAgreeRandomDemo()
        let agreePass = agreeSteps.allSatisfy { $0.status == .success }
        demoLogger.info("[TEST] AgreeRandom: \(agreePass ? "PASS" : "FAIL") (\(agreeSteps.count) steps)")
        for step in agreeSteps {
            demoLogger.info("  \(step.title): \(step.status == .success ? "OK" : step.status == .failure ? "FAIL" : "INFO")")
        }

        // Test 6: ECDSA N-Party
        demoLogger.info("[TEST] ECDSA N-Party: starting...")
        let ecdsaMPSteps = runECDSAMPDemo()
        let ecdsaMPPass = ecdsaMPSteps.allSatisfy { $0.status == .success }
        demoLogger.info("[TEST] ECDSA N-Party: \(ecdsaMPPass ? "PASS" : "FAIL") (\(ecdsaMPSteps.count) steps)")
        for step in ecdsaMPSteps {
            demoLogger.info("  \(step.title): \(step.status == .success ? "OK" : step.status == .failure ? "FAIL" : "INFO")")
        }

        // Test 7: EdDSA N-Party
        demoLogger.info("[TEST] EdDSA N-Party: starting...")
        let eddsaSteps = runEdDSADemo()
        let eddsaPass = eddsaSteps.allSatisfy { $0.status == .success }
        demoLogger.info("[TEST] EdDSA N-Party: \(eddsaPass ? "PASS" : "FAIL") (\(eddsaSteps.count) steps)")
        for step in eddsaSteps {
            demoLogger.info("  \(step.title): \(step.status == .success ? "OK" : step.status == .failure ? "FAIL" : "INFO")")
        }

        // Test 8: Access Structures
        demoLogger.info("[TEST] Access Structures: starting...")
        let acSteps = runAccessStructureDemo()
        let acPass = acSteps.allSatisfy { $0.status == .success }
        demoLogger.info("[TEST] Access Structures: \(acPass ? "PASS" : "FAIL") (\(acSteps.count) steps)")
        for step in acSteps {
            demoLogger.info("  \(step.title): \(step.status == .success ? "OK" : step.status == .failure ? "FAIL" : "INFO")")
        }

        let allPass = hdPass && batchPass && lifecyclePass && agreePass && zkPass && ecdsaMPPass && eddsaPass && acPass
        demoLogger.info("=== DEMO TEST SUITE \(allPass ? "ALL PASS" : "SOME FAILED") ===")

        // Write results to file for debugging
        testLog += "HD Derivation: \(hdPass ? "PASS" : "FAIL") (\(hdSteps.count) steps)\n"
        testLog += "Batch Signing: \(batchPass ? "PASS" : "FAIL") (\(batchSteps.count) steps)\n"
        testLog += "Key Lifecycle: \(lifecyclePass ? "PASS" : "FAIL") (\(lifecycleSteps.count) steps)\n"
        testLog += "AgreeRandom: \(agreePass ? "PASS" : "FAIL") (\(agreeSteps.count) steps)\n"
        testLog += "ZK Proofs: \(zkPass ? "PASS" : "FAIL") (\(zkSteps.count) steps)\n"
        for step in zkSteps {
            testLog += "  \(step.title): \(step.status == .success ? "OK" : "FAIL") - \(step.detail.prefix(80))\n"
        }
        testLog += "ECDSA N-Party: \(ecdsaMPPass ? "PASS" : "FAIL") (\(ecdsaMPSteps.count) steps)\n"
        testLog += "EdDSA N-Party: \(eddsaPass ? "PASS" : "FAIL") (\(eddsaSteps.count) steps)\n"
        testLog += "Access Structures: \(acPass ? "PASS" : "FAIL") (\(acSteps.count) steps)\n"
        testLog += "=== ALL \(allPass ? "PASS" : "SOME FAILED") ===\n"
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = dir.appendingPathComponent("test_results.txt")
            try? testLog.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }
}
#endif

#Preview {
    NavigationStack {
        DemoHubView()
    }
}
