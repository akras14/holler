import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import UniformTypeIdentifiers

/// Wires the pieces together: menu bar icon, key monitor, microphone, model, pill.
public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let statusMenu = StatusMenu(pasteboard: .general)
    private let indicator = Indicator()
    private let recorder = Recorder()
    private let transcriber = Transcriber()
    private let history = History()
    private let dictationKey = DictationKey()
    private lazy var keyMonitor = KeyMonitor(key: dictationKey)
    private lazy var dictation = Dictation(source: recorder, transcriber: transcriber, paster: Paster(), history: history)
    private lazy var files = FileTranscription(transcriber: transcriber)
    private var downloading = false
    private var error: String?
    private var permissionTimer: Timer?

    static let microphoneKey = "Microphone"

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.menu = statusMenu.menu
        statusMenu.menu.delegate = self
        statusMenu.onSelectMicrophone = { [weak self] uid in
            UserDefaults.standard.set(uid, forKey: Self.microphoneKey)
            self?.recorder.deviceUID = uid
            self?.refresh()
        }
        statusMenu.onOpenPermission = { permission in
            let pane = permission == .accessibility ? "Privacy_Accessibility" : "Privacy_Microphone"
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
        }
        statusMenu.onToggleLaunchAtLogin = { [weak self] in
            let service = SMAppService.mainApp
            do {
                if service.status == .enabled { try service.unregister() } else { try service.register() }
            } catch {
                self?.error = "Couldn't change Launch at Login: \(error.localizedDescription)"
            }
            self?.refresh()
        }

        statusMenu.onClearRecent = { [weak self] in
            self?.history.clear()
            self?.refresh()
        }

        statusMenu.onTranscribeFile = { [weak self] in self?.chooseFile() }
        files.onChange = { [weak self] in self?.refresh() }
        files.onFinish = { [weak self] file, outcome in self?.show(outcome, for: file) }

        recorder.deviceUID = UserDefaults.standard.string(forKey: Self.microphoneKey)
        recorder.onLevel = { [weak self] in self?.indicator.level($0) }
        dictationKey.onAction = { [weak self] in self?.dictation.handle($0) }
        dictation.onStateChange = { [weak self] state in
            if state == .recording { self?.error = nil }
            self?.indicator.update(state)
            self?.refresh()
        }
        dictation.onError = { [weak self] message in
            self?.error = message
            NSSound.beep()
            self?.refresh()
        }

        askForPermissions()
        loadModel()
        refresh()
    }

    private func loadModel() {
        downloading = !Transcriber.isModelDownloaded
        Task { @MainActor in
            do {
                try await dictation.loadModel()
            } catch {
                self.error = "Couldn't load the speech model: \(error.localizedDescription)"
            }
            downloading = false
            refresh()
        }
    }

    /// Asks once for each permission, then watches for the Accessibility grant, which
    /// macOS doesn't announce, so the key monitor can start as soon as it arrives.
    private func askForPermissions() {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in DispatchQueue.main.async { self.refresh() } }
        }
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        if AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary) {
            keyMonitor.start()
            return
        }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self, AXIsProcessTrusted() else { return }
            timer.invalidate()
            self.keyMonitor.start()
            self.refresh()
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "Transcribe File to Clipboard"
        panel.message = "Choose a recording or video. Its transcript is copied to the clipboard."
        panel.prompt = "Transcribe"
        panel.allowedContentTypes = [.audiovisualContent]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        // Holler has no windows, so it has to come forward for the panel to get focus.
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        files.start(url)
    }

    private func show(_ outcome: FileTranscription.Outcome, for file: URL) {
        let message = FileTranscription.message(for: file, outcome)
        let alert = NSAlert()
        alert.messageText = message.title
        alert.informativeText = message.detail
        guard case .copied(let text) = outcome else {
            alert.alertStyle = .warning
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return
        }
        alert.addButton(withTitle: "Done")
        alert.addButton(withTitle: "Save as Text File…")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertSecondButtonReturn else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = FileTranscription.textFileName(for: file)
        panel.directoryURL = file.deletingLastPathComponent()
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try FileTranscription.save(text, to: url)
        } catch {
            let failed = NSAlert(error: error)
            failed.messageText = "Couldn't save the transcript"
            failed.informativeText = "\(error.localizedDescription) It's still on the clipboard."
            failed.runModal()
        }
    }

    private var missingPermissions: [Permission] {
        var missing: [Permission] = []
        if !AXIsProcessTrusted() { missing.append(.accessibility) }
        if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized { missing.append(.microphone) }
        return missing
    }

    private func refresh() {
        var model = MenuModel()
        model.state = dictation.state
        model.downloading = downloading
        model.error = error
        model.missing = missingPermissions
        model.recent = history.items
        model.transcribingFile = files.file?.lastPathComponent
        model.microphones = Microphones.all()
        model.selectedMicrophone = recorder.deviceUID
        model.launchAtLogin = SMAppService.mainApp.status == .enabled
        statusMenu.model = model

        let symbol: String
        switch dictation.state {
        case .loading: symbol = "hourglass"
        case .ready where files.file != nil: symbol = "ellipsis"
        case .ready: symbol = model.missing.isEmpty && error == nil ? "waveform" : "exclamationmark.triangle"
        case .recording: symbol = "mic.fill"
        case .transcribing: symbol = "ellipsis"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Holler")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    /// Fresh device list and permission state every time the menu opens.
    public func menuNeedsUpdate(_ menu: NSMenu) { refresh() }
}
