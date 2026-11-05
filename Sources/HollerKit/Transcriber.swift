import FluidAudio
import Foundation

/// Speech to text with Parakeet TDT v2 (English), run on the Neural Engine by FluidAudio.
///
/// The model is downloaded to `~/Library/Application Support/Holler/Models`, unless
/// FluidVoice has already downloaded Parakeet v2, in which case Holler uses that copy.
public final class Transcriber {
    public static let version = AsrModelVersion.v2
    private let manager = AsrManager(config: .default)
    public private(set) var isLoaded = false

    public init() {}

    /// Whether the model is already on disk, so loading won't download ~450 MB.
    public static var isModelDownloaded: Bool { firstComplete(candidateFolders) != nil }

    /// Loads the model, downloading it first if there's no copy on disk.
    public func load() async throws {
        let models: AsrModels
        if let folder = Self.firstComplete(Self.candidateFolders) {
            models = try AsrModels.loadLocal(from: folder, version: Self.version)
        } else {
            // FluidAudio resumes or replaces a half-finished download here.
            models = try await AsrModels.downloadAndLoad(to: Self.ownFolder, version: Self.version)
        }
        try await manager.loadModels(models)
        isLoaded = true
    }

    /// Transcribes 16 kHz mono samples.
    public func transcribe(_ samples: [Float]) async throws -> String {
        // Parakeet needs at least a second of audio; pad short clips with silence.
        let padded = samples.count < 16_000
            ? samples + [Float](repeating: 0, count: 16_000 - samples.count) : samples
        var state = TdtDecoderState.make(decoderLayers: Self.version.decoderLayers)
        let result = try await manager.transcribe(padded, decoderState: &state)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Transcribes an audio file in any format AVFoundation reads.
    public func transcribe(file: URL) async throws -> String {
        try await transcribe(AudioConverter().resampleAudioFile(file))
    }
}

extension Transcriber {
    static let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

    /// Where Holler downloads the model.
    static var ownFolder: URL { support.appendingPathComponent("Holler/Models/parakeet-tdt-0.6b-v2") }

    /// Copies to try, in order: Holler's, then FluidVoice's. FluidVoice ships an older
    /// FluidAudio that names the folder after the Hugging Face repo; newer releases drop
    /// the `-coreml`. The weights are the same, so any copy saves a 450 MB download.
    static var candidateFolders: [URL] {
        let fluidAudio = support.appendingPathComponent("FluidAudio/Models")
        return [ownFolder,
                fluidAudio.appendingPathComponent("parakeet-tdt-0.6b-v2-coreml"),
                fluidAudio.appendingPathComponent("parakeet-tdt-0.6b-v2")]
    }

    /// The first folder holding a whole model. An interrupted download leaves every
    /// folder in place but with `.partial` weights, so those don't count.
    static func firstComplete(_ folders: [URL]) -> URL? {
        let required = ["Preprocessor.mlmodelc", "Encoder.mlmodelc", "Decoder.mlmodelc",
                        "JointDecision.mlmodelc", "parakeet_vocab.json"]
        let files = FileManager.default
        return folders.first { folder in
            guard required.allSatisfy({ files.fileExists(atPath: folder.appendingPathComponent($0).path) })
            else { return false }
            let contents = files.enumerator(at: folder, includingPropertiesForKeys: nil)
            return !(contents?.contains { ($0 as? URL)?.pathExtension == "partial" } ?? false)
        }
    }
}
