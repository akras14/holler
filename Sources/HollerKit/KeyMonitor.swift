import AppKit

/// Feeds keyboard events from every app to the dictation key.
///
/// Global monitors only see key events once Holler has Accessibility permission, and
/// ones added before it was granted stay deaf, so `start()` is called after the grant.
public final class KeyMonitor {
    let key: DictationKey
    private var monitors: [Any] = []

    public init(key: DictationKey) { self.key = key }

    public var isRunning: Bool { !monitors.isEmpty }

    public func start() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] in self?.handle($0) }) {
            monitors.append(global)
        }
        // Events while Holler's own menu is open.
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] in
            self?.handle($0)
            return $0
        }) {
            monitors.append(local)
        }
    }

    func handle(_ event: NSEvent) {
        switch event.type {
        case .flagsChanged:
            key.flagsChanged(keyCode: event.keyCode, flags: event.modifierFlags.rawValue, at: event.timestamp)
        case .keyDown:
            key.keyDown(keyCode: event.keyCode, at: event.timestamp)
        default:
            break
        }
    }
}
