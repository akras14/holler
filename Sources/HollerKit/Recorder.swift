import AVFoundation
import CoreAudio

/// Converts microphone buffers, in whatever format the device uses, to 16 kHz mono.
///
/// One converter for the whole recording, so its filter state carries across buffers
/// instead of clicking at every buffer boundary.
final class SampleStream {
    static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                      channels: 1, interleaved: false)!
    private let converter: AVAudioConverter
    private var samples: [Float] = []

    init(from format: AVAudioFormat) {
        converter = AVAudioConverter(from: format, to: Self.format)!
    }

    func append(_ buffer: AVAudioPCMBuffer) { convert(buffer) }

    /// Flushes what the converter is still holding and returns everything.
    func finish() -> [Float] {
        convert(nil)
        return samples
    }

    private func convert(_ buffer: AVAudioPCMBuffer?) {
        var fed = false
        let ratio = Self.format.sampleRate / converter.inputFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer?.frameLength ?? 0) * ratio) + 1_024
        while true {
            let out = AVAudioPCMBuffer(pcmFormat: Self.format, frameCapacity: capacity)!
            let status = converter.convert(to: out, error: nil) { _, inputStatus in
                guard let buffer, !fed else {
                    inputStatus.pointee = buffer == nil ? .endOfStream : .noDataNow
                    return nil
                }
                fed = true
                inputStatus.pointee = .haveData
                return buffer
            }
            if out.frameLength > 0 {
                samples.append(contentsOf: UnsafeBufferPointer(start: out.floatChannelData![0],
                                                               count: Int(out.frameLength)))
            }
            // Keep draining while the output filled up; stop once the converter wants more input.
            if status != .haveData || out.frameLength < out.frameCapacity { break }
        }
    }
}

/// Records the microphone into 16 kHz mono samples.
public final class Recorder {
    /// The input's loudness from 0 to 1, about ten times a second, on the main thread.
    public var onLevel: (Float) -> Void = { _ in }
    /// The microphone to use, by Core Audio UID; nil for the system default.
    public var deviceUID: String?

    private var engine: AVAudioEngine?
    private var stream: SampleStream?
    private let lock = NSLock()

    public init() {}

    public func start() throws {
        // A fresh engine each time picks up whatever input is current now.
        let engine = AVAudioEngine()
        let input = engine.inputNode
        if let uid = deviceUID, var id = Microphones.deviceID(forUID: uid), let unit = input.audioUnit {
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                 &id, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        lock.withLock { stream = nil }
        input.installTap(onBus: 0, bufferSize: 4_800, format: nil) { [weak self] buffer, _ in
            guard let self else { return }
            self.lock.withLock {
                if self.stream == nil { self.stream = SampleStream(from: buffer.format) }
                self.stream?.append(buffer)
            }
            let level = Self.level(of: buffer)
            DispatchQueue.main.async { self.onLevel(level) }
        }
        engine.prepare()
        try engine.start()
        self.engine = engine
    }

    /// Stops recording and returns what was heard.
    public func stop() -> [Float] {
        guard let engine else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        return lock.withLock {
            defer { stream = nil }
            return stream?.finish() ?? []
        }
    }

    /// RMS of the first channel on a -50…0 dB scale, mapped to 0…1.
    static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += data[0][i] * data[0][i] }
        let rms = (sum / Float(n)).squareRoot()
        guard rms > 0 else { return 0 }
        let db = 20 * log10(rms)
        return min(max((db + 50) / 50, 0), 1)
    }
}
