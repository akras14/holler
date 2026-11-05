import AppKit
@testable import HollerKit

/// Device-specific modifier bits, as macOS reports them in `flagsChanged` events.
let rightOption: UInt = 0x40 | NSEvent.ModifierFlags.option.rawValue
let leftOption: UInt = 0x20 | NSEvent.ModifierFlags.option.rawValue
let command: UInt = 0x08 | NSEvent.ModifierFlags.command.rawValue

@MainActor
func pushToTalkChecks(_ t: Checker) {
    func make() -> (PushToTalk, () -> [PushToTalk.Action]) {
        let ptt = PushToTalk()
        var actions: [PushToTalk.Action] = []
        ptt.onAction = { actions.append($0) }
        return (ptt, { actions })
    }

    t.group("Push to talk") {
        let (ptt, actions) = make()
        ptt.flagsChanged(keyCode: 61, flags: rightOption, at: 10)
        t.expect(actions(), [.start], "pressing Right Option starts recording")
        ptt.flagsChanged(keyCode: 61, flags: 0, at: 11)
        t.expect(actions(), [.start, .finish], "releasing it finishes")
    }

    t.group("Push to talk: quick tap") {
        let (ptt, actions) = make()
        ptt.flagsChanged(keyCode: 61, flags: rightOption, at: 10)
        ptt.flagsChanged(keyCode: 61, flags: 0, at: 10.1)
        t.expect(actions(), [.start, .cancel], "a tap is thrown away")
    }

    t.group("Push to talk: other keys") {
        let (ptt, actions) = make()
        ptt.flagsChanged(keyCode: 58, flags: leftOption, at: 10)
        ptt.flagsChanged(keyCode: 58, flags: 0, at: 11)
        t.expect(actions(), [], "Left Option does nothing")

        ptt.flagsChanged(keyCode: 55, flags: command, at: 12)
        ptt.flagsChanged(keyCode: 61, flags: command | rightOption, at: 12.1)
        ptt.flagsChanged(keyCode: 61, flags: command, at: 13)
        t.expect(actions(), [], "⌘ held first: it's a shortcut, not dictation")
    }

    t.group("Push to talk: shortcuts while holding") {
        let (ptt, actions) = make()
        ptt.flagsChanged(keyCode: 61, flags: rightOption, at: 10)
        ptt.keyDown(at: 10.5)
        t.expect(actions(), [.start, .cancel], "typing ⌥-letter cancels")
        ptt.flagsChanged(keyCode: 61, flags: 0, at: 11)
        t.expect(actions(), [.start, .cancel], "and the release after it does nothing")

        let (ptt2, actions2) = make()
        ptt2.flagsChanged(keyCode: 61, flags: rightOption, at: 10)
        ptt2.flagsChanged(keyCode: 55, flags: rightOption | command, at: 10.5)
        t.expect(actions2(), [.start, .cancel], "adding ⌘ cancels")
    }

    t.group("Push to talk: caps lock") {
        let (ptt, actions) = make()
        let capsLock = NSEvent.ModifierFlags.capsLock.rawValue
        ptt.flagsChanged(keyCode: 61, flags: rightOption | capsLock, at: 10)
        ptt.flagsChanged(keyCode: 61, flags: capsLock, at: 11)
        t.expect(actions(), [.start, .finish], "caps lock on doesn't get in the way")
    }
}
