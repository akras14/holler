import AppKit

public enum Permission: Equatable { case accessibility, microphone }

/// Everything the menu shows.
public struct MenuModel {
    public var state: Dictation.State = .loading
    public var downloading = false
    public var error: String?
    public var missing: [Permission] = []
    public var recent: [String] = []
    public var microphones: [Microphones.Device] = []
    public var selectedMicrophone: String?
    public var launchAtLogin = false
    public init() {}
}

/// The menu bar icon's menu, rebuilt whenever its model changes.
public final class StatusMenu: NSObject {
    public let menu = NSMenu()
    public var model = MenuModel() { didSet { rebuild() } }
    public var onSelectMicrophone: (String?) -> Void = { _ in }
    public var onOpenPermission: (Permission) -> Void = { _ in }
    public var onToggleLaunchAtLogin: () -> Void = {}
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard) {
        self.pasteboard = pasteboard
        super.init()
        menu.autoenablesItems = false
        rebuild()
    }

    private func rebuild() {
        menu.removeAllItems()

        if !model.missing.isEmpty {
            menu.addItem(label(model.missing.count == 1 ? "Holler needs a permission" : "Holler needs two permissions"))
            for permission in model.missing {
                let title = permission == .accessibility ? "Allow Accessibility (to paste)…" : "Allow Microphone…"
                let item = action(title, #selector(openPermission(_:)))
                item.representedObject = permission == .accessibility ? "accessibility" : "microphone"
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        menu.addItem(label(statusLine))
        menu.addItem(.separator())

        menu.addItem(.sectionHeader(title: "Recent"))
        if model.recent.isEmpty {
            menu.addItem(label("No transcripts yet"))
        }
        for text in model.recent {
            let item = action(Self.shorten(text), #selector(copyRecent(_:)))
            item.representedObject = text
            item.toolTip = text
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let microphone = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
        microphone.submenu = microphoneMenu()
        menu.addItem(microphone)
        let login = action("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = model.launchAtLogin ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Holler", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private var statusLine: String {
        if let error = model.error { return error }
        switch model.state {
        case .loading: return model.downloading ? "Downloading speech model (450 MB)…" : "Loading speech model…"
        case .ready: return "Tap Right Option to dictate"
        case .recording: return "Listening: tap Right Option to stop, Esc to cancel"
        case .transcribing: return "Transcribing…"
        }
    }

    private func microphoneMenu() -> NSMenu {
        let sub = NSMenu()
        sub.autoenablesItems = false
        let systemDefault = action("System Default", #selector(selectMicrophone(_:)))
        systemDefault.state = model.selectedMicrophone == nil ? .on : .off
        sub.addItem(systemDefault)
        sub.addItem(.separator())
        var devices = model.microphones
        if let chosen = model.selectedMicrophone, !devices.contains(where: { $0.uid == chosen }) {
            devices.append(.init(uid: chosen, name: "\(chosen) (not connected)"))
        }
        for device in devices {
            let item = action(device.name, #selector(selectMicrophone(_:)))
            item.representedObject = device.uid
            item.state = device.uid == model.selectedMicrophone ? .on : .off
            sub.addItem(item)
        }
        return sub
    }

    /// At most 55 characters, broken between words.
    static func shorten(_ text: String) -> String {
        guard text.count > 55 else { return text }
        var cut = String(text.prefix(55))
        if text[text.index(text.startIndex, offsetBy: 55)] != " ", let space = cut.lastIndex(of: " ") {
            cut = String(cut[..<space])
        }
        return cut.trimmingCharacters(in: .whitespaces) + "…"
    }

    private func label(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func copyRecent(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    @objc private func selectMicrophone(_ sender: NSMenuItem) {
        onSelectMicrophone(sender.representedObject as? String)
    }

    @objc private func openPermission(_ sender: NSMenuItem) {
        onOpenPermission(sender.representedObject as? String == "accessibility" ? .accessibility : .microphone)
    }

    @objc private func toggleLaunchAtLogin() { onToggleLaunchAtLogin() }
}
