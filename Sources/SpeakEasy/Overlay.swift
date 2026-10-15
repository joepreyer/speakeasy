import AppKit
import SwiftUI

enum OverlayState: Equatable {
    case listening
    case processing
    case info(String)
    case error(String)
}

/// A small floating pill at the bottom-center of the screen showing the dictation
/// state. Never takes focus, ignores the mouse.
final class OverlayController {
    /// Polled while listening to drive the waveform.
    var levelProvider: (() -> Double)?

    private let panel: NSPanel
    private let model = OverlayModel()
    private var hideWorkItem: DispatchWorkItem?
    private var levelTimer: Timer?
    private var visibility = 0

    private(set) var isShowingActivity = false

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: OverlayView(model: model))
    }

    func show(_ state: OverlayState) {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        let wasVisible = panel.isVisible
        withAnimation(wasVisible ? .spring(response: 0.3, dampingFraction: 0.85) : nil) {
            model.state = state
        }
        switch state {
        case .listening:
            isShowingActivity = true
            startLevelUpdates()
        case .processing:
            isShowingActivity = true
            stopLevelUpdates()
        case .info, .error:
            isShowingActivity = false
            stopLevelUpdates()
        }
        position()
        visibility += 1
        if !wasVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        isShowingActivity = false
        stopLevelUpdates()
        guard panel.isVisible else { return }
        let token = visibility
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // Skip if the pill was shown again while fading out.
            guard let self, self.visibility == token else { return }
            self.panel.orderOut(nil)
        })
    }

    /// Shows a message briefly, then hides.
    func flash(_ state: OverlayState) {
        show(state)
        let item = DispatchWorkItem { [weak self] in
            self?.hideWorkItem = nil
            self?.hide()
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: item)
    }

    private func startLevelUpdates() {
        model.level = 0
        guard levelTimer == nil else { return }
        levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self, let target = self.levelProvider?() else { return }
            // Rise quickly, fall slowly, so the bars feel responsive but not jittery.
            let smoothing = target > self.model.level ? 0.55 : 0.18
            self.model.level += (target - self.model.level) * smoothing
        }
    }

    private func stopLevelUpdates() {
        levelTimer?.invalidate()
        levelTimer = nil
    }

    private func position() {
        guard let screen = NSScreen.main else { return }
        let size = panel.frame.size
        let x = screen.frame.midX - size.width / 2
        let y = screen.visibleFrame.minY + 20
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

final class OverlayModel: ObservableObject {
    @Published var state: OverlayState = .listening
    @Published var level: Double = 0
}

struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        content
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(Capsule().fill(Color.black.opacity(0.92)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.55), lineWidth: 1.5))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .listening:
            Waveform(level: model.level)
        case .processing:
            ProcessingWave()
        case .info(let message):
            Message(icon: "sparkles", text: message)
        case .error(let message):
            Message(icon: "exclamationmark.triangle.fill", text: message)
        }
    }
}

private enum Bars {
    static let count = 11
    static let width: CGFloat = 2.5
    static let spacing: CGFloat = 2.5
    static let minHeight: CGFloat = 3
    static let maxHeight: CGFloat = 18
    /// Taller in the middle, tapering toward the edges.
    static let envelope: [Double] = (0..<count).map { index in
        let x = Double(index) / Double(count - 1) * 2 - 1
        return 0.35 + 0.65 * exp(-x * x * 2.2)
    }
}

/// Bars that follow the microphone level, with a little per-bar motion so it feels alive.
private struct Waveform: View {
    let level: Double

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: Bars.spacing) {
                ForEach(0..<Bars.count, id: \.self) { index in
                    let wobble = 0.7 + 0.3 * sin(t * 11 + Double(index) * 1.9)
                    let amount = min(1, level * 1.4) * Bars.envelope[index] * wobble
                    Capsule()
                        .fill(Color.white)
                        .frame(width: Bars.width,
                               height: Bars.minHeight + (Bars.maxHeight - Bars.minHeight) * amount)
                }
            }
            .frame(height: Bars.maxHeight)
        }
    }
}

/// The same bars at rest with a soft pulse travelling across them while transcribing.
private struct ProcessingWave: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: Bars.spacing) {
                ForEach(0..<Bars.count, id: \.self) { index in
                    let phase = t * 2.4 - Double(index) / Double(Bars.count) * 2.2
                    let pulse = pow(max(0, sin(phase * .pi)), 6)
                    Capsule()
                        .fill(Color.white.opacity(0.45 + 0.55 * pulse))
                        .frame(width: Bars.width, height: Bars.minHeight + 7 * pulse)
                }
            }
            .frame(height: Bars.maxHeight)
        }
    }
}

private struct Message: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 2)
    }
}
