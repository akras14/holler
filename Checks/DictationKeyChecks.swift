import AppKit
@testable import HollerKit

/// Device-specific modifier bits, as macOS reports them in `flagsChanged` events.
let rightOption: UInt = 0x40 | NSEvent.ModifierFlags.option.rawValue
let leftOption: UInt = 0x20 | NSEvent.ModifierFlags.option.rawValue
let command: UInt = 0x08 | NSEvent.ModifierFlags.command.rawValue
let escape: UInt16 = 53

@MainActor
func dictationKeyChecks(_ t: Checker) {
    func make() -> (DictationKey, () -> [DictationKey.Action]) {
        let key = DictationKey()
        var actions: [DictationKey.Action] = []
        key.onAction = { actions.append($0) }
        return (key, { actions })
    }
    /// A Right Option tap: press at `time`, release a moment later.
    func tap(_ key: DictationKey, at time: TimeInterval) {
        key.flagsChanged(keyCode: 61, flags: rightOption, at: time)
        key.flagsChanged(keyCode: 61, flags: 0, at: time + 0.1)
    }

    t.group("Dictation key") {
        let (key, actions) = make()
        key.flagsChanged(keyCode: 61, flags: rightOption, at: 10)
        t.expect(actions(), [.start], "pressing Right Option starts recording")
        key.flagsChanged(keyCode: 61, flags: 0, at: 10.1)
        t.expect(actions(), [.start], "letting go keeps it recording")
        key.flagsChanged(keyCode: 61, flags: rightOption, at: 15)
        t.expect(actions(), [.start, .finish], "the second press stops it")
        key.flagsChanged(keyCode: 61, flags: 0, at: 15.1)
        t.expect(actions(), [.start, .finish], "and its release does nothing")
        tap(key, at: 20)
        tap(key, at: 25)
        t.expect(actions(), [.start, .finish, .start, .finish], "and it works again after that")
    }

    t.group("Dictation key: holding") {
        let (key, actions) = make()
        key.flagsChanged(keyCode: 61, flags: rightOption, at: 10)
        key.flagsChanged(keyCode: 61, flags: 0, at: 13)
        t.expect(actions(), [.start], "a long press starts recording like a tap")
        tap(key, at: 20)
        t.expect(actions(), [.start, .finish])
    }

    t.group("Dictation key: double tap") {
        let (key, actions) = make()
        tap(key, at: 10)
        tap(key, at: 10.2)
        t.expect(actions(), [.start, .cancel], "two quick taps are thrown away")
    }

    t.group("Dictation key: Esc") {
        let (key, actions) = make()
        tap(key, at: 10)
        key.keyDown(keyCode: escape, at: 12)
        t.expect(actions(), [.start, .cancel], "Esc cancels")
        tap(key, at: 14)
        t.expect(actions(), [.start, .cancel, .start], "and the next tap starts afresh")

        let (idle, idleActions) = make()
        idle.keyDown(keyCode: escape, at: 10)
        t.expect(idleActions(), [], "Esc does nothing when not recording")
    }

    t.group("Dictation key: typing while recording") {
        let (key, actions) = make()
        tap(key, at: 10)
        key.keyDown(keyCode: 0, at: 11)
        key.flagsChanged(keyCode: 55, flags: command, at: 12)
        key.flagsChanged(keyCode: 55, flags: 0, at: 12.1)
        t.expect(actions(), [.start], "other keys don't stop the recording")
        tap(key, at: 15)
        t.expect(actions(), [.start, .finish])
    }

    t.group("Dictation key: shortcuts") {
        let (key, actions) = make()
        key.flagsChanged(keyCode: 58, flags: leftOption, at: 10)
        key.flagsChanged(keyCode: 58, flags: 0, at: 10.1)
        t.expect(actions(), [], "Left Option does nothing")

        key.flagsChanged(keyCode: 55, flags: command, at: 12)
        key.flagsChanged(keyCode: 61, flags: command | rightOption, at: 12.1)
        key.flagsChanged(keyCode: 61, flags: command, at: 12.2)
        key.flagsChanged(keyCode: 55, flags: 0, at: 12.3)
        t.expect(actions(), [], "⌘ held first: it's a shortcut, not dictation")

        key.flagsChanged(keyCode: 61, flags: rightOption, at: 20)
        key.keyDown(keyCode: 0, at: 20.1)
        key.flagsChanged(keyCode: 61, flags: 0, at: 20.2)
        t.expect(actions(), [.start, .cancel], "⌥-letter cancels the recording it started")
        tap(key, at: 25)
        t.expect(actions(), [.start, .cancel, .start], "and the next tap starts a new one")

        let (key2, actions2) = make()
        key2.flagsChanged(keyCode: 61, flags: rightOption, at: 10)
        key2.flagsChanged(keyCode: 55, flags: rightOption | command, at: 10.1)
        key2.flagsChanged(keyCode: 55, flags: rightOption, at: 10.2)
        key2.flagsChanged(keyCode: 61, flags: 0, at: 10.3)
        t.expect(actions2(), [.start, .cancel], "so does adding ⌘ to Right Option")
    }

    t.group("Dictation key: log") {
        let (key, _) = make()
        var logs: [String] = []
        key.log = { logs.append($0) }
        key.flagsChanged(keyCode: 58, flags: leftOption, at: 5)
        key.flagsChanged(keyCode: 58, flags: 0, at: 5.1)
        key.keyDown(keyCode: 0, at: 6)
        t.expect(logs, [], "ordinary typing isn't logged")

        tap(key, at: 10)
        key.keyDown(keyCode: 0, at: 11)
        key.flagsChanged(keyCode: 61, flags: rightOption, at: 12.5)
        key.flagsChanged(keyCode: 61, flags: 0, at: 12.6)
        t.expect(logs, [
            "key 61 flags 0x80040: idle → starting, start",
            "key 61 flags 0x0: starting → recording",
            "key 61 flags 0x80040: recording → stopping, finish after 2.50 s",
            "key 61 flags 0x0: stopping → idle",
        ], "every Right Option step is, with its flags; keys that change nothing aren't")

        logs = []
        key.flagsChanged(keyCode: 61, flags: rightOption, at: 20)
        key.keyDown(keyCode: 0, at: 20.1)
        key.flagsChanged(keyCode: 61, flags: 0, at: 20.2)
        tap(key, at: 30)
        tap(key, at: 30.2)
        t.expect(logs, [
            "key 61 flags 0x80040: idle → starting, start",
            "key down 0: starting → idle, cancel",
            "key 61 flags 0x0: idle → idle",
            "key 61 flags 0x80040: idle → starting, start",
            "key 61 flags 0x0: starting → recording",
            "key 61 flags 0x80040: recording → stopping, cancel after 0.20 s",
            "key 61 flags 0x0: stopping → idle",
        ], "and so is what cancels a recording")
    }

    t.group("Dictation key: caps lock") {
        let (key, actions) = make()
        let capsLock = NSEvent.ModifierFlags.capsLock.rawValue
        key.flagsChanged(keyCode: 61, flags: rightOption | capsLock, at: 10)
        key.flagsChanged(keyCode: 61, flags: capsLock, at: 10.1)
        key.flagsChanged(keyCode: 61, flags: rightOption | capsLock, at: 12)
        t.expect(actions(), [.start, .finish], "caps lock on doesn't get in the way")
    }
}

