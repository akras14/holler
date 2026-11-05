import AppKit

/// Turns Right Option key events into start, finish and cancel.
///
/// Recording starts on key-down so the first word isn't clipped. A tap shorter than
/// `minimumHold`, or a hold that turns into a shortcut (another modifier or any key
/// pressed meanwhile, as in ⌥-letter for special characters), is cancelled rather than
/// transcribed. Right Option pressed while another modifier is already down is a shortcut
/// too, and is ignored.
public final class PushToTalk {
    public enum Action: Equatable { case start, finish, cancel }

    public var onAction: (Action) -> Void = { _ in }
    public var minimumHold: TimeInterval = 0.3
    private var pressedAt: TimeInterval?

    static let rightOptionKeyCode: UInt16 = 61
    /// NX_DEVICERALTKEYMASK: set only while the right-hand Option key is down.
    static let rightOptionBit: UInt = 0x40
    /// Any modifier other than Right Option (Left Option is NX_DEVICELALTKEYMASK).
    static let otherModifiers: UInt = 0x20 | NSEvent.ModifierFlags([.command, .control, .shift, .function]).rawValue

    public init() {}

    public func flagsChanged(keyCode: UInt16, flags: UInt, at time: TimeInterval) {
        let rightOptionDown = flags & Self.rightOptionBit != 0
        let othersDown = flags & Self.otherModifiers != 0

        if let start = pressedAt {
            if othersDown {
                pressedAt = nil
                onAction(.cancel)
            } else if !rightOptionDown {
                pressedAt = nil
                onAction(time - start < minimumHold ? .cancel : .finish)
            }
        } else if keyCode == Self.rightOptionKeyCode, rightOptionDown, !othersDown {
            pressedAt = time
            onAction(.start)
        }
    }

    public func keyDown(at time: TimeInterval) {
        guard pressedAt != nil else { return }
        pressedAt = nil
        onAction(.cancel)
    }
}
