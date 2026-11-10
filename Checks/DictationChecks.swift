import AppKit
import AVFoundation
@testable import HollerKit

/// Stands in for the microphone: hands back prepared samples.
final class FakeMic: AudioSource {
    var onLevel: (Float) -> Void = { _ in }
    var samples: [Float] = []
    var failStart = false
    private(set) var running = false
    private(set) var starts = 0

    func start() throws {
        if failStart { throw NSError(domain: "mic", code: 1) }
        starts += 1
        running = true
    }
    func stop() -> [Float] {
        running = false
        return samples
    }
}

/// 16 kHz mono samples of `text` spoken by `say`.
func spokenSamples(_ text: String) -> [Float] {
    let url = spokenFile(text)
    defer { try? FileManager.default.removeItem(at: url) }
    let buffers = micBuffers(url)
    let stream = SampleStream(from: buffers[0].format)
    buffers.forEach(stream.append)
    return stream.finish()
}

@MainActor
func dictationChecks(_ t: Checker, transcriber: Transcriber) {
    func make(_ transcriber: Transcriber) -> (Dictation, FakeMic, () -> [String], History) {
        let mic = FakeMic()
        let board = NSPasteboard(name: NSPasteboard.Name("holler-check-\(UUID().uuidString)"))
        let paster = Paster(pasteboard: board)
        var pasted: [String] = []
        paster.sendPaste = { pasted.append(board.string(forType: .string) ?? "") }
        let suite = "holler-check-\(UUID().uuidString)"
        let history = History(defaults: UserDefaults(suiteName: suite)!)
        let dictation = Dictation(source: mic, transcriber: transcriber, paster: paster, history: history)
        return (dictation, mic, { pasted }, history)
    }

    t.group("Dictation") {
        let (dictation, mic, pasted, history) = make(transcriber)
        var logs: [String] = []
        dictation.log = { logs.append($0) }
        t.expect(dictation.state, .ready, "ready once the model is loaded")
        dictation.handle(.start)
        t.expect(mic.running, true, "the first tap opens the mic")
        t.expect(dictation.state, .recording)
        mic.samples = spokenSamples("Let's meet for lunch tomorrow.")
        dictation.handle(.finish)
        t.expect(mic.running, false, "the second closes it")
        t.expect(dictation.state, .transcribing)
        t.expect(waitUntil(timeout: 30) { !pasted().isEmpty }, true, "the transcript is pasted")
        t.expect(pasted().map(words), ["let s meet for lunch tomorrow"])
        t.expect(history.items.map(words), ["let s meet for lunch tomorrow"], "and kept in Recent")
        t.expect(dictation.state, .ready)
        t.expect(logs.count, 3, "the log has start, finish and the result")
        t.expect(logs.first, "start: mic on")
        t.expect(logs.dropFirst().first?.hasPrefix("finish: 1."), true, "finish gives the length: \(logs)")
        t.expect(logs.dropFirst().first?.contains(", peak 0."), true, "and how loud it got: \(logs)")
        t.expect(logs.last, "pasted \(pasted().first?.count ?? 0) characters", "the result gives the length, not the text")
    }

    t.group("Dictation: cancel") {
        let (dictation, mic, pasted, history) = make(transcriber)
        var logs: [String] = []
        dictation.log = { logs.append($0) }
        mic.samples = spokenSamples("This should never appear.")
        dictation.handle(.start)
        dictation.handle(.cancel)
        t.expect(logs, ["start: mic on", "cancel: mic off, recording dropped"])
        dictation.handle(.cancel)
        t.expect(logs.last, "ignored cancel: not recording")
        t.expect(mic.running, false, "Esc or a shortcut closes the mic")
        t.expect(dictation.state, .ready)
        t.expect(holds(for: 0.5) { pasted().isEmpty }, true, "and nothing is pasted")
        t.expect(history.items, [])
    }

    t.group("Dictation: silence") {
        let (dictation, mic, pasted, history) = make(transcriber)
        var logs: [String] = []
        dictation.log = { logs.append($0) }
        mic.samples = [Float](repeating: 0, count: 32_000)
        dictation.handle(.start)
        dictation.handle(.finish)
        t.expect(waitUntil { dictation.state == .ready }, true)
        t.expect(pasted(), [], "nothing heard, nothing pasted")
        t.expect(history.items, [])
        t.expect(logs, ["start: mic on", "finish: 2.00 s of audio, peak 0.00", "heard nothing"],
                 "a silent recording says so in the log")
    }

    t.group("Dictation: model still loading") {
        let (dictation, mic, _, _) = make(Transcriber())
        var logs: [String] = []
        dictation.log = { logs.append($0) }
        t.expect(dictation.state, .loading)
        dictation.handle(.start)
        t.expect(mic.starts, 0, "the key does nothing until the model is ready")
        t.expect(dictation.state, .loading)
        t.expect(logs, ["ignored start: model not loaded"])
    }

    t.group("Dictation: microphone fails") {
        let (dictation, mic, _, _) = make(transcriber)
        var logs: [String] = []
        dictation.log = { logs.append($0) }
        mic.failStart = true
        dictation.handle(.start)
        t.expect(dictation.state, .ready, "a mic that won't start leaves Holler ready for the next try")
        dictation.handle(.finish)
        t.expect(dictation.state, .ready, "and the release after it is ignored")
        t.expect(logs.count, 2)
        t.expect(logs.first?.hasPrefix("start: mic failed: "), true, "\(logs)")
        t.expect(logs.last, "ignored finish: not recording")
        mic.failStart = false
        dictation.handle(.start)
        t.expect(dictation.state, .recording)
        dictation.handle(.cancel)
    }
}
