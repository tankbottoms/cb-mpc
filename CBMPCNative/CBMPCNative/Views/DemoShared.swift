import SwiftUI
import CommonCrypto

// MARK: - Demo Step Model

struct DemoStep: Identifiable {
    let id = UUID()
    let title: String
    let status: StepStatus
    let detail: String
    let duration: TimeInterval

    enum StepStatus {
        case success, failure, info
    }
}

// MARK: - Demo Step Row (Live demos - green checkmarks)

struct DemoStepRow: View {
    let step: DemoStep

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Image(systemName: step.status == .success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(step.status == .success ? .green : .red)
                    .font(.system(size: 10))
                Text(step.title)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(String(format: "%.1fms", step.duration * 1000))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.orange)
            }
            Text(step.detail)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(4)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Conceptual Step Row (blue info icon, no timing)

struct ConceptualStepRow: View {
    let step: DemoStep

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                    .font(.system(size: 10))
                Text(step.title)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
            }
            Text(step.detail)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(6)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Demo Runner

/// Observable demo runner that publishes steps in real-time
class DemoRunner: ObservableObject {
    @Published var steps: [DemoStep] = []
    @Published var isRunning = false
    @Published var elapsedMs: Double = 0

    private var startTime: CFAbsoluteTime = 0
    private var timer: Timer?

    func appendStep(_ step: DemoStep) {
        DispatchQueue.main.async {
            self.steps.append(step)
        }
    }

    func start() {
        DispatchQueue.main.async {
            self.steps = []
            self.isRunning = true
            self.elapsedMs = 0
            self.startTime = CFAbsoluteTimeGetCurrent()
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.elapsedMs = (CFAbsoluteTimeGetCurrent() - self.startTime) * 1000
            }
        }
    }

    func finish() {
        DispatchQueue.main.async {
            self.isRunning = false
            self.timer?.invalidate()
            self.timer = nil
            // Align top timer with sum of step durations
            let totalStepMs = self.steps.reduce(0.0) { $0 + $1.duration } * 1000
            if totalStepMs > 0 {
                self.elapsedMs = totalStepMs
            }
        }
    }
}

// MARK: - Demo Header

struct DemoHeader: View {
    let title: String
    let description: String
    let isLive: Bool
    var isRunning: Bool = false
    var elapsedMs: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(isLive ? "Live" : "Conceptual")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isLive ? Color.green.opacity(0.15) : Color.blue.opacity(0.15))
                    .foregroundColor(isLive ? .green : .blue)
                    .clipShape(Capsule())
            }
            Text(description)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            if isLive && (isRunning || elapsedMs > 0) {
                HStack(spacing: 4) {
                    if isRunning {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                    }
                    Text(String(format: "%.0fms", elapsedMs))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.orange)
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Helpers

func sha256(_ data: Data) -> Data {
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    data.withUnsafeBytes { buffer in
        _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
    }
    return Data(hash)
}

func hexString(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
}
