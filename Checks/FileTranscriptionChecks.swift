import AppKit
import AVFoundation
@testable import HollerKit

/// A small QuickTime movie: a blank picture with `text` spoken by `say` as its sound.
func spokenVideo(_ text: String) -> URL {
    let speech = spokenFile(text)
    defer { try? FileManager.default.removeItem(at: speech) }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("holler-\(UUID().uuidString).mov")
    let writer = try! AVAssetWriter(outputURL: url, fileType: .mov)
    let picture = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64,
    ])
    let frames = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: picture, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64,
    ])
    let sound = AVAssetWriterInput(mediaType: .audio, outputSettings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
    ])
    writer.add(picture)
    writer.add(sound)

    let asset = AVURLAsset(url: speech)
    let reader = try! AVAssetReader(asset: asset)
    let samples = AVAssetReaderTrackOutput(track: asset.tracks(withMediaType: .audio)[0],
                                           outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
    reader.add(samples)
    reader.startReading()
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    // Each input is fed from its own queue: fed one after the other, the writer can
    // stall waiting for the second while it interleaves them.
    let done = DispatchGroup()
    done.enter()
    done.enter()
    let seconds = Int(asset.duration.seconds.rounded(.up))
    var frame = 0
    picture.requestMediaDataWhenReady(on: DispatchQueue(label: "picture")) {
        while picture.isReadyForMoreMediaData {
            guard frame <= seconds else { picture.markAsFinished(); done.leave(); return }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, frames.pixelBufferPool!, &buffer)
            frames.append(buffer!, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 1))
            frame += 1
        }
    }
    sound.requestMediaDataWhenReady(on: DispatchQueue(label: "sound")) {
        while sound.isReadyForMoreMediaData {
            guard let buffer = samples.copyNextSampleBuffer() else { sound.markAsFinished(); done.leave(); return }
            sound.append(buffer)
        }
    }
    done.wait()
    let finished = DispatchSemaphore(value: 0)
    writer.finishWriting { finished.signal() }
    finished.wait()
    precondition(writer.status == .completed, "couldn't write the movie: \(String(describing: writer.error))")
    return url
}

/// A WAV file of silence.
func silentFile(seconds: Double) -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("holler-\(UUID().uuidString).wav")
    let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
    let frames = AVAudioFrameCount(seconds * 16_000)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    try! AVAudioFile(forWriting: url, settings: format.settings).write(from: buffer)
    return url
}

