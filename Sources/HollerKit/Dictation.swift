import Foundation

public protocol AudioSource: AnyObject {
    var onLevel: (Float) -> Void { get set }
    func start() throws
    func stop() -> [Float]
}

extension Recorder: AudioSource {}

/// Key → microphone → transcript → paste. Runs on the main thread.
public final class Dictation {
    public enum State: Equatable { case loading, ready, recording, transcribing }

    public private(set) var state: State = .loading { didSet { if state != oldValue { onStateChange(state) } } }
    public var onStateChange: (State) -> Void = { _ in }
    /// Called when the microphone or transcription fails, with a message for the menu.
    public var onError: (String) -> Void = { _ in }
    /// Each start, finish and cancel, and what came of it.
    public var log: (String) -> Void = Log.writer("dictation")

    private let source: AudioSource
    private let transcriber: Transcriber
    private let paster: Paster
    private let history: History
    private var recording = false
    /// Transcripts still being worked out: another recording can start meanwhile.
    private var pending = 0

    public init(source: AudioSource, transcriber: Transcriber, paster: Paster, history: History) {
        self.source = source
        self.transcriber = transcriber
        self.paster = paster
        self.history = history
        updateState()
    }

    public func loadModel() async throws {
        try await transcriber.load()
        updateState()
    }

    public func handle(_ action: DictationKey.Action) {
        guard transcriber.isLoaded else {
            log("ignored \(action): model not loaded")
            return
        }
        switch action {
        case .start:
            guard !recording else {
                log("ignored start: already recording")
                return
            }
            do {
                try source.start()
                recording = true
                log("start: mic on")
            } catch {
                log("start: mic failed: \(error.localizedDescription)")
                onError("Couldn't start the microphone: \(error.localizedDescription)")
            }
        case .cancel:
            guard recording else {
                log("ignored cancel: not recording")
                return
            }
            recording = false
            _ = source.stop()
            log("cancel: mic off, recording dropped")
        case .finish:
            guard recording else {
                log("ignored finish: not recording")
                return
            }
            recording = false
            let samples = source.stop()
            let peak = samples.lazy.map(abs).max() ?? 0
            log(String(format: "finish: %.2f s of audio, peak %.2f", Double(samples.count) / 16_000, peak))
            pending += 1
            Task { @MainActor in
                defer {
                    pending -= 1
                    updateState()
                }
                do {
                    let text = try await transcriber.transcribe(samples)
                    guard !text.isEmpty else {
                        log("heard nothing")
                        return
                    }
                    history.add(text)
                    paster.paste(text)
                    log("pasted \(text.count) characters")
                } catch {
                    log("transcription failed: \(error.localizedDescription)")
                    onError("Couldn't transcribe: \(error.localizedDescription)")
                }
            }
        }
        updateState()
    }

    private func updateState() {
        state = !transcriber.isLoaded ? .loading : recording ? .recording : pending > 0 ? .transcribing : .ready
    }
}
