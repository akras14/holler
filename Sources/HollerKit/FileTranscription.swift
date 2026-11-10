import AppKit
import AVFoundation

/// Transcribes a recording or video chosen from the menu and copies the text to the
/// clipboard. One file at a time; dictation keeps working meanwhile. Runs on the main thread.
public final class FileTranscription {
    public enum Outcome: Equatable {
        case copied(String)
        case noSpeech
        /// Not a file macOS can read sound from: not audio or video, or a video with no sound.
        case unreadable
        case failed(String)
    }

    /// The file being transcribed, if any.
    public private(set) var file: URL? { didSet { onChange() } }
    public var onChange: () -> Void = {}
    public var onFinish: (URL, Outcome) -> Void = { _, _ in }

    private let transcriber: Transcriber
    private let pasteboard: NSPasteboard

    public init(transcriber: Transcriber, pasteboard: NSPasteboard = .general) {
        self.transcriber = transcriber
        self.pasteboard = pasteboard
    }

    public func start(_ url: URL) {
        guard file == nil, transcriber.isLoaded else { return }
        file = url
        Task { @MainActor in
            let outcome = await transcribe(url)
            if case .copied(let text) = outcome {
                // A plain copy, not marked transient like a dictation: this one is meant to stay.
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
            }
            file = nil
            onFinish(url, outcome)
        }
    }

    private func transcribe(_ url: URL) async -> Outcome {
        guard (try? AVAudioFile(forReading: url)) != nil else { return .unreadable }
        do {
            let text = try await transcriber.transcribe(file: url)
            return text.isEmpty ? .noSpeech : .copied(text)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// The name the Save panel suggests: the recording's, as a text file.
    public static func textFileName(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent + ".txt"
    }

    public static func save(_ text: String, to url: URL) throws {
        try (text + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// What the window shown when a file is done says.
    public static func message(for url: URL, _ outcome: Outcome) -> (title: String, detail: String) {
        let name = url.lastPathComponent
        switch outcome {
        case .copied(let text):
            let count = text.split(whereSeparator: \.isWhitespace).count
            let preview = StatusMenu.shorten(text, to: 200)
            return ("Transcript copied to the clipboard",
                    "\(name): \(count) \(count == 1 ? "word" : "words"). Paste it anywhere, or save it as a text file."
                        + "\n\n“\(preview)”")
        case .noSpeech:
            return ("No speech found", "Holler didn't hear any speech in \(name). Nothing was copied.")
        case .unreadable:
            return ("Couldn't read \(name)",
                    "Holler reads the audio and video formats macOS plays, such as MP3, M4A, WAV, MP4 and MOV. "
                        + "Nothing was copied.")
        case .failed(let reason):
            return ("Couldn't transcribe \(name)", "\(reason) Nothing was copied.")
        }
    }
}