@MainActor
func fileTranscriptionChecks(_ t: Checker, transcriber: Transcriber) {
    func make(_ transcriber: Transcriber) -> (FileTranscription, NSPasteboard, () -> [FileTranscription.Outcome]) {
        let board = NSPasteboard(name: NSPasteboard.Name("holler-check-\(UUID().uuidString)"))
        let files = FileTranscription(transcriber: transcriber, pasteboard: board)
        var outcomes: [FileTranscription.Outcome] = []
        files.onFinish = { _, outcome in outcomes.append(outcome) }
        return (files, board, { outcomes })
    }

    t.group("Transcriber: files") {
        let video = spokenVideo("Please send me the slides after the meeting.")
        defer { try? FileManager.default.removeItem(at: video) }
        let fromVideo = finish { try await transcriber.transcribe(file: video) }
        t.expect(fromVideo.map(words), "please send me the slides after the meeting", "reads a video's sound track")

        // FluidAudio refuses anything under 0.3 seconds.
        let blip = silentFile(seconds: 0.2)
        defer { try? FileManager.default.removeItem(at: blip) }
        t.expect(finish { try await transcriber.transcribe(file: blip) }, "", "a tiny file is padded, not refused")

        // Over 30 seconds, so FluidAudio reads it in chunks from disk.
        let sentences = [
            "The library opens at nine in the morning and closes at six in the evening.",
            "On weekends the hours are shorter, and the reading room stays closed.",
            "Members can borrow up to ten books at a time for three weeks.",
            "Late returns cost twenty five cents a day, up to five dollars a book.",
            "The children's section has story time every Tuesday and Thursday afternoon.",
            "Printing costs ten cents a page, and the scanner on the second floor is free.",
            "Study rooms can be booked a week ahead at the front desk or online.",
        ]
        let long = spokenFile(sentences.joined(separator: " "))
        defer { try? FileManager.default.removeItem(at: long) }
        let duration = (try? AVAudioFile(forReading: long)).map { Double($0.length) / $0.fileFormat.sampleRate } ?? 0
        t.expect(duration > 30, true, "the long recording is over 30 seconds (\(duration)s)")
        let text = finish(timeout: 120) { try await transcriber.transcribe(file: long) }.map(words) ?? ""
        for phrase in ["the library opens", "story time every tuesday", "study rooms can be booked"] {
            t.expect(text.contains(phrase), true, "a long recording comes through whole: \(phrase)")
        }
    }

    t.group("File transcription") {
        let (files, board, outcomes) = make(transcriber)
        board.clearContents()
        board.setString("what was copied before", forType: .string)
        var names: [String?] = []
        files.onChange = { names.append(files.file?.lastPathComponent) }
        let video = spokenVideo("The package arrives on Friday.")
        // Made up front: `say` spins the run loop, which would let the first file finish.
        let second = spokenFile("A second file.")
        defer { [video, second].forEach { try? FileManager.default.removeItem(at: $0) } }

        files.start(video)
        t.expect(files.file, video, "knows which file it's working on, for the menu")
        files.start(second)
        t.expect(files.file, video, "one file at a time")
        t.expect(waitUntil(timeout: 30) { !outcomes().isEmpty }, true, "finishes")
        guard case .copied(let text)? = outcomes().first else {
            return t.expect(String(describing: outcomes()), "copied", "the transcript is copied")
        }
        t.expect(words(text), "the package arrives on friday")
        t.expect(outcomes().count, 1, "the file started while busy was ignored")
        t.expect(board.string(forType: .string), text, "and is on the clipboard")
        t.expect(board.types?.contains(Paster.transient), false,
                 "kept by clipboard managers: unlike a dictation, this copy is meant to stay")
        t.expect(files.file, nil, "free for the next file")
        t.expect(names, [video.lastPathComponent, nil], "says when it starts and stops")
    }

    t.group("File transcription: nothing to copy") {
        let (files, board, outcomes) = make(transcriber)
        board.clearContents()
        board.setString("what was copied before", forType: .string)

        let quiet = silentFile(seconds: 2)
        defer { try? FileManager.default.removeItem(at: quiet) }
        files.start(quiet)
        t.expect(waitUntil(timeout: 30) { !outcomes().isEmpty }, true)
        t.expect(outcomes(), [.noSpeech], "silence")

        let notAudio = FileManager.default.temporaryDirectory.appendingPathComponent("holler-\(UUID().uuidString).mp3")
        defer { try? FileManager.default.removeItem(at: notAudio) }
        try! "just some text".write(to: notAudio, atomically: true, encoding: .utf8)
        files.start(notAudio)
        t.expect(waitUntil(timeout: 30) { outcomes().count == 2 }, true)
        t.expect(outcomes().last, .unreadable, "a file with no sound Holler can read")
        t.expect(board.string(forType: .string), "what was copied before", "neither touches the clipboard")
    }

    t.group("File transcription: model still loading") {
        let (files, _, outcomes) = make(Transcriber())
        let url = spokenFile("Too early.")
        defer { try? FileManager.default.removeItem(at: url) }
        files.start(url)
        t.expect(files.file, nil, "nothing starts until the model is ready")
        t.expect(holds(for: 0.3) { outcomes().isEmpty }, true)
    }

    t.group("File transcription: saving") {
        let lecture = URL(fileURLWithPath: "/Users/me/Movies/Week 3 lecture.mp4")
        t.expect(FileTranscription.textFileName(for: lecture), "Week 3 lecture.txt", "named after the recording")
        let saved = FileManager.default.temporaryDirectory.appendingPathComponent("holler-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: saved) }
        let saveResult: Void? = try? FileTranscription.save("Ünïcode — fine.", to: saved)
        t.expect(saveResult != nil, true, "saves")
        t.expect(try? String(contentsOf: saved, encoding: .utf8), "Ünïcode — fine.\n", "as UTF-8 text")
    }

    t.group("File transcription: messages") {
        let file = URL(fileURLWithPath: "/tmp/interview.m4a")
        let copied = FileTranscription.message(for: file, .copied(String(repeating: "word ", count: 100) + "end."))
        t.expect(copied.title, "Transcript copied to the clipboard", "says plainly where the text went")
        t.expect(copied.detail.hasPrefix("interview.m4a: 101 words. Paste it anywhere, or save it as a text file."),
                 true, copied.detail)
        t.expect(copied.detail.hasSuffix("word word…”"), true, "with the start of it, to check it's the right one")
        t.expect(FileTranscription.message(for: file, .copied("Hi.")).detail,
                 "interview.m4a: 1 word. Paste it anywhere, or save it as a text file.\n\n“Hi.”")

        let none = FileTranscription.message(for: file, .noSpeech)
        t.expect(none.title, "No speech found")
        t.expect(none.detail, "Holler didn't hear any speech in interview.m4a. Nothing was copied.")
        let unreadable = FileTranscription.message(for: file, .unreadable)
        t.expect(unreadable.title, "Couldn't read interview.m4a")
        t.expect(unreadable.detail,
                 "Holler reads the audio and video formats macOS plays, such as MP3, M4A, WAV, MP4 and MOV. "
                     + "Nothing was copied.")
        let failed = FileTranscription.message(for: file, .failed("The model stopped."))
        t.expect(failed.title, "Couldn't transcribe interview.m4a")
        t.expect(failed.detail, "The model stopped. Nothing was copied.")
    }
}
