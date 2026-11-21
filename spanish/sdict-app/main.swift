// SDict: menu-bar app for sdict. A global hotkey (⌃⌥S by default) looks up
// the clipboard in a floating window; Play buttons run ssay (Google voice, cached).
// All dictionary logic lives in ~/spanish-tools/sdict, called with --json.
import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI
import Translation

let home = FileManager.default.homeDirectoryForCurrentUser.path
let sdictPath = home + "/spanish-tools/sdict"
let ssayPath = home + "/spanish-tools/ssay"   // Google Chirp 3 HD (cached), falls back to macOS Paulina
let toolPath = "/usr/bin:/bin:/usr/sbin:/sbin:" + home + "/.local/bin"
let hotKeyChoices: [(letter: String, code: Int)] = [("S", kVK_ANSI_S), ("E", kVK_ANSI_E), ("P", kVK_ANSI_P)]

struct Sense: Decodable {
    let pos: String?
    let gloss: String
    let extra: String?
    let example: String?
}

struct Entry: Decodable {
    let word: String
    let reading: String?
    let common: Bool
    let note: String?
    let form: [String]
    let senses: [Sense]
    let more: Int
}

struct Piece: Decodable {
    let word: String
    let lemma: String?
    let gloss: String
    let form: String?
}

struct Lookup: Decodable {
    let query: String
    let note: String?
    let entries: [Entry]
    let more: Int
    let sentence: Bool?
    let source: String?
    let breakdown: [Piece]?
}

// Whole-sentence translation with Apple's on-device Translation framework (no network).
enum Translator {
    static func translate(_ text: String, from source: String) async -> (String?, String?) {
        let from = Locale.Language(identifier: source)
        let to = Locale.Language(identifier: source == "en" ? "es" : "en")
        let status = await LanguageAvailability().status(from: from, to: to)
        guard status == .installed else {
            return (nil, "Translation needs the Spanish language pack: System Settings → General → "
                + "Language & Region → Translation Languages → download Spanish.")
        }
        if #available(macOS 26.0, *) {
            do {
                let session = TranslationSession(installedSource: from, target: to)
                return (try await session.translate(text).targetText, nil)
            } catch {
                return (nil, "Translation failed: \(error.localizedDescription)")
            }
        }
        return (nil, "Sentence translation needs macOS 26 or later.")
    }
}

func makeProcess(_ path: String, _ args: [String]) -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = args
    var env = ProcessInfo.processInfo.environment
    env["PATH"] = toolPath
    env["LANG"] = "en_US.UTF-8"
    process.environment = env
    return process
}

// MARK: - Model

final class Model: ObservableObject {
    @Published var query = ""
    @Published var lookup: Lookup?
    @Published var error: String?
    @Published var searching = false
    @Published var playing: String?
    @Published var focusRequest = 0
    @Published var translation: String?
    @Published var translationError: String?
    @Published var translating = false
    private var generation = 0
    private var pending: DispatchWorkItem?

    // Search shortly after typing stops.
    func scheduleSearch(after delay: Double) {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.search() }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func search() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            lookup = nil
            error = nil
            translation = nil
            translationError = nil
            return
        }
        generation += 1
        let current = generation
        searching = true
        DispatchQueue.global(qos: .userInitiated).async {
            let process = makeProcess("/usr/bin/python3", ["-I", sdictPath, "--json", text])
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            var result: Lookup?
            var message: String?
            do {
                try process.run()
                let data = out.fileHandleForReading.readDataToEndOfFile()
                let errData = err.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                result = try? JSONDecoder().decode(Lookup.self, from: data)
                if result == nil {
                    let detail = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    message = detail.isEmpty ? "sdict returned nothing." : detail
                }
            } catch {
                message = "Couldn't run sdict: \(error.localizedDescription)"
            }
            DispatchQueue.main.async {
                guard current == self.generation else { return }
                self.searching = false
                self.lookup = result
                self.error = message
                self.translation = nil
                self.translationError = nil
                if let result, result.sentence == true {
                    self.translate(result.query, source: result.source ?? "es", generation: current)
                }
            }
        }
    }

    func translate(_ text: String, source: String, generation current: Int) {
        translating = true
        Task { @MainActor in
            let (text, problem) = await Translator.translate(text, from: source)
            guard current == self.generation else { return }
            self.translating = false
            self.translation = text
            self.translationError = problem
        }
    }

    func lookUpWord(_ word: String) {
        query = word
        search()
    }

    func play(_ word: String) {
        guard playing == nil else { return }
        let process = makeProcess("/usr/bin/python3", ["-I", ssayPath, word])
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in
            DispatchQueue.main.async { self.playing = nil }
        }
        do {
            try process.run()
            playing = word
        } catch {
            self.error = "Couldn't speak: \(error.localizedDescription)"
        }
    }
}

// MARK: - Views

