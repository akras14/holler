import AppKit
import HollerKit

MainActor.assumeIsolated {
    _ = NSApplication.shared
    let args = CommandLine.arguments
    if args.count >= 3, args[1] == "--snapshot-indicator" {
        snapshotIndicator(to: URL(fileURLWithPath: args[2]))
        exit(0)
    }
    let t = Checker()
    dictationKeyChecks(t)
    keyMonitorChecks(t)
    pasterChecks(t)
    historyChecks(t)
    microphoneChecks(t)
    indicatorChecks(t)
    menuChecks(t)
    modelFolderChecks(t)
    let transcriber = Transcriber()
    transcriberChecks(t, transcriber: transcriber)
    fileTranscriptionChecks(t, transcriber: transcriber)
    recorderChecks(t, transcriber: transcriber)
    dictationChecks(t, transcriber: transcriber)

    print(t.failures == 0 ? "✔ \(t.count) checks passed" : "✘ \(t.failures) of \(t.count) checks failed")
    exit(t.failures == 0 ? 0 : 1)
}
