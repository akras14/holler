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

    t.group("Timestamps") {
        typealias T = Transcript.Token
        let short = Transcript(text: "Hi. Bye", tokens: [T(text: " Hi", start: 5.2), T(text: ".", start: 5.5),
                                                          T(text: " Bye", start: 70)])
        t.expect(short.withTimestamps, "[0:05] Hi.\n[1:10] Bye",
                 "one line per sentence, from when it starts; the last needn't end in a full stop")

        let long = Transcript(text: "", tokens: [
            T(text: " Hello", start: 0.4), T(text: " there", start: 0.8), T(text: ".", start: 1.1),
            T(text: " It", start: 65.2), T(text: " costs", start: 65.5), T(text: " 3", start: 66),
            T(text: ".", start: 66.1), T(text: "5", start: 66.2), T(text: " dollars", start: 66.4),
            T(text: "?", start: 66.9), T(text: " Yes", start: 3725), T(text: "!", start: 3725.3),
        ])
        t.expect(long.withTimestamps, "[0:00:00] Hello there.\n[0:01:05] It costs 3.5 dollars?\n[1:02:05] Yes!",
                 "hours once the recording is that long, on every line so they line up; 3.5 isn't a sentence end")

        t.expect(Transcript(text: "", tokens: []).withTimestamps, "", "nothing said, nothing to stamp")
    }

    t.group("Transcriber: files") {
        let video = spokenVideo("Please send me the slides after the meeting.")
        defer { try? FileManager.default.removeItem(at: video) }
        let fromVideo = finish { try await transcriber.transcribe(file: video) }
        t.expect(fromVideo.map { words($0.text) }, "please send me the slides after the meeting",
                 "reads a video's sound track")
        t.expect(fromVideo.map { words($0.tokens.map(\.text).joined()) }, "please send me the slides after the meeting",
                 "with the time of each piece")

        // FluidAudio refuses anything under 0.3 seconds.
        let blip = silentFile(seconds: 0.2)
        defer { try? FileManager.default.removeItem(at: blip) }
        t.expect(finish { try await transcriber.transcribe(file: blip) }?.text, "", "a tiny file is padded, not refused")

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
        let transcript = finish(timeout: 120) { try await transcriber.transcribe(file: long) }
        let text = transcript.map { words($0.text) } ?? ""
        for phrase in ["the library opens", "story time every tuesday", "study rooms can be booked"] {
            t.expect(text.contains(phrase), true, "a long recording comes through whole: \(phrase)")
        }

        // Each line's time, in seconds, from "[m:ss] …".
        let lines = (transcript?.withTimestamps ?? "").split(separator: "\n")
        let times = lines.compactMap { line -> Int? in
            guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return nil }
            let parts = line[line.index(after: line.startIndex)..<close].split(separator: ":").compactMap { Int($0) }
            return parts.count == 2 ? parts[0] * 60 + parts[1] : nil
        }
        t.expect(lines.count, sentences.count, "a timestamped line per sentence: \(lines)")
        t.expect(times.count, lines.count, "each starting with its time")
        t.expect(times.first, 0, "the first at the start")
        t.expect(times == times.sorted() && Set(times).count == times.count, true, "in order: \(times)")
        t.expect((times.last ?? 0) > 25, true, "times run on across the chunks of a long file: \(times)")
        t.expect(words(lines.last.map(String.init) ?? "").hasSuffix("study rooms can be booked a week ahead at the front desk or online"),
                 true, "the last line holds the last sentence")
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

    t.group("File transcription: with timestamps") {
        let (files, board, outcomes) = make(transcriber)
        let url = spokenFile("The package arrives on Friday. Please sign for it.")
        defer { try? FileManager.default.removeItem(at: url) }
        files.start(url, timestamps: true)
        t.expect(waitUntil(timeout: 30) { !outcomes().isEmpty }, true, "finishes")
        guard case .copied(let text)? = outcomes().first else {
            return t.expect(String(describing: outcomes()), "copied", "the transcript is copied")
        }
        let lines = text.split(separator: "\n").map(String.init)
        t.expect(lines.count, 2, "a line per sentence: \(text)")
        t.expect(lines.first?.hasPrefix("[0:00] "), true, text)
        t.expect(lines.last?.range(of: #"^\[0:0[1-9]\] "#, options: .regularExpression) != nil, true, text)
        t.expect(words(text.replacingOccurrences(of: #"\[[0-9:]+\]"#, with: "", options: .regularExpression)),
                 "the package arrives on friday please sign for it")
        t.expect(board.string(forType: .string), text, "on the clipboard like that")
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
        t.expect(FileTranscription.message(for: file, .copied("[0:00] Hi there.\n[0:04] Bye.")).detail
                     .hasPrefix("interview.m4a: 3 words."), true, "timestamps aren't counted as words")

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
