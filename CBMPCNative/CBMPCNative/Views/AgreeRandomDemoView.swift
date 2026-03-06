import SwiftUI

/// Live AgreeRandom demo: 2-party secure random agreement using C++ commit-reveal protocol
struct AgreeRandomDemoView: View {
    @StateObject private var runner = DemoRunner()
    @State private var hasRun = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                DemoHeader(
                    title: "AgreeRandom",
                    description: "2-party commit-reveal shared randomness. Both parties contribute entropy.",
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
            runAgreeRandomDemo(runner: runner)
            runner.finish()
        }
    }
}

@discardableResult
func runAgreeRandomDemo(runner: DemoRunner? = nil) -> [DemoStep] {
    var steps: [DemoStep] = []
    let partyNames = ["party_0", "party_1"]

    // -- Step 1: 128-bit shared random --
    let t0 = CFAbsoluteTimeGetCurrent()
    do {
        let (rand0, rand1) = try LocalTwoPartyRunner.run(partyNames: partyNames) { job, role -> Data in
            var out = cbmpc_cmem_t()
            let result = cbmpc_agree_random(job.cJob, 128, &out)
            guard result == 0 else { throw CBMPCError.transportError("agree_random failed: \(result)") }
            defer { if let p = out.data { cbmpc_free(p) } }
            return Data(bytes: out.data!, count: Int(out.size))
        }
        let dt = CFAbsoluteTimeGetCurrent() - t0
        let match = (rand0 == rand1)
        let hex0 = hexString(rand0)
        steps.append(DemoStep(
            title: "1. AgreeRandom (128-bit)",
            status: (match && rand0.count == 16) ? .success : .failure,
            detail: "Party 0: \(hex0.prefix(32))...\nParty 1: \(hexString(rand1).prefix(32))...\nMatch: \(match ? "YES" : "NO") | Size: \(rand0.count) bytes (\(rand0.count * 8) bits)\nC++: agree_random() commit-reveal protocol",
            duration: dt
        ))
        runner?.appendStep(steps.last!)
    } catch {
        steps.append(DemoStep(title: "1. AgreeRandom 128-bit", status: .failure, detail: "\(error)", duration: CFAbsoluteTimeGetCurrent() - t0))
        runner?.appendStep(steps.last!)
        return steps
    }

    // -- Step 2: 256-bit shared random --
    let t1 = CFAbsoluteTimeGetCurrent()
    do {
        let (rand0, rand1) = try LocalTwoPartyRunner.run(partyNames: partyNames) { job, role -> Data in
            var out = cbmpc_cmem_t()
            let result = cbmpc_agree_random(job.cJob, 256, &out)
            guard result == 0 else { throw CBMPCError.transportError("agree_random failed: \(result)") }
            defer { if let p = out.data { cbmpc_free(p) } }
            return Data(bytes: out.data!, count: Int(out.size))
        }
        let dt = CFAbsoluteTimeGetCurrent() - t1
        let match = (rand0 == rand1)
        steps.append(DemoStep(
            title: "2. AgreeRandom (256-bit)",
            status: (match && rand0.count == 32) ? .success : .failure,
            detail: "Value: \(hexString(rand0))\nMatch: \(match ? "YES" : "NO") | Size: \(rand0.count) bytes (\(rand0.count * 8) bits)\nSuitable for AES-256 key agreement, session IDs",
            duration: dt
        ))
        runner?.appendStep(steps.last!)
    } catch {
        steps.append(DemoStep(title: "2. AgreeRandom 256-bit", status: .failure, detail: "\(error)", duration: CFAbsoluteTimeGetCurrent() - t1))
        runner?.appendStep(steps.last!)
        return steps
    }

    // -- Step 3: 10-bit shared random (small value) --
    let t2 = CFAbsoluteTimeGetCurrent()
    do {
        let (rand0, rand1) = try LocalTwoPartyRunner.run(partyNames: partyNames) { job, role -> Data in
            var out = cbmpc_cmem_t()
            let result = cbmpc_agree_random(job.cJob, 10, &out)
            guard result == 0 else { throw CBMPCError.transportError("agree_random failed: \(result)") }
            defer { if let p = out.data { cbmpc_free(p) } }
            return Data(bytes: out.data!, count: Int(out.size))
        }
        let dt = CFAbsoluteTimeGetCurrent() - t2
        let match = (rand0 == rand1)
        // Convert to integer for display
        var value: UInt16 = 0
        if rand0.count >= 2 {
            value = UInt16(rand0[0]) << 8 | UInt16(rand0[1])
            value &= 0x03FF // mask to 10 bits
        } else if rand0.count == 1 {
            value = UInt16(rand0[0]) & 0x03FF
        }
        steps.append(DemoStep(
            title: "3. AgreeRandom (10-bit)",
            status: match ? .success : .failure,
            detail: "Value: \(value) (0x\(String(format: "%04x", value))) | \(rand0.count) bytes raw\nMatch: \(match ? "YES" : "NO")\nUse: coin flip, leader election, parameter selection",
            duration: dt
        ))
        runner?.appendStep(steps.last!)
    } catch {
        steps.append(DemoStep(title: "3. AgreeRandom 10-bit", status: .failure, detail: "\(error)", duration: CFAbsoluteTimeGetCurrent() - t2))
        runner?.appendStep(steps.last!)
        return steps
    }

    // -- Step 4: Summary --
    let allPass = steps.allSatisfy { $0.status == .success }
    let totalTime = steps.reduce(0.0) { $0 + $1.duration }
    steps.append(DemoStep(
        title: "4. Cross-Platform Verification",
        status: allPass ? .success : .failure,
        detail: "3 rounds: 128-bit, 256-bit, 10-bit shared randomness\nAll parties derived identical values via commit-reveal\nC++: coinbase::mpc::agree_random()\nTotal: \(String(format: "%.0fms", totalTime * 1000))",
        duration: totalTime
    ))
    runner?.appendStep(steps.last!)

    return steps
}

#Preview {
    NavigationStack {
        AgreeRandomDemoView()
    }
}
