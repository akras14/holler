import AppKit
import HollerKit

MainActor.assumeIsolated {
    _ = NSApplication.shared
    let t = Checker()
    pushToTalkChecks(t)
    pasterChecks(t)
    historyChecks(t)
    microphoneChecks(t)
    modelFolderChecks(t)
    let transcriber = Transcriber()
    transcriberChecks(t, transcriber: transcriber)
    recorderChecks(t, transcriber: transcriber)

    print(t.failures == 0 ? "✔ \(t.count) checks passed" : "✘ \(t.failures) of \(t.count) checks failed")
    exit(t.failures == 0 ? 0 : 1)
}
