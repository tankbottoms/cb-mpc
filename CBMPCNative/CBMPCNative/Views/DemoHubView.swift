import SwiftUI
import os

private let demoLogger = Logger(subsystem: "xyz.atsignhandle.cb-mpc", category: "DemoTest")

enum DemoCategory: String, CaseIterable, Identifiable {
    case ecdsa2pc = "ECDSA 2-Party"
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
        case .ecdsa2pc, .hdDerivation, .batchSigning, .keyLifecycle, .agreeRandom, .zkProofs, .nPartyBackup:
            return true
        case .accessStructures:
            return false
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
            #if DEBUG
            if !hasRunAllTests {
                hasRunAllTests = true
                runAllDemoTests()
            }
            #endif
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
        demoLogger.info("=== DEMO TEST SUITE START ===")

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

        // Test 5: ZK Proofs
        demoLogger.info("[TEST] ZK Proofs: starting...")
        let zkSteps = runZKProofDemo()
        let zkPass = zkSteps.allSatisfy { $0.status == .success }
        demoLogger.info("[TEST] ZK Proofs: \(zkPass ? "PASS" : "FAIL") (\(zkSteps.count) steps)")
        for step in zkSteps {
            demoLogger.info("  \(step.title): \(step.status == .success ? "OK" : step.status == .failure ? "FAIL" : "INFO")")
        }

        let allPass = hdPass && batchPass && lifecyclePass && agreePass && zkPass
        demoLogger.info("=== DEMO TEST SUITE \(allPass ? "ALL PASS" : "SOME FAILED") ===")
    }
}
#endif

#Preview {
    NavigationStack {
        DemoHubView()
    }
}
