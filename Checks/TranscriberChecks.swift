import Foundation
@testable import HollerKit

/// Speech made with `say`, so the check needs no audio files in the repo.
func spokenFile(_ text: String) -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("holler-\(UUID().uuidString).aiff")
    let say = Process()
    say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
    say.arguments = ["-o", url.path, text]
    try! say.run()
    say.waitUntilExit()
    return url
}

/// Lowercase words only, so the check doesn't depend on punctuation or capitals.
func words(_ text: String) -> String {
    text.lowercased().components(separatedBy: CharacterSet.letters.inverted)
        .filter { !$0.isEmpty }.joined(separator: " ")
}

@MainActor
func transcriberChecks(_ t: Checker, transcriber: Transcriber) {
    t.group("Transcriber") {
        let loaded: Void? = finish(timeout: 300) { try await transcriber.load() }
        t.expect(loaded != nil, true, "loads the Parakeet model")

        let url = spokenFile("The quick brown fox jumps over the lazy dog.")
        defer { try? FileManager.default.removeItem(at: url) }
        let text = finish { try await transcriber.transcribe(file: url) }
        t.expect(text.map(words),
                 "the quick brown fox jumps over the lazy dog", "transcribes spoken English")

        let silence = finish { try await transcriber.transcribe([Float](repeating: 0, count: 16_000)) }
        t.expect(silence, "", "silence gives no text")
    }
}

/// A models folder holding fake Parakeet folders with the given names.
func fakeModels(_ folders: [String]) -> URL {
    let models = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    for folder in folders {
        for item in ["Preprocessor.mlmodelc", "Encoder.mlmodelc", "Decoder.mlmodelc", "JointDecision.mlmodelc"] {
            try! FileManager.default.createDirectory(
                at: models.appendingPathComponent(folder).appendingPathComponent(item),
                withIntermediateDirectories: true)
        }
        try! "{}".write(to: models.appendingPathComponent(folder).appendingPathComponent("parakeet_vocab.json"),
                        atomically: true, encoding: .utf8)
    }
    return models
}

@MainActor
func modelFolderChecks(_ t: Checker) {
    t.group("Model folder") {
        let fluidVoice = fakeModels(["parakeet-tdt-0.6b-v2-coreml"])
        t.expect(Transcriber.localModelFolder(in: fluidVoice)?.lastPathComponent,
                 "parakeet-tdt-0.6b-v2-coreml", "reuses the copy FluidVoice downloaded")

        let current = fakeModels(["parakeet-tdt-0.6b-v2"])
        t.expect(Transcriber.localModelFolder(in: current)?.lastPathComponent,
                 "parakeet-tdt-0.6b-v2", "uses the folder current FluidAudio downloads to")

        let partial = fakeModels(["parakeet-tdt-0.6b-v2-coreml"])
        try? FileManager.default.removeItem(
            at: partial.appendingPathComponent("parakeet-tdt-0.6b-v2-coreml/Encoder.mlmodelc"))
        t.expect(Transcriber.localModelFolder(in: partial), nil, "skips an incomplete download")

        t.expect(Transcriber.localModelFolder(in: fakeModels([])), nil, "nothing downloaded yet")
    }
}
