import AppKit
@testable import HollerKit

@MainActor
func indicatorChecks(_ t: Checker) {
    t.group("Indicator") {
        let indicator = Indicator()
        let panel = indicator.panel
        t.expect(panel.isVisible, false, "hidden at launch")
        indicator.update(.recording)
        t.expect(panel.isVisible, true, "shown while recording")
        indicator.update(.transcribing)
        t.expect(panel.isVisible, true, "and while transcribing")
        indicator.update(.ready)
        t.expect(panel.isVisible, false, "hidden once the text is pasted")

        // The paste goes to whatever app has focus, so the pill must never take it.
        t.expect(panel.canBecomeKey, false, "never takes keyboard focus")
        t.expect(panel.styleMask.contains(.nonactivatingPanel), true, "doesn't activate Holler")
        t.expect(panel.ignoresMouseEvents, true, "clicks pass through")
        t.expect(panel.collectionBehavior.contains(.canJoinAllSpaces), true, "on every Space")
        t.expect(panel.collectionBehavior.contains(.fullScreenAuxiliary), true, "and over full-screen apps")

        indicator.update(.recording)
        // On the screen you're working on: the one with the pointer.
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }!.visibleFrame
        t.expect(panel.frame.midX, screen.midX, "centered")
        t.expect(panel.frame.minY, screen.minY + 50, "near the bottom of the screen")
        indicator.update(.ready)
    }
}

@MainActor
func menuChecks(_ t: Checker) {
    func titles(_ menu: NSMenu) -> [String] { menu.items.map { $0.isSeparatorItem ? "—" : $0.title } }
    func item(_ menu: NSMenu, _ title: String) -> NSMenuItem? { menu.items.first { $0.title == title } }

    t.group("Menu") {
        let board = NSPasteboard(name: NSPasteboard.Name("holler-check-\(UUID().uuidString)"))
        let menu = StatusMenu(pasteboard: board)
        var model = MenuModel()
        model.state = .ready
        model.recent = ["Short one.", String(repeating: "word ", count: 30) + "end."]
        model.microphones = [.init(uid: "mic-a", name: "MacBook Pro Microphone"), .init(uid: "mic-b", name: "AirPods")]
        menu.model = model

        t.expect(titles(menu.menu), [
            "Hold Right Option to dictate", "—",
            "Recent", "Short one.", String(repeating: "word ", count: 11).trimmingCharacters(in: .whitespaces) + "…", "—",
            "Microphone", "Launch at Login", "—",
            "Quit Holler",
        ])
        t.expect(menu.menu.items[0].isEnabled, false, "the status line is just a label")
        t.expect(item(menu.menu, "Quit Holler")?.keyEquivalent, "q")

        let long = menu.menu.items[4]
        t.expect(long.toolTip, model.recent[1], "the full text is in the tooltip")
        menu.menu.performActionForItem(at: 4)
        t.expect(board.string(forType: .string), model.recent[1], "clicking a recent transcript copies all of it")
    }

    t.group("Menu: microphone") {
        let menu = StatusMenu(pasteboard: .general)
        var chosen: [String?] = []
        menu.onSelectMicrophone = { chosen.append($0) }
        var model = MenuModel()
        model.microphones = [.init(uid: "mic-a", name: "MacBook Pro Microphone"), .init(uid: "mic-b", name: "AirPods")]
        menu.model = model

        let sub = item(menu.menu, "Microphone")!.submenu!
        t.expect(titles(sub), ["System Default", "—", "MacBook Pro Microphone", "AirPods"])
        t.expect(sub.items[0].state, .on, "follows the system default unless you pick one")
        sub.performActionForItem(at: 3)
        t.expect(chosen, ["mic-b"])
        model.selectedMicrophone = "mic-b"
        menu.model = model
        let updated = item(menu.menu, "Microphone")!.submenu!
        t.expect(updated.items.map(\.state), [.off, .off, .off, .on], "the chosen one is checked")
        updated.performActionForItem(at: 0)
        t.expect(chosen, ["mic-b", nil], "System Default clears the choice")

        model.selectedMicrophone = "unplugged"
        menu.model = model
        t.expect(titles(item(menu.menu, "Microphone")!.submenu!).last, "unplugged (not connected)",
                 "an unplugged choice stays visible instead of silently switching")
    }

    t.group("Menu: states") {
        let menu = StatusMenu(pasteboard: .general)
        var model = MenuModel()
        model.state = .loading
        menu.model = model
        t.expect(menu.menu.items[0].title, "Loading speech model…")
        model.downloading = true
        menu.model = model
        t.expect(menu.menu.items[0].title, "Downloading speech model (450 MB)…")
        model.state = .ready
        model.error = "Couldn't start the microphone"
        menu.model = model
        t.expect(menu.menu.items[0].title, "Couldn't start the microphone", "errors replace the status line")
        model.error = nil
        menu.model = model
        t.expect(item(menu.menu, "No transcripts yet")?.isEnabled, false)
    }

    t.group("Menu: permissions") {
        let menu = StatusMenu(pasteboard: .general)
        var opened: [Permission] = []
        menu.onOpenPermission = { opened.append($0) }
        var model = MenuModel()
        model.state = .ready
        model.missing = [.accessibility, .microphone]
        menu.model = model
        t.expect(Array(titles(menu.menu).prefix(4)), [
            "Holler needs two permissions", "Allow Accessibility (to paste)…", "Allow Microphone…", "—",
        ])
        menu.menu.performActionForItem(at: 1)
        menu.menu.performActionForItem(at: 2)
        t.expect(opened, [.accessibility, .microphone], "each one opens its pane in System Settings")
    }
}
