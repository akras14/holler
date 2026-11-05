import AppKit

/// Types text into the frontmost app by pasting it, then puts the clipboard back.
public final class Paster {
    let pasteboard: NSPasteboard
    /// How long the frontmost app gets to read the clipboard before it's restored.
    public var restoreDelay: TimeInterval = 0.5
    /// Presses ⌘V. Replaced in checks, which can't post events to other apps.
    public var sendPaste: () -> Void = Paster.pressCommandV

    /// Clipboard managers that follow nspasteboard.org skip items with this type.
    static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    public init(pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }

    public func paste(_ text: String) {
        let saved = snapshot()
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        pasteboard.setData(Data(), forType: Self.transient)
        let ours = pasteboard.changeCount
        sendPaste()

        DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) { [pasteboard] in
            // Something was copied meanwhile: leave it.
            guard pasteboard.changeCount == ours else { return }
            pasteboard.clearContents()
            if !saved.isEmpty { pasteboard.writeObjects(saved) }
        }
    }

    /// Copies of every item on the clipboard, with all their types.
    private func snapshot() -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    /// Posts ⌘V to whichever app has keyboard focus. Needs Accessibility permission.
    public static func pressCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: down)
            // Only ⌘, so a modifier still held down can't turn it into another shortcut.
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}
