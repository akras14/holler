import FluidAudio
import Foundation

/// Speech to text with Parakeet TDT v2 (English), run on the Neural Engine by FluidAudio.
///
/// The model lives in FluidAudio's shared cache, `~/Library/Application Support/FluidAudio/Models`,
/// which FluidVoice uses too, so a Mac that has run FluidVoice with Parakeet v2 downloads nothing.
public final class Transcriber {
    public static let version = AsrModelVersion.v2
    private let manager = AsrManager(config: .default)
    public private(set) var isLoaded = false

    public init() {}

    /// Whether the model is already on disk, so loading won't download ~450 MB.
    public static var isModelDownloaded: Bool { localModelFolder(in: modelsFolder) != nil }

    /// Loads the model, downloading it first if there's no copy on disk.
    public func load() async throws {
        let models: AsrModels
        if let folder = Self.localModelFolder(in: Self.modelsFolder) {
            models = try AsrModels.loadLocal(from: folder, version: Self.version)
        } else {
            models = try await AsrModels.downloadAndLoad(version: Self.version)
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
    /// FluidAudio's shared models folder.
    public static var modelsFolder: URL {
        AsrModels.defaultCacheDirectory(for: version).deletingLastPathComponent()
    }

    /// A complete copy of the model already on disk, if there is one.
    /// FluidVoice's folder comes first: older FluidAudio releases, which FluidVoice ships,
    /// name it after the Hugging Face repo, and current ones drop the `-coreml`. The
    /// weights are the same, so either copy saves a 450 MB download.
    static func localModelFolder(in models: URL) -> URL? {
        let required = ["Preprocessor.mlmodelc", "Encoder.mlmodelc", "Decoder.mlmodelc",
                        "JointDecision.mlmodelc", "parakeet_vocab.json"]
        return ["parakeet-tdt-0.6b-v2-coreml", "parakeet-tdt-0.6b-v2"]
            .map { models.appendingPathComponent($0) }
            .first { folder in
                required.allSatisfy {
                    FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
                }
            }
    }
}
