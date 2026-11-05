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

    public func handle(_ action: PushToTalk.Action) {
        guard transcriber.isLoaded else { return }
        switch action {
        case .start:
            guard !recording else { return }
            do {
                try source.start()
                recording = true
            } catch {
                onError("Couldn't start the microphone: \(error.localizedDescription)")
            }
        case .cancel:
            guard recording else { return }
            recording = false
            _ = source.stop()
        case .finish:
            guard recording else { return }
            recording = false
            let samples = source.stop()
            pending += 1
            Task { @MainActor in
                defer {
                    pending -= 1
                    updateState()
                }
                do {
                    let text = try await transcriber.transcribe(samples)
                    guard !text.isEmpty else { return }
                    history.add(text)
                    paster.paste(text)
                } catch {
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