struct EntryView: View {
    let entry: Entry
    @ObservedObject var model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.word).font(.system(size: 28, weight: .semibold))
                if let reading = entry.reading {
                    Text(reading).font(.system(size: 17)).foregroundStyle(.secondary)
                }
                if entry.common {
                    Text("common")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                }
                Spacer()
                Button { model.play(entry.word) } label: {
                    Image(systemName: model.playing == entry.word ? "speaker.wave.2.fill" : "play.fill")
                        .frame(width: 18)
                }
                .help("Hear it (Google voice, Latin American Spanish)")
                .disabled(model.playing != nil && model.playing != entry.word)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.word, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc").frame(width: 18)
                }
                .help("Copy word")
            }
            if let note = entry.note {
                Text(note).font(.callout).foregroundStyle(.secondary)
            }
            if !entry.form.isEmpty {
                Text("form: " + entry.form.joined(separator: " → ")).font(.callout).foregroundStyle(.secondary)
            }
            ForEach(Array(entry.senses.enumerated()), id: \.offset) { i, sense in
                if let pos = sense.pos {
                    Text(pos).font(.caption).foregroundStyle(.secondary).padding(.top, 2)
                }
                let number = Text("\(i + 1). ").foregroundStyle(.secondary)
                let extra = Text(sense.extra.map { "  (\($0))" } ?? "").foregroundStyle(.secondary)
                Text("\(number)\(sense.gloss)\(extra)")
                    .font(.system(size: 14))
                    .fixedSize(horizontal: false, vertical: true)
                if let example = sense.example {
                    Text(example)
                        .font(.system(size: 13))
                        .italic()
                        .foregroundStyle(.secondary)
                        .padding(.leading, 18)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if entry.more > 0 {
                Text("+ \(entry.more) more meanings (run sdict in Terminal)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .textSelection(.enabled)
    }
}

// Translation box + word-by-word breakdown for sentences.
struct SentenceView: View {
    let lookup: Lookup
    @ObservedObject var model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(lookup.source == "en" ? "Spanish" : "Translation")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    if lookup.source != "en" {
                        Button { model.play(lookup.query) } label: {
                            Image(systemName: model.playing == lookup.query ? "speaker.wave.2.fill" : "play.fill")
                        }
                        .help("Hear the Spanish sentence (Google voice)")
                        .disabled(model.playing != nil && model.playing != lookup.query)
                    }
                    if let t = model.translation {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(t, forType: .string)
                        } label: { Image(systemName: "doc.on.doc") }
                        .help("Copy translation")
                    }
                }
                if model.translating {
                    ProgressView().controlSize(.small)
                } else if let t = model.translation {
                    Text(t).font(.system(size: 19, weight: .medium)).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let problem = model.translationError {
                    Text(problem).font(.callout).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.08)))

            if let pieces = lookup.breakdown, !pieces.isEmpty {
                Text("Word by word").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Button { model.lookUpWord(piece.word) } label: {
                            Text(piece.word).font(.system(size: 15, weight: .semibold))
                        }
                        .buttonStyle(.link)
                        .help("Show the full entry")
                        if let lemma = piece.lemma {
                            Text("→ \(lemma)").font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                        Text(piece.gloss).font(.system(size: 14))
                            .fixedSize(horizontal: false, vertical: true)
                        if let form = piece.form {
                            Text(form).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .textSelection(.enabled)
    }
}

struct ContentView: View {
    @ObservedObject var model: Model
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Spanish word or sentence (en + English)", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20))
                    .focused($fieldFocused)
                    .onSubmit { model.scheduleSearch(after: 0.1) }
                    .onChange(of: model.query) { model.scheduleSearch(after: 0.35) }
                if model.searching {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 30)
            .padding(.bottom, 12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error = model.error {
                        Text(error).foregroundStyle(.red)
                    }
                    if let lookup = model.lookup {
                        if let note = lookup.note {
                            Text(note).foregroundStyle(.orange)
                        }
                        if lookup.sentence == true {
                            SentenceView(lookup: lookup, model: model)
                            if !lookup.entries.isEmpty { Divider() }
                        } else if lookup.entries.isEmpty {
                            Text("No match for “\(lookup.query)”.")
                        }
                        ForEach(Array(lookup.entries.enumerated()), id: \.offset) { i, entry in
                            if i > 0 { Divider() }
                            EntryView(entry: entry, model: model)
                        }
                        if lookup.more > 0 {
                            Text("\(lookup.more) more matches (run sdict in Terminal to see them)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else if !model.searching && model.error == nil {
                        Text("Type a Spanish word or sentence. English: type en first (en city, en where is the market).")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            Text("Type to search    ⌃⌥S: look up clipboard    ⌃⌥⇧S: new search    Esc: close")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
        }
        .frame(width: 480, height: 560)
        .onAppear { fieldFocused = true }
        .onChange(of: model.focusRequest) { fieldFocused = true }
    }
}

// MARK: - App

final class Panel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static var shared: AppDelegate!
    let model = Model()
    var panel: Panel!
    var statusItem: NSStatusItem!
    var hotKeyRef: EventHotKeyRef?
    var searchHotKeyRef: EventHotKeyRef?

    var hotKeyLetter: String {
        get { UserDefaults.standard.string(forKey: "hotKey") ?? "S" }
        set { UserDefaults.standard.set(newValue, forKey: "hotKey") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        panel = Panel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
                      styleMask: [.titled, .closable, .fullSizeContentView],
                      backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: ContentView(model: model))

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Ñ"

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            // id 1 = look up clipboard (⌃⌥S), id 2 = open an empty search window (⌃⌥⇧S)
            var hotKey = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
            let which = hotKey.id
            DispatchQueue.main.async {
                if which == 2 { AppDelegate.shared.menuOpen() } else { AppDelegate.shared.lookUpClipboard() }
            }
            return noErr
        }, 1, &spec, nil, nil)
        registerHotKey()

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == UInt16(kVK_Escape), event.window === self.panel else { return event }
            self.closePanel()
            return nil
        }
    }

    func registerHotKey() {
        for ref in [hotKeyRef, searchHotKeyRef].compactMap({ $0 }) { UnregisterEventHotKey(ref) }
        hotKeyRef = nil
        searchHotKeyRef = nil
        let code = hotKeyChoices.first { $0.letter == hotKeyLetter }?.code ?? kVK_ANSI_S
        let id = EventHotKeyID(signature: OSType(0x5344_4354), id: 1)  // "SDCT"
        let status = RegisterEventHotKey(UInt32(code), UInt32(controlKey | optionKey), id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        // Same letter + Shift opens an empty search window.
        let searchID = EventHotKeyID(signature: OSType(0x5344_4354), id: 2)
        let searchStatus = RegisterEventHotKey(UInt32(code), UInt32(controlKey | optionKey | shiftKey), searchID,
                                               GetApplicationEventTarget(), 0, &searchHotKeyRef)
        if status != noErr || searchStatus != noErr {
            let taken = status != noErr ? "⌃⌥\(hotKeyLetter)" : "⌃⌥⇧\(hotKeyLetter)"
            showAlert("\(taken) is already used by something else.",
                      "Pick another hotkey from the Ñ menu in the menu bar.")
        }
        rebuildMenu()
    }

    func rebuildMenu() {
        let menu = NSMenu()
        let lookUp = NSMenuItem(title: "Look Up Clipboard", action: #selector(menuLookUp), keyEquivalent: hotKeyLetter.lowercased())
        lookUp.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(lookUp)
        let open = NSMenuItem(title: "Open Search Window", action: #selector(menuOpen), keyEquivalent: hotKeyLetter.lowercased())
        open.keyEquivalentModifierMask = [.control, .option, .shift]
        menu.addItem(open)
        menu.addItem(.separator())
        let hotKeyItem = NSMenuItem(title: "Hotkey", action: nil, keyEquivalent: "")
        let hotKeyMenu = NSMenu()
        for choice in hotKeyChoices {
            let item = NSMenuItem(title: "⌃⌥" + choice.letter + "  (search: ⌃⌥⇧" + choice.letter + ")", action: #selector(menuHotKey(_:)), keyEquivalent: "")
            item.representedObject = choice.letter
            item.state = choice.letter == hotKeyLetter ? .on : .off
            item.target = self
            hotKeyMenu.addItem(item)
        }
        hotKeyItem.submenu = hotKeyMenu
        menu.addItem(hotKeyItem)
        let login = NSMenuItem(title: "Open at Login", action: #selector(menuLogin), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        for item in menu.items where item.action != nil {
            item.target = self
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit SDict", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func lookUpClipboard() {
        let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        model.query = String(text.prefix(400))
        model.search()
        showPanel()
    }

    func showPanel() {
        if !panel.isVisible {
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
            if let frame = screen?.visibleFrame {
                panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2,
                                             y: frame.midY - panel.frame.height / 2 + frame.height / 10))
            }
        }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        model.focusRequest += 1
    }

    func closePanel() {
        panel.orderOut(nil)
        NSApp.hide(nil)  // hand focus back to the previous app
    }

    func windowDidResignKey(_ notification: Notification) {
        panel.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.hide(nil)
    }

    func showAlert(_ title: String, _ detail: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.runModal()
    }

    @objc func menuLookUp() { lookUpClipboard() }

    @objc func menuOpen() {
        model.query = ""
        model.lookup = nil
        model.error = nil
        showPanel()
    }

    @objc func menuHotKey(_ sender: NSMenuItem) {
        guard let letter = sender.representedObject as? String else { return }
        hotKeyLetter = letter
        registerHotKey()
    }

    @objc func menuLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showAlert("Couldn't change the login setting.", error.localizedDescription)
        }
        rebuildMenu()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
