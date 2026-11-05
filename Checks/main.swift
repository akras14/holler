import AppKit

MainActor.assumeIsolated {
    _ = NSApplication.shared
    let t = Checker()
    pushToTalkChecks(t)
    pasterChecks(t)
    historyChecks(t)
    modelFolderChecks(t)
    transcriberChecks(t)

    print(t.failures == 0 ? "✔ \(t.count) checks passed" : "✘ \(t.failures) of \(t.count) checks failed")
    exit(t.failures == 0 ? 0 : 1)
}