@MainActor
func keyMonitorChecks(_ t: Checker) {
    func flags(_ keyCode: UInt16, _ raw: UInt, at time: TimeInterval) -> NSEvent {
        NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: raw),
                         timestamp: time, windowNumber: 0, context: nil, characters: "",
                         charactersIgnoringModifiers: "", isARepeat: false, keyCode: keyCode)!
    }
    func key(_ keyCode: UInt16, at time: TimeInterval) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                         timestamp: time, windowNumber: 0, context: nil, characters: "\u{1b}",
                         charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: keyCode)!
    }

    t.group("Key events") {
        let dictationKey = DictationKey()
        var actions: [DictationKey.Action] = []
        dictationKey.onAction = { actions.append($0) }
        let monitor = KeyMonitor(key: dictationKey)

        monitor.handle(flags(61, rightOption, at: 100))
        monitor.handle(flags(61, 0, at: 100.1))
        monitor.handle(flags(61, rightOption, at: 102))
        t.expect(actions, [.start, .finish], "Right Option events from macOS reach the dictation key")

        monitor.handle(flags(61, 0, at: 102.1))
        monitor.handle(flags(61, rightOption, at: 104))
        monitor.handle(flags(61, 0, at: 104.1))
        monitor.handle(key(escape, at: 105))
        t.expect(actions, [.start, .finish, .start, .cancel], "so does Esc")
    }
}
