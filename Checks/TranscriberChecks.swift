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

/// A fake complete Parakeet model folder.
func fakeModel() -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    for item in ["Preprocessor.mlmodelc", "Encoder.mlmodelc", "Decoder.mlmodelc", "JointDecision.mlmodelc"] {
        try! FileManager.default.createDirectory(at: folder.appendingPathComponent(item),
                                                withIntermediateDirectories: true)
    }
    try! "{}".write(to: folder.appendingPathComponent("parakeet_vocab.json"), atomically: true, encoding: .utf8)
    return folder
}

@MainActor
func modelFolderChecks(_ t: Checker) {
    t.group("Model folder") {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        t.expect(Transcriber.ownFolder.path,
                 support.appendingPathComponent("Holler/Models/parakeet-tdt-0.6b-v2").path,
                 "downloads go in Holler's own folder")
        t.expect(Transcriber.candidateFolders.map(\.path), [
            Transcriber.ownFolder.path,
            support.appendingPathComponent("FluidAudio/Models/parakeet-tdt-0.6b-v2-coreml").path,
            support.appendingPathComponent("FluidAudio/Models/parakeet-tdt-0.6b-v2").path,
        ], "Holler's copy first, then FluidVoice's")

        let first = fakeModel(), second = fakeModel()
        t.expect(Transcriber.firstComplete([first, second]), first, "the first complete copy wins")

        let missingPiece = fakeModel()
        try! FileManager.default.removeItem(at: missingPiece.appendingPathComponent("Encoder.mlmodelc"))
        t.expect(Transcriber.firstComplete([missingPiece, second]), second, "a copy missing a piece is skipped")

        // An interrupted download leaves the folders in place with `.partial` weights.
        let interrupted = fakeModel()
        try! Data().write(to: interrupted.appendingPathComponent("Encoder.mlmodelc/weight.bin.partial"))
        t.expect(Transcriber.firstComplete([interrupted, second]), second, "a half-finished download is skipped")
        t.expect(Transcriber.firstComplete([interrupted]), nil, "so it gets downloaded again")

        let nowhere = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        t.expect(Transcriber.firstComplete([nowhere]), nil, "nothing downloaded yet")
    }
}
