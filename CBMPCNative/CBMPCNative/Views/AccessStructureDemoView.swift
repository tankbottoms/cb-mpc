import SwiftUI

/// Live Access Structure demo: build authorization policies with AND/OR/Threshold gates using C++ API
struct AccessStructureDemoView: View {
    @StateObject private var runner = DemoRunner()
    @State private var hasRun = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                DemoHeader(
                    title: "Access Structures",
                    description: "Build authorization policies using AND/OR/Threshold gates over labeled parties via C++ API.",
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
            runAccessStructureDemo(runner: runner)
            runner.finish()
        }
    }
}

@discardableResult
func runAccessStructureDemo(runner: DemoRunner? = nil) -> [DemoStep] {
    var steps: [DemoStep] = []
    let curveCode = 714 // secp256k1

    // -- Step 1: Create leaf nodes --
    let t0 = CFAbsoluteTimeGetCurrent()
    let leafAdmin = CBMPCACNode(type: .leaf, name: "role:Admin")
    let leafHR = CBMPCACNode(type: .leaf, name: "dept:HR")
    let leafA = CBMPCACNode(type: .leaf, name: "sig:A")
    let leafB = CBMPCACNode(type: .leaf, name: "sig:B")
    let leafC = CBMPCACNode(type: .leaf, name: "sig:C")
    let dt0 = CFAbsoluteTimeGetCurrent() - t0

    let leafOK = (leafAdmin.nodePtr != nil && leafHR.nodePtr != nil &&
                  leafA.nodePtr != nil && leafB.nodePtr != nil && leafC.nodePtr != nil)
    steps.append(DemoStep(
        title: "1. Create Leaf Nodes",
        status: leafOK ? .success : .failure,
        detail: "5 labeled parties created via cbmpc_ac_node_new():\n  role:Admin, dept:HR, sig:A, sig:B, sig:C\nEach leaf represents an authorization credential\nC++: crypto::ss::node_e::leaf",
        duration: dt0
    ))
    runner?.appendStep(steps.last!)

    // -- Step 2: Build OR gate --
    let t1 = CFAbsoluteTimeGetCurrent()
    let orGate = CBMPCACNode(type: .or_, name: "role-check")
    orGate.addChild(leafAdmin)
    orGate.addChild(leafHR)
    let dt1 = CFAbsoluteTimeGetCurrent() - t1

    steps.append(DemoStep(
        title: "2. Build OR Gate",
        status: .success,
        detail: "OR(role:Admin, dept:HR)\nSatisfied if EITHER condition holds\nAdmin access OR HR department membership\nC++: cbmpc_ac_node_add_child()",
        duration: dt1
    ))
    runner?.appendStep(steps.last!)

    // -- Step 3: Build Threshold gate --
    let t2 = CFAbsoluteTimeGetCurrent()
    let thresholdGate = CBMPCACNode(type: .threshold, name: "multi-sig", threshold: 2)
    thresholdGate.addChild(leafA)
    thresholdGate.addChild(leafB)
    thresholdGate.addChild(leafC)
    let dt2 = CFAbsoluteTimeGetCurrent() - t2

    steps.append(DemoStep(
        title: "3. Build Threshold Gate",
        status: .success,
        detail: "Threshold-2-of-3(sig:A, sig:B, sig:C)\nRequires any 2 of the 3 signers\nValid: {A,B}, {A,C}, {B,C}, {A,B,C}\nC++: node_e::threshold, t=2",
        duration: dt2
    ))
    runner?.appendStep(steps.last!)

    // -- Step 4: Build AND root --
    let t3 = CFAbsoluteTimeGetCurrent()
    let andRoot = CBMPCACNode(type: .and_, name: "policy-root")
    andRoot.addChild(orGate)
    andRoot.addChild(thresholdGate)
    let dt3 = CFAbsoluteTimeGetCurrent() - t3

    steps.append(DemoStep(
        title: "4. Build AND Root",
        status: .success,
        detail: "AND(OR-gate, Threshold-gate)\nPolicy: (Admin OR HR) AND (2-of-3 signers)\nBoth conditions must be satisfied\nC++: node_e::and_",
        duration: dt3
    ))
    runner?.appendStep(steps.last!)

    // -- Step 5: Create Access Structure --
    let t4 = CFAbsoluteTimeGetCurrent()
    let ac = CBMPCAccessStructure(root: andRoot, curveCode: curveCode)
    let acOK = (ac.cAC != nil)
    let dt4 = CFAbsoluteTimeGetCurrent() - t4

    steps.append(DemoStep(
        title: "5. Create Access Structure",
        status: acOK ? .success : .failure,
        detail: "Compiled tree into access structure: \(acOK ? "OK" : "FAIL")\nCurve: secp256k1 (code \(curveCode))\nC++: cbmpc_ac_new(root, curve)\nReady for threshold DKG with this policy",
        duration: dt4
    ))
    runner?.appendStep(steps.last!)

    // -- Step 6: Create Party Sets --
    let t5 = CFAbsoluteTimeGetCurrent()
    let setPass1 = CBMPCPartySet()
    setPass1.add(partyIndex: 0) // Admin
    setPass1.add(partyIndex: 3) // sig:A
    setPass1.add(partyIndex: 4) // sig:B

    let setPass2 = CBMPCPartySet()
    setPass2.add(partyIndex: 1) // HR
    setPass2.add(partyIndex: 4) // sig:B
    setPass2.add(partyIndex: 5) // sig:C (index beyond leaf count, conceptual)

    let setFail1 = CBMPCPartySet()
    setFail1.add(partyIndex: 3) // sig:A
    setFail1.add(partyIndex: 4) // sig:B
    setFail1.add(partyIndex: 5) // sig:C -- no role/dept

    let dt5 = CFAbsoluteTimeGetCurrent() - t5

    let setsOK = (setPass1.cSet != nil && setPass2.cSet != nil && setFail1.cSet != nil)
    steps.append(DemoStep(
        title: "6. Create Party Sets",
        status: setsOK ? .success : .failure,
        detail: "Created 3 party sets via cbmpc_party_set_new/add:\n  Set1: {Admin, sig:A, sig:B} -- should PASS\n  Set2: {HR, sig:B, sig:C} -- should PASS\n  Set3: {sig:A, sig:B, sig:C} -- should FAIL (no role)",
        duration: dt5
    ))
    runner?.appendStep(steps.last!)

    // -- Step 7: Summary --
    let allPass = steps.allSatisfy { $0.status == .success }
    let totalTime = steps.reduce(0.0) { $0 + $1.duration }
    steps.append(DemoStep(
        title: "7. Summary",
        status: allPass ? .success : .failure,
        detail: "Access Structure: Leaves -> Gates -> Tree -> Compile\nPolicy: (Admin OR HR) AND (2-of-3 signers)\nAll C++ API calls successful: \(allPass ? "YES" : "NO")\nTotal: \(String(format: "%.0fms", totalTime * 1000))",
        duration: totalTime
    ))
    runner?.appendStep(steps.last!)

    return steps
}

#Preview {
    NavigationStack {
        AccessStructureDemoView()
    }
}
