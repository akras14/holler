import FluidAudio
import Foundation

/// What was said in a recording, and when each piece of it was said.
public struct Transcript: Equatable {
    /// A piece of a word as the model hears it. A leading space starts a new word, so the
    /// pieces joined together give back the text.
    public struct Token: Equatable {
        public var text: String
        /// Seconds from the start of the recording.
        public var start: TimeInterval

        public init(text: String, start: TimeInterval) {
            self.text = text
            self.start = start
        }
    }

    public var text: String
    public var tokens: [Token]

    public init(text: String, tokens: [Token]) {
        self.text = text
        self.tokens = tokens
    }

    init(_ result: ASRResult) {
        self.init(text: result.text.trimmingCharacters(in: .whitespacesAndNewlines),
                  tokens: (result.tokenTimings ?? []).map { Token(text: $0.token, start: $0.startTime) })
    }

    /// One line per sentence, each starting with when it's said: "[1:05] It's raining."
    /// Recordings an hour or longer get hours on every line, so the lines stay aligned.
    public var withTimestamps: String {
        var sentences: [(start: TimeInterval, text: String)] = []
        var current: (start: TimeInterval, text: String)?
        for (i, token) in tokens.enumerated() {
            if current == nil { current = (token.start, "") }
            current!.text += token.text
            // A sentence ends at . ? or ! followed by a new word, so "3.5" stays whole.
            let next = i + 1 < tokens.count ? tokens[i + 1] : nil
            if let last = token.text.last, ".?!".contains(last), next.map({ $0.text.hasPrefix(" ") }) ?? true {
                sentences.append(current!)
                current = nil
            }
        }
        if let current { sentences.append(current) }

        let hours = (tokens.last?.start ?? 0) >= 3600
        return sentences
            .map { "[\(Self.time($0.start, hours: hours))] \($0.text.trimmingCharacters(in: .whitespaces))" }
            .joined(separator: "\n")
    }

    /// "1:05", or "0:01:05" with hours.
    static func time(_ seconds: TimeInterval, hours: Bool) -> String {
        let s = Int(seconds)
        return hours
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}
