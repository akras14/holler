import AVFoundation
@testable import HollerKit

/// Reads an audio file as the microphone delivers it: small buffers in the device's format.
func micBuffers(_ url: URL, sampleRate: Double = 48_000, channels: AVAudioChannelCount = 2,
                frames: AVAudioFrameCount = 4_800) -> [AVAudioPCMBuffer] {
    let file = try! AVAudioFile(forReading: url)
    let device = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
    let converter = AVAudioConverter(from: file.processingFormat, to: device)!
    var buffers: [AVAudioPCMBuffer] = []
    var done = false
    while !done {
        let out = AVAudioPCMBuffer(pcmFormat: device, frameCapacity: frames)!
        _ = converter.convert(to: out, error: nil) { count, status in
            let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count)!
            if (try? file.read(into: input, frameCount: count)) == nil || input.frameLength == 0 {
                status.pointee = .endOfStream
                return nil
            }
            status.pointee = .haveData
            return input
        }
        if out.frameLength == 0 { done = true } else { buffers.append(out) }
    }
    return buffers
}

@MainActor
func recorderChecks(_ t: Checker, transcriber: Transcriber) {
    t.group("Recorder: format conversion") {
        let device = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let stream = SampleStream(from: device)
        for _ in 0..<10 {
            let buffer = AVAudioPCMBuffer(pcmFormat: device, frameCapacity: 4_800)!
            buffer.frameLength = 4_800
            stream.append(buffer)
        }
        let samples = stream.finish()
        t.expect(abs(samples.count - 16_000) < 100, true, "one second of 48 kHz stereo is about 16,000 samples")
    }

    t.group("Recorder: speech through the converter") {
        let url = spokenFile("Please send the report by Friday afternoon.")
        defer { try? FileManager.default.removeItem(at: url) }
        let buffers = micBuffers(url)
        let stream = SampleStream(from: buffers[0].format)
        buffers.forEach(stream.append)
        let text = finish { try await transcriber.transcribe(stream.finish()) }
        t.expect(text.map(words), "please send the report by friday afternoon",
                 "speech cut into 0.1 s mic buffers transcribes cleanly")
    }

    t.group("Recorder: level") {
        let device = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let quiet = AVAudioPCMBuffer(pcmFormat: device, frameCapacity: 480)!
        quiet.frameLength = 480
        let loud = AVAudioPCMBuffer(pcmFormat: device, frameCapacity: 480)!
        loud.frameLength = 480
        for i in 0..<480 { loud.floatChannelData![0][i] = i % 2 == 0 ? 0.5 : -0.5 }
        t.expect(Recorder.level(of: quiet), 0, "silence is level 0")
        t.expect(Recorder.level(of: loud) > 0.8, true, "speech-loud audio is near the top")
    }
}

@MainActor
func microphoneChecks(_ t: Checker) {
    t.group("Microphones") {
        let all = Microphones.all()
        t.expect(all.allSatisfy { !$0.uid.isEmpty && !$0.name.isEmpty }, true, "every input has a name and UID")
        if let uid = Microphones.defaultUID {
            t.expect(all.contains { $0.uid == uid }, true, "the system default input is listed")
        }
        t.expect(all.contains { $0.uid == "BuiltInSpeakerDevice" }, false, "output-only devices aren't")
    }
}
