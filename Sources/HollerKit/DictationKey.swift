import AppKit

/// Turns Right Option taps into start, finish and cancel: tap once to start recording,
/// tap again to stop, Esc to throw the recording away.
///
/// Recording starts on the first key-down so the first word isn't clipped. Until that
/// key comes back up, the press might still be a shortcut (⌥-letter for special
/// characters, ⌘⌥…): another key or modifier then cancels it. Once released, typing
/// doesn't stop the recording; only Right Option or Esc do. Right Option pressed while
/// another modifier is already down is a shortcut, and is ignored.
public final class DictationKey {
    public enum Action: Equatable { case start, finish, cancel }

    public var onAction: (Action) -> Void = { _ in }
    /// Recordings shorter than this, such as an accidental double tap, are cancelled.
    public var minimumLength: TimeInterval = 0.3
    /// Each Right Option event and each key that changes something. Other typing isn't logged.
    public var log: (String) -> Void = Log.writer("key")

    private enum Phase {
        case idle
        /// The starting press, still held: could turn out to be a shortcut.
        case starting(since: TimeInterval)
        case recording(since: TimeInterval)
        /// The stopping press, still held: its release is ignored.
        case stopping

        var name: String {
            switch self {
            case .idle: "idle"
            case .starting: "starting"
            case .recording: "recording"
            case .stopping: "stopping"
            }
        }
    }
    private var phase = Phase.idle

    static let rightOptionKeyCode: UInt16 = 61
    static let escapeKeyCode: UInt16 = 53
    /// NX_DEVICERALTKEYMASK: set only while the right-hand Option key is down.
    static let rightOptionBit: UInt = 0x40
    /// Any modifier other than Right Option (Left Option is NX_DEVICELALTKEYMASK).
    static let otherModifiers: UInt = 0x20 | NSEvent.ModifierFlags([.command, .control, .shift, .function]).rawValue

    public init() {}

    public func flagsChanged(keyCode: UInt16, flags: UInt, at time: TimeInterval) {
        let rightOptionDown = flags & Self.rightOptionBit != 0
        let othersDown = flags & Self.otherModifiers != 0
        let rightOptionPressed = keyCode == Self.rightOptionKeyCode && rightOptionDown && !othersDown
        let before = phase
        var action: Action?
        var length = ""

        switch phase {
        case .idle:
            if rightOptionPressed {
                phase = .starting(since: time)
                action = .start
            }
        case .starting(let since):
            if othersDown {
                phase = .idle
                action = .cancel
            } else if !rightOptionDown {
                phase = .recording(since: since)
            }
        case .recording(let since):
            if rightOptionPressed {
                phase = .stopping
                action = time - since < minimumLength ? .cancel : .finish
                length = String(format: " after %.2f s", time - since)
            }
        case .stopping:
            if !rightOptionDown {
                phase = .idle
            } else if rightOptionPressed {
                // The release went missing (secure input can hide it): this is a new start.
                phase = .starting(since: time)
                action = .start
            }
        }

        // Modifiers used while idle are ordinary typing: leave them out.
        if keyCode == Self.rightOptionKeyCode || before.name != "idle" || phase.name != "idle" {
            log("key \(keyCode) flags 0x\(String(flags, radix: 16)): \(before.name) → \(phase.name)"
                + (action.map { ", \($0)\(length)" } ?? ""))
        }
        if let action { onAction(action) }
    }

    public func keyDown(keyCode: UInt16, at time: TimeInterval) {
        let before = phase
        switch phase {
        case .starting,
             .recording where keyCode == Self.escapeKeyCode:
            phase = .idle
            // Only keys that cancel are logged, so the log never holds what was typed.
            log("key down \(keyCode): \(before.name) → idle, cancel")
            onAction(.cancel)
        default:
            break
        }
    }
}
