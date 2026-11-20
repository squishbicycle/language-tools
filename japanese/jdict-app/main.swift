// JDict: menu-bar app for jdict. A global hotkey (⌃⌥K by default) looks up
// the clipboard in a floating window; Play buttons run jsay. All dictionary
// logic lives in ~/japanese-tools/jdict, called with --json.
import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

let home = FileManager.default.homeDirectoryForCurrentUser.path
let jdictPath = home + "/japanese-tools/jdict"
let jsayPath = home + "/japanese-tools/jsay"
let toolPath = "/usr/bin:/bin:/usr/sbin:/sbin:" + home + "/.local/bin"
let hotKeyChoices: [(letter: String, code: Int)] = [("K", kVK_ANSI_K), ("D", kVK_ANSI_D), ("L", kVK_ANSI_L)]

struct Sense: Decodable {
    let pos: String?
    let gloss: String
    let extra: String?
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

struct Lookup: Decodable {
    let query: String
    let note: String?
    let entries: [Entry]
    let more: Int
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
    private var generation = 0
    private var pending: DispatchWorkItem?

    // Search shortly after typing stops, so a Return that only confirms
    // Japanese input (IME) doesn't search half-typed text like "だんj".
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
            return
        }
        generation += 1
        let current = generation
        searching = true
        DispatchQueue.global(qos: .userInitiated).async {
            let process = makeProcess("/usr/bin/python3", ["-I", jdictPath, "--json", text])
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
                    message = detail.isEmpty ? "jdict returned nothing." : detail
                }
            } catch {
                message = "Couldn't run jdict: \(error.localizedDescription)"
            }
            DispatchQueue.main.async {
                guard current == self.generation else { return }
                self.searching = false
                self.lookup = result
                self.error = message
            }
        }
    }

    func play(_ word: String) {
        guard playing == nil else { return }
        let process = makeProcess(jsayPath, [word])
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in
            DispatchQueue.main.async { self.playing = nil }
        }
        do {
            try process.run()
            playing = word
        } catch {
            self.error = "Couldn't run jsay: \(error.localizedDescription)"
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
                .help("Play audio (jsay)")
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
            }
            if entry.more > 0 {
                Text("+ \(entry.more) more meanings (run jdict in Terminal)").font(.caption).foregroundStyle(.secondary)
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
                TextField("Japanese or English", text: $model.query)
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
                        if lookup.entries.isEmpty {
                            Text("No match for 「\(lookup.query)」.")
                            Text("For a whole sentence, select it, then right-click → Translate.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Array(lookup.entries.enumerated()), id: \.offset) { i, entry in
                            if i > 0 { Divider() }
                            EntryView(entry: entry, model: model)
                        }
                        if lookup.more > 0 {
                            Text("\(lookup.more) more matches (run jdict in Terminal to see them)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else if !model.searching && model.error == nil {
                        Text("Type a Japanese or English word.").foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            Text("Type to search    Esc: close")
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

    var hotKeyLetter: String {
        get { UserDefaults.standard.string(forKey: "hotKey") ?? "K" }
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
        statusItem.button?.title = "辞"

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { AppDelegate.shared.lookUpClipboard() }
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
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        let code = hotKeyChoices.first { $0.letter == hotKeyLetter }?.code ?? kVK_ANSI_K
        let id = EventHotKeyID(signature: OSType(0x4A44_4354), id: 1)  // "JDCT"
        let status = RegisterEventHotKey(UInt32(code), UInt32(controlKey | optionKey), id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            showAlert("⌃⌥\(hotKeyLetter) is already used by something else.",
                      "Pick another hotkey from the 辞 menu in the menu bar.")
        }
        rebuildMenu()
    }

    func rebuildMenu() {
        let menu = NSMenu()
        let lookUp = NSMenuItem(title: "Look Up Clipboard", action: #selector(menuLookUp), keyEquivalent: hotKeyLetter.lowercased())
        lookUp.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(lookUp)
        menu.addItem(NSMenuItem(title: "Open Search Window", action: #selector(menuOpen), keyEquivalent: ""))
        menu.addItem(.separator())
        let hotKeyItem = NSMenuItem(title: "Hotkey", action: nil, keyEquivalent: "")
        let hotKeyMenu = NSMenu()
        for choice in hotKeyChoices {
            let item = NSMenuItem(title: "⌃⌥" + choice.letter, action: #selector(menuHotKey(_:)), keyEquivalent: "")
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
        menu.addItem(NSMenuItem(title: "Quit JDict", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func lookUpClipboard() {
        let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        model.query = String(text.prefix(40))
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
