import SwiftUI

/// Conceptual Access Structure demo: define authorization policies with AND/OR/Threshold gates
struct AccessStructureDemoView: View {
    @State private var steps: [DemoStep] = []
    @State private var hasViewed = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                DemoHeader(
                    title: "Access Structures",
                    description: "Define authorization policies using AND/OR/Threshold gates over labeled parties.",
                    isLive: false
                )
                if !hasViewed {
                    Button(action: showSteps) {
                        HStack(spacing: 4) {
                            Image(systemName: "eye.fill").font(.system(size: 10))
                            Text("View Demo Steps").font(.system(size: 10))
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
                ForEach(steps) { step in
                    ConceptualStepRow(step: step)
                }
            }
            .listStyle(.plain)
        }
        .onAppear {
            if !hasViewed { showSteps() }
        }
    }

    private func showSteps() {
        hasViewed = true
        steps = [
            DemoStep(
                title: "1. Define Leaves",
                status: .info,
                detail: "5 labeled parties (leaf nodes):\n  role:Admin -- administrative access\n  dept:HR -- department-level access\n  sig:A, sig:B, sig:C -- individual signers\nEach leaf represents an authorization credential",
                duration: 0
            ),
            DemoStep(
                title: "2. Build OR Gate",
                status: .info,
                detail: "OR(role:Admin, dept:HR)\nSatisfied if EITHER condition holds\nAdmin access OR HR department membership\nProvides flexible role-based authorization",
                duration: 0
            ),
            DemoStep(
                title: "3. Build Threshold Gate",
                status: .info,
                detail: "Threshold-2-of-3(sig:A, sig:B, sig:C)\nRequires any 2 of the 3 signers\nValid combinations: {A,B}, {A,C}, {B,C}, {A,B,C}\nFault-tolerant: survives 1 signer being unavailable",
                duration: 0
            ),
            DemoStep(
                title: "4. Build AND Root",
                status: .info,
                detail: "AND(OR-gate, Threshold-gate)\nFull policy: (Admin OR HR) AND (2-of-3 signers)\nBoth conditions must be satisfied simultaneously\nCombines role-based and multi-sig authorization",
                duration: 0
            ),
            DemoStep(
                title: "5. Evaluate Quorums",
                status: .info,
                detail: "PASS: {Admin, sig:A, sig:B} -- admin + 2 signers\nPASS: {HR, sig:B, sig:C} -- HR + 2 signers\nPASS: {Admin, sig:A, sig:B, sig:C} -- admin + all signers\nFAIL: {sig:A, sig:B, sig:C} -- no role/dept\nFAIL: {Admin, sig:A} -- only 1 signer\nFAIL: {HR} -- no signers",
                duration: 0
            ),
        ]
    }
}

#Preview {
    NavigationStack {
        AccessStructureDemoView()
    }
}
