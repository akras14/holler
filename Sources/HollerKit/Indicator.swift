import AppKit

/// The floating pill shown while recording (bars follow your voice) and transcribing
/// (bars ripple). It never takes focus, so the paste lands in the app you were using.
public final class Indicator {
    public let panel: NSPanel
    private let bars = BarsView(frame: NSRect(x: 0, y: 0, width: 88, height: 32))
    private var timer: Timer?
    static let bottomOffset: CGFloat = 50

    public init() {
        panel = NSPanel(contentRect: bars.frame, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = bars
    }

    public func update(_ state: Dictation.State) {
        switch state {
        case .recording:
            bars.mode = .listening
            bars.reset()
            show()
        case .transcribing:
            bars.mode = .working
            show()
        case .loading, .ready:
            timer?.invalidate()
            timer = nil
            panel.orderOut(nil)
        }
    }

    public func level(_ value: Float) { bars.push(CGFloat(value)) }

    private func show() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let area = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: area.midX - panel.frame.width / 2, y: area.minY + Self.bottomOffset))
        panel.orderFrontRegardless()
        if timer == nil {
            let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [bars] _ in bars.tick() }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }
}

/// Bars on a dark pill: the recent input levels, newest on the right.
final class BarsView: NSView {
    enum Mode { case listening, working }
    var mode = Mode.listening
    private static let count = 9
    private var targets = [CGFloat](repeating: 0, count: count)
    private var shown = [CGFloat](repeating: 0, count: count)
    private var phase: CGFloat = 0

    func reset() {
        targets = .init(repeating: 0, count: Self.count)
        shown = targets
    }

    func push(_ level: CGFloat) {
        targets.removeFirst()
        targets.append(level)
    }

    /// Eases the bars toward their targets; called 30 times a second while visible.
    func tick() {
        phase += 0.25
        for i in 0..<Self.count {
            let target: CGFloat = mode == .listening
                ? targets[i]
                : 0.25 + 0.2 * sin(phase - CGFloat(i) * 0.7)
            shown[i] += (target - shown[i]) * 0.35
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let pill = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor(white: 0.08, alpha: 0.9).setFill()
        pill.fill()
        NSColor(white: 1, alpha: 0.15).setStroke()
        pill.lineWidth = 1
        pill.stroke()

        let width: CGFloat = 3, gap: CGFloat = 3.5
        let total = CGFloat(Self.count) * width + CGFloat(Self.count - 1) * gap
        let maxHeight = bounds.height - 14
        NSColor.white.setFill()
        for i in 0..<Self.count {
            let height = max(width, maxHeight * min(shown[i], 1))
            let x = bounds.midX - total / 2 + CGFloat(i) * (width + gap)
            let bar = NSRect(x: x, y: bounds.midY - height / 2, width: width, height: height)
            NSBezierPath(roundedRect: bar, xRadius: width / 2, yRadius: width / 2).fill()
        }
    }
}
