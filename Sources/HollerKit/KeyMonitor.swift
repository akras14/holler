import AppKit

/// Feeds keyboard events from every app to push to talk.
///
/// Global monitors only see key events once Holler has Accessibility permission, and
/// ones added before it was granted stay deaf, so `start()` is called after the grant.
public final class KeyMonitor {
    let pushToTalk: PushToTalk
    private var monitors: [Any] = []

    public init(pushToTalk: PushToTalk) { self.pushToTalk = pushToTalk }

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
            pushToTalk.flagsChanged(keyCode: event.keyCode, flags: event.modifierFlags.rawValue, at: event.timestamp)
        case .keyDown:
            pushToTalk.keyDown(at: event.timestamp)
        default:
            break
        }
    }
}
