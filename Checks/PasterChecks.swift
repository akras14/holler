import AppKit
@testable import HollerKit

@MainActor
func pasterChecks(_ t: Checker) {
    func make() -> (Paster, NSPasteboard, () -> [String?]) {
        let board = NSPasteboard(name: NSPasteboard.Name("holler-check-\(UUID().uuidString)"))
        let paster = Paster(pasteboard: board)
        paster.restoreDelay = 0.05
        var seen: [String?] = []
        paster.sendPaste = { seen.append(board.string(forType: .string)) }
        return (paster, board, { seen })
    }

    t.group("Paste") {
        let (paster, board, seen) = make()
        board.clearContents()
        board.setString("what I copied", forType: .string)
        paster.paste("hello there")
        t.expect(seen(), ["hello there"], "the text is on the clipboard when ⌘V is sent")
        t.expect(waitUntil { board.string(forType: .string) == "what I copied" }, true,
                 "then the clipboard gets back what was there before")
        board.releaseGlobally()
    }

    t.group("Paste: other clipboard contents") {
        let (paster, board, _) = make()
        let custom = NSPasteboard.PasteboardType("com.example.custom")
        let item = NSPasteboardItem()
        item.setData(Data([1, 2, 3]), forType: custom)
        item.setString("label", forType: .string)
        board.clearContents()
        board.writeObjects([item])
        paster.paste("hello")
        t.expect(waitUntil { board.data(forType: custom) == Data([1, 2, 3]) }, true, "restores every type, not just text")
        t.expect(board.string(forType: .string), "label")
        board.releaseGlobally()
    }

    t.group("Paste: empty clipboard") {
        let (paster, board, _) = make()
        board.clearContents()
        let before = board.changeCount
        paster.paste("hello")
        t.expect(waitUntil { board.changeCount > before + 1 }, true, "the clipboard is restored")
        t.expect(board.string(forType: .string), nil, "to empty")
        board.releaseGlobally()
    }

    t.group("Paste: copying meanwhile") {
        let (paster, board, _) = make()
        paster.restoreDelay = 0.3
        board.clearContents()
        board.setString("old", forType: .string)
        paster.paste("hello")
        board.clearContents()
        board.setString("copied just now", forType: .string)
        t.expect(holds(for: 0.5) { board.string(forType: .string) == "copied just now" }, true,
                 "a copy made before the restore isn't overwritten")
        board.releaseGlobally()
    }

    t.group("Paste: clipboard managers") {
        let (paster, board, _) = make()
        var transient = false
        paster.sendPaste = { transient = board.types?.contains(.init("org.nspasteboard.TransientType")) == true }
        paster.paste("hello")
        t.expect(transient, true, "the dictated text is marked transient so clipboard history skips it")
        board.releaseGlobally()
    }
}

@MainActor
func historyChecks(_ t: Checker) {
    t.group("History") {
        let suite = "holler-check-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let history = History(defaults: defaults)
        history.add("first")
        history.add("second")
        history.add("")
        t.expect(history.items, ["second", "first"], "newest first, empty transcripts skipped")

        for i in 1...12 { history.add("item \(i)") }
        t.expect(history.items.count, 10, "keeps the last ten")
        t.expect(history.items.first, "item 12")

        t.expect(History(defaults: defaults).items, history.items, "survives a relaunch")
    }
}
