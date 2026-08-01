import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import Foundation
import ScreenCaptureKit

@_silgen_name("_AXUIElementGetWindow")
private func AXUIElementGetWindowID(
    _ element: AXUIElement,
    _ identifier: UnsafeMutablePointer<CGWindowID>
) -> AXError

struct Options {
    var runOnce = false
    var dryRun = false
    var copyOnly = false
    var verbose = false
    var activationDelay: TimeInterval = 0.7
    var pasteDelay: TimeInterval = 0.15
    var resultFile: String?
}

struct WindowInfo: CustomStringConvertible {
    let id: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    let title: String
    let bounds: CGRect

    var description: String {
        "#\(id) \(ownerName) — \(title.isEmpty ? "Untitled" : title)"
    }
}

struct FocusInfo {
    let element: AXUIElement
    let pid: pid_t
    let role: String
    let isTextInput: Bool
    let frame: CGRect?
    let windowID: CGWindowID?
}

enum AppsnapError: LocalizedError {
    case accessibilityPermission
    case screenRecordingPermission
    case noCurrentWindow
    case noBehindWindow
    case captureFailed(Int32)
    case pasteTargetUnavailable

    var errorDescription: String? {
        switch self {
        case .accessibilityPermission:
            return "Enable Appsnap in System Settings → Privacy & Security → Accessibility."
        case .screenRecordingPermission:
            return "Enable Appsnap in System Settings → Privacy & Security → Screen & System Audio Recording."
        case .noCurrentWindow:
            return "Could not find the current window."
        case .noBehindWindow:
            return "No normal window was found directly behind the current window."
        case .captureFailed(let status):
            return "Window capture failed with status \(status)."
        case .pasteTargetUnavailable:
            return "Screenshot copied, but no verified text cursor was available."
        }
    }
}

enum AppsnapHotKey {
    static let signature = OSType(
        UInt32(UInt8(ascii: "A")) << 24
            | UInt32(UInt8(ascii: "p")) << 16
            | UInt32(UInt8(ascii: "S")) << 8
            | UInt32(UInt8(ascii: "n"))
    )
    static let identifier = UInt32(1)
}

struct KeyboardShortcut: Equatable {
    static let defaultShortcut = KeyboardShortcut(
        keyCode: UInt32(kVK_ANSI_S),
        carbonModifiers: UInt32(optionKey | cmdKey)
    )

    private static let keyCodeDefaultsKey = "globalShortcutKeyCode"
    private static let modifiersDefaultsKey = "globalShortcutCarbonModifiers"

    let keyCode: UInt32
    let carbonModifiers: UInt32

    var isValid: Bool {
        keyCode <= UInt16.max && carbonModifiers != 0
    }

    static func load(from defaults: UserDefaults = .standard) -> KeyboardShortcut {
        guard defaults.object(forKey: keyCodeDefaultsKey) != nil,
              defaults.object(forKey: modifiersDefaultsKey) != nil
        else { return defaultShortcut }

        let shortcut = KeyboardShortcut(
            keyCode: UInt32(defaults.integer(forKey: keyCodeDefaultsKey)),
            carbonModifiers: UInt32(defaults.integer(forKey: modifiersDefaultsKey))
        )
        return shortcut.isValid ? shortcut : defaultShortcut
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(Int(keyCode), forKey: Self.keyCodeDefaultsKey)
        defaults.set(Int(carbonModifiers), forKey: Self.modifiersDefaultsKey)
    }

    var displayString: String {
        "\(modifierDisplayString)\(Self.keyDisplayString(for: keyCode))"
    }

    var menuModifierMask: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return flags
    }

    var menuKeyEquivalent: String {
        Self.menuKeyEquivalent(for: keyCode)
    }

    private var modifierDisplayString: String {
        var value = ""
        if carbonModifiers & UInt32(controlKey) != 0 { value += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { value += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { value += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { value += "⌘" }
        return value
    }

    private static func keyDisplayString(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Delete: return "Delete"
        case kVK_ForwardDelete: return "Forward Delete"
        case kVK_Escape: return "Escape"
        case kVK_Home: return "Home"
        case kVK_End: return "End"
        case kVK_PageUp: return "Page Up"
        case kVK_PageDown: return "Page Down"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_DownArrow: return "↓"
        case kVK_UpArrow: return "↑"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_F13: return "F13"
        case kVK_F14: return "F14"
        case kVK_F15: return "F15"
        case kVK_F16: return "F16"
        case kVK_F17: return "F17"
        case kVK_F18: return "F18"
        case kVK_F19: return "F19"
        case kVK_F20: return "F20"
        default: return "Key \(keyCode)"
        }
    }

    private static func menuKeyEquivalent(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "a"
        case kVK_ANSI_B: return "b"
        case kVK_ANSI_C: return "c"
        case kVK_ANSI_D: return "d"
        case kVK_ANSI_E: return "e"
        case kVK_ANSI_F: return "f"
        case kVK_ANSI_G: return "g"
        case kVK_ANSI_H: return "h"
        case kVK_ANSI_I: return "i"
        case kVK_ANSI_J: return "j"
        case kVK_ANSI_K: return "k"
        case kVK_ANSI_L: return "l"
        case kVK_ANSI_M: return "m"
        case kVK_ANSI_N: return "n"
        case kVK_ANSI_O: return "o"
        case kVK_ANSI_P: return "p"
        case kVK_ANSI_Q: return "q"
        case kVK_ANSI_R: return "r"
        case kVK_ANSI_S: return "s"
        case kVK_ANSI_T: return "t"
        case kVK_ANSI_U: return "u"
        case kVK_ANSI_V: return "v"
        case kVK_ANSI_W: return "w"
        case kVK_ANSI_X: return "x"
        case kVK_ANSI_Y: return "y"
        case kVK_ANSI_Z: return "z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Space: return " "
        default: return ""
        }
    }
}

@MainActor
final class ShortcutRecorderWindowController: NSWindowController {
    init(
        currentShortcut: KeyboardShortcut,
        onRecord: @escaping @MainActor (KeyboardShortcut) -> Void,
        onCancel: @escaping @MainActor () -> Void,
        onRestoreDefault: @escaping @MainActor () -> Void
    ) {
        let recorderView = ShortcutRecorderView(
            currentShortcut: currentShortcut,
            onRecord: onRecord,
            onCancel: onCancel,
            onRestoreDefault: onRestoreDefault
        )
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 170),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Set Appsnap Shortcut"
        panel.contentView = recorderView
        panel.isReleasedWhenClosed = false
        panel.center()
        super.init(window: panel)
        panel.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        guard let window, let recorderView = window.contentView as? ShortcutRecorderView else { return }
        window.makeKeyAndOrderFront(sender)
        window.makeFirstResponder(recorderView)
    }
}

extension ShortcutRecorderWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        (window?.contentView as? ShortcutRecorderView)?.cancel()
    }
}

@MainActor
final class ShortcutRecorderView: NSView {
    private let statusLabel = NSTextField(labelWithString: "")
    private let onRecord: @MainActor (KeyboardShortcut) -> Void
    private let onCancel: @MainActor () -> Void
    private let onRestoreDefault: @MainActor () -> Void
    private var didFinish = false

    init(
        currentShortcut: KeyboardShortcut,
        onRecord: @escaping @MainActor (KeyboardShortcut) -> Void,
        onCancel: @escaping @MainActor () -> Void,
        onRestoreDefault: @escaping @MainActor () -> Void
    ) {
        self.onRecord = onRecord
        self.onCancel = onCancel
        self.onRestoreDefault = onRestoreDefault
        super.init(frame: .zero)
        buildView(currentShortcut: currentShortcut)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape {
            cancel()
            return
        }

        if Int(event.keyCode) == kVK_Delete, carbonModifiers(from: event.modifierFlags) == 0 {
            finish()
            onRestoreDefault()
            return
        }

        let modifiers = carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0, !Self.isModifierKeyCode(Int(event.keyCode)) else {
            statusLabel.stringValue = "Press at least one modifier plus one regular key."
            NSSound.beep()
            return
        }

        finish()
        onRecord(KeyboardShortcut(
            keyCode: UInt32(event.keyCode),
            carbonModifiers: modifiers
        ))
    }

    func cancel() {
        guard !didFinish else { return }
        finish()
        onCancel()
    }

    private func buildView(currentShortcut: KeyboardShortcut) {
        let titleLabel = NSTextField(labelWithString: "Press the new global shortcut")
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.alignment = .center

        let detailLabel = NSTextField(labelWithString: "Use at least one modifier and one non-modifier key.")
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.alignment = .center

        statusLabel.stringValue = "Current: \(currentShortcut.displayString)"
        statusLabel.font = .monospacedSystemFont(ofSize: 18, weight: .medium)
        statusLabel.alignment = .center

        let deleteLabel = NSTextField(labelWithString: "Escape cancels. Delete restores ⌥⌘S.")
        deleteLabel.font = .systemFont(ofSize: 11)
        deleteLabel.textColor = .tertiaryLabelColor
        deleteLabel.alignment = .center

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelButtonPressed))
        cancelButton.bezelStyle = .rounded

        let defaultButton = NSButton(title: "Restore Default", target: self, action: #selector(defaultButtonPressed))
        defaultButton.bezelStyle = .rounded

        let buttonStack = NSStackView(views: [defaultButton, cancelButton])
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 8

        let stack = NSStackView(views: [titleLabel, detailLabel, statusLabel, deleteLabel, buttonStack])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @objc private func cancelButtonPressed() {
        cancel()
    }

    @objc private func defaultButtonPressed() {
        finish()
        onRestoreDefault()
    }

    private func finish() {
        didFinish = true
        window?.close()
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers = UInt32(0)
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }

    private static func isModifierKeyCode(_ keyCode: Int) -> Bool {
        switch keyCode {
        case kVK_Command, kVK_Shift, kVK_CapsLock, kVK_Option, kVK_Control,
             kVK_RightShift, kVK_RightOption, kVK_RightControl, kVK_Function:
            return true
        default:
            return false
        }
    }
}

@main
final class Appsnap: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var runMenuItem: NSMenuItem?
    private var shortcutMenuItem: NSMenuItem?
    private var shortcutRecorder: ShortcutRecorderWindowController?
    private var shortcut = KeyboardShortcut.load()
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var isRunningCapture = false

    static func main() async {
        let options = parseOptions()
        if options.runOnce {
            await runOnce(options: options)
            return
        }

        await MainActor.run {
            let app = NSApplication.shared
            let delegate = Appsnap()
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            withExtendedLifetime(delegate) {
                app.run()
            }
        }
    }

    static func runOnce(options: Options) async {
        let watchdog = Task.detached(priority: .background) {
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            if !Task.isCancelled { _exit(124) }
        }
        defer { watchdog.cancel() }

        do {
            let result = try await run(options: options)
            print(result)
            writeResult(result, to: options.resultFile)
        } catch {
            let result = "Appsnap: \(error.localizedDescription)"
            writeResult(result, to: options.resultFile)
            fputs("\(result)\n", stderr)
            exit(1)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            setupStatusMenu()
        }
        guard installHotKeyHandler() else { return }
        let registrationStatus = registerHotKey(shortcut)
        if registrationStatus != noErr, shortcut != .defaultShortcut {
            fputs("Appsnap: \(shortcut.displayString) registration failed with status \(registrationStatus); trying default shortcut.\n", stderr)
            shortcut = .defaultShortcut
            shortcut.save()
            let defaultStatus = registerHotKey(shortcut)
            if defaultStatus != noErr {
                fputs("Appsnap: Option-Command-S registration failed with status \(defaultStatus).\n", stderr)
            }
            Task { @MainActor in
                updateShortcutMenuItems()
            }
        } else if registrationStatus != noErr {
            fputs("Appsnap: Option-Command-S registration failed with status \(registrationStatus).\n", stderr)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    @MainActor
    private func setupStatusMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "rectangle.on.rectangle",
                accessibilityDescription: "Appsnap"
            )
            button.image?.isTemplate = true
            button.toolTip = "Appsnap"
        }

        let menu = NSMenu()
        let runItem = NSMenuItem(
            title: "Run Appsnap",
            action: #selector(runFromMenu),
            keyEquivalent: shortcut.menuKeyEquivalent
        )
        runItem.keyEquivalentModifierMask = shortcut.menuModifierMask
        runItem.target = self
        menu.addItem(runItem)
        let shortcutItem = NSMenuItem(
            title: "Global Shortcut: \(shortcut.displayString)",
            action: #selector(openShortcutRecorder),
            keyEquivalent: ""
        )
        shortcutItem.target = self
        menu.addItem(shortcutItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(
            title: "Open Accessibility Settings",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: "Open Screen Recording Settings",
            action: #selector(openScreenRecordingSettings),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(
            title: "Quit Appsnap",
            action: #selector(quit),
            keyEquivalent: "q"
        ))
        for menuItem in menu.items {
            menuItem.target = self
        }
        item.menu = menu
        statusItem = item
        runMenuItem = runItem
        shortcutMenuItem = shortcutItem
    }

    @MainActor
    private func updateShortcutMenuItems() {
        runMenuItem?.keyEquivalent = shortcut.menuKeyEquivalent
        runMenuItem?.keyEquivalentModifierMask = shortcut.menuModifierMask
        shortcutMenuItem?.title = "Global Shortcut: \(shortcut.displayString)"
    }

    private func installHotKeyHandler() -> Bool {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let handler: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }

            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr, hotKeyID.id == AppsnapHotKey.identifier else {
                return noErr
            }

            let rawPointer = UInt(bitPattern: userData)
            Task { @MainActor in
                let pointer = UnsafeRawPointer(bitPattern: rawPointer)!
                let appsnap = Unmanaged<Appsnap>.fromOpaque(pointer).takeUnretainedValue()
                appsnap.runCapture()
            }
            return noErr
        }

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            selfPointer,
            &eventHandlerRef
        )
        guard installStatus == noErr else {
            fputs("Appsnap: hotkey handler registration failed with status \(installStatus).\n", stderr)
            return false
        }
        return true
    }

    private func registerHotKey(_ shortcut: KeyboardShortcut) -> OSStatus {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        let hotKeyID = EventHotKeyID(
            signature: AppsnapHotKey.signature,
            id: AppsnapHotKey.identifier
        )
        let registerStatus = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if registerStatus == noErr {
            print("Appsnap: global hotkey \(shortcut.displayString) registered.")
            fflush(stdout)
        }
        return registerStatus
    }

    @objc @MainActor private func runFromMenu() {
        runCapture()
    }

    @objc @MainActor private func openShortcutRecorder() {
        shortcutRecorder = ShortcutRecorderWindowController(
            currentShortcut: shortcut,
            onRecord: { [weak self] newShortcut in
                self?.applyShortcut(newShortcut)
            },
            onCancel: { [weak self] in
                self?.shortcutRecorder = nil
            },
            onRestoreDefault: { [weak self] in
                self?.applyShortcut(.defaultShortcut)
            }
        )
        shortcutRecorder?.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @MainActor
    private func applyShortcut(_ newShortcut: KeyboardShortcut) {
        shortcutRecorder = nil
        guard newShortcut != shortcut else { return }

        let previousShortcut = shortcut
        let status = registerHotKey(newShortcut)
        guard status == noErr else {
            let restoreStatus = registerHotKey(previousShortcut)
            showShortcutRegistrationAlert(
                shortcut: newShortcut,
                status: status,
                previousShortcut: previousShortcut,
                restoreStatus: restoreStatus
            )
            return
        }

        shortcut = newShortcut
        shortcut.save()
        updateShortcutMenuItems()
    }

    @MainActor
    private func showShortcutRegistrationAlert(
        shortcut: KeyboardShortcut,
        status: OSStatus,
        previousShortcut: KeyboardShortcut,
        restoreStatus: OSStatus
    ) {
        let alert = NSAlert()
        alert.messageText = "Shortcut Not Available"
        if restoreStatus == noErr {
            alert.informativeText = """
            Appsnap could not register \(shortcut.displayString). It may already be used by another app or by macOS.

            The previous shortcut, \(previousShortcut.displayString), is still active.
            Carbon status: \(status)
            """
        } else {
            alert.informativeText = """
            Appsnap could not register \(shortcut.displayString), and macOS also rejected the previous shortcut \(previousShortcut.displayString).

            Open the shortcut recorder and choose another shortcut.
            Carbon status: \(status), restore status: \(restoreStatus)
            """
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @MainActor
    private func runCapture() {
        guard !isRunningCapture else { return }
        isRunningCapture = true
        Task {
            do {
                let result = try await Self.run(options: Options())
                print(result)
            } catch {
                fputs("Appsnap: \(error.localizedDescription)\n", stderr)
            }
            await MainActor.run {
                self.isRunningCapture = false
            }
        }
    }

    @objc @MainActor private func openAccessibilitySettings() {
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    @objc @MainActor private func openScreenRecordingSettings() {
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    @MainActor
    private func openSettings(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc @MainActor private func quit() {
        NSApplication.shared.terminate(nil)
    }

    static func writeResult(_ result: String, to path: String?) {
        guard let path else { return }
        try? result.write(toFile: path, atomically: true, encoding: .utf8)
    }

    static func run(options: Options) async throws -> String {
        let accessibilityOptions = [
            "AXTrustedCheckOptionPrompt": true,
        ] as CFDictionary
        guard AXIsProcessTrustedWithOptions(accessibilityOptions) else {
            throw AppsnapError.accessibilityPermission
        }
        if !options.dryRun, !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
            throw AppsnapError.screenRecordingPermission
        }

        let windows = WindowInspector.normalWindows(excludingPID: getpid())
        guard let current = windows.first else {
            throw AppsnapError.noCurrentWindow
        }
        guard windows.count > 1 else {
            throw AppsnapError.noBehindWindow
        }
        let behind = windows[1]
        FocusInspector.enableEnhancedAccessibility(for: current.ownerPID)
        await pause(0.05)
        let initialFocus = FocusInspector.currentFocus()
        let currentHasTextCursor = initialFocus.map {
            $0.isTextInput && FocusInspector.belongsToWindow($0, window: current)
        } ?? false

        if options.verbose {
            print("Current: \(current)")
            print("Behind: \(behind)")
            print("Focus: \(initialFocus?.role ?? "none") text=\(currentHasTextCursor)")
        }

        if options.dryRun {
            if currentHasTextCursor {
                return "Would capture \(behind.ownerName) and paste into \(current.ownerName)."
            }
            return "Would capture \(current.ownerName), activate \(behind.ownerName), and paste only after verifying its cursor."
        }

        if currentHasTextCursor {
            try await Capturer.copyWindowToClipboard(behind.id)
            if options.copyOnly {
                return "Captured \(behind.ownerName) to the clipboard."
            }

            guard WindowInspector.frontmostWindow()?.id == current.id,
                  let focus = FocusInspector.currentFocus(),
                  focus.isTextInput,
                  FocusInspector.belongsToWindow(focus, window: current)
            else {
                throw AppsnapError.pasteTargetUnavailable
            }

            await pause(options.pasteDelay)
            try Paster.commandV()
            return "Pasted \(behind.ownerName) into \(current.ownerName)."
        }

        try await Capturer.copyWindowToClipboard(current.id)
        if options.copyOnly {
            return "Captured \(current.ownerName) to the clipboard."
        }

        let activated = WindowActivator.activate(behind)
        if activated {
            await pause(options.activationDelay)
            if WindowInspector.frontmostWindow()?.id == behind.id,
               let focus = FocusInspector.currentFocus(),
               focus.isTextInput,
               FocusInspector.belongsToWindow(focus, window: behind)
            {
                await pause(options.pasteDelay)
                try Paster.commandV()
                return "Pasted \(current.ownerName) into \(behind.ownerName)."
            }
        }

        _ = WindowActivator.activate(current)
        throw AppsnapError.pasteTargetUnavailable
    }

    static func pause(_ seconds: TimeInterval) async {
        try? await Task.sleep(
            nanoseconds: UInt64(max(0, seconds) * 1_000_000_000)
        )
    }

    static func parseOptions() -> Options {
        var options = Options()
        var iterator = CommandLine.arguments.dropFirst().makeIterator()

        while let argument = iterator.next() {
            switch argument {
            case "--run-once": options.runOnce = true
            case "--dry-run":
                options.runOnce = true
                options.dryRun = true
            case "--copy-only":
                options.runOnce = true
                options.copyOnly = true
            case "--verbose", "-v":
                options.runOnce = true
                options.verbose = true
            case "--activation-delay":
                options.runOnce = true
                if let value = iterator.next(), let delay = Double(value) {
                    options.activationDelay = max(0, delay)
                }
            case "--paste-delay":
                options.runOnce = true
                if let value = iterator.next(), let delay = Double(value) {
                    options.pasteDelay = max(0, delay)
                }
            case "--result-file":
                options.runOnce = true
                options.resultFile = iterator.next()
            case "--help", "-h":
                print("""
                Usage: appsnap [options]
                  --run-once                   Run capture once and exit
                  --dry-run                    Inspect without capturing or pasting
                  --copy-only                  Capture without changing focus or pasting
                  --activation-delay SECONDS   Wait after activating the behind window
                  --paste-delay SECONDS        Wait before Command-V
                  --result-file PATH           Write final status for a launcher
                  --verbose, -v                 Print diagnostics
                """)
                exit(0)
            default:
                break
            }
        }

        return options
    }
}

enum FocusInspector {
    private static let textRoles: Set<String> = [
        kAXTextFieldRole,
        kAXTextAreaRole,
        kAXComboBoxRole,
        "AXSearchField",
    ]
    private static let containerRoles: Set<String> = [
        kAXApplicationRole,
        kAXGroupRole,
        kAXScrollAreaRole,
        kAXWindowRole,
        "AXLayoutArea",
        "AXWebArea",
    ]

    static func enableEnhancedAccessibility(for pid: pid_t) {
        let application = AXUIElementCreateApplication(pid)
        for attribute in ["AXManualAccessibility", "AXEnhancedUserInterface"] {
            _ = AXUIElementSetAttributeValue(
                application,
                attribute as CFString,
                kCFBooleanTrue
            )
        }
    }

    static func currentFocus() -> FocusInfo? {
        let system = AXUIElementCreateSystemWide()
        guard let element = elementAttribute(system, kAXFocusedUIElementAttribute) else {
            return nil
        }

        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }

        let role = stringAttribute(element, kAXRoleAttribute) ?? ""
        let subrole = stringAttribute(element, kAXSubroleAttribute) ?? ""
        let roleDescription = (stringAttribute(element, kAXRoleDescriptionAttribute) ?? "").lowercased()
        let names = attributeNames(element)
        let selectedRange = names.contains(kAXSelectedTextRangeAttribute)
        let hasValue = names.contains(kAXValueAttribute)
        let focused = boolAttribute(element, kAXFocusedAttribute) == true
        let editable = boolAttribute(element, "AXEditable") == true
        let explicitRole = textRoles.contains(role)
            || textRoles.contains(subrole)
            || roleDescription.contains("text field")
            || roleDescription.contains("text area")
            || roleDescription.contains("search field")
        let selectedRangeEditor = selectedRange
            && hasValue
            && focused
            && !containerRoles.contains(role)
            && !containerRoles.contains(subrole)
        let isTextInput = explicitRole || (editable && focused) || selectedRangeEditor

        return FocusInfo(
            element: element,
            pid: pid,
            role: role,
            isTextInput: isTextInput,
            frame: frame(of: element),
            windowID: windowID(of: element)
        )
    }

    static func belongsToWindow(_ focus: FocusInfo, window: WindowInfo) -> Bool {
        if let focusedWindowID = focus.windowID {
            return focusedWindowID == window.id
        }
        guard process(focus.pid, belongsToOwner: window.ownerPID) else {
            return false
        }

        if let frame = focus.frame {
            let expanded = window.bounds.insetBy(dx: -4, dy: -4)
            return expanded.contains(CGPoint(x: frame.midX, y: frame.midY))
        }
        return true
    }

    private static func process(_ focusPID: pid_t, belongsToOwner ownerPID: pid_t) -> Bool {
        if focusPID == ownerPID { return true }
        guard let owner = NSRunningApplication(processIdentifier: ownerPID),
              let focus = NSRunningApplication(processIdentifier: focusPID)
        else { return false }

        if let ownerBundleID = owner.bundleIdentifier,
           let focusBundleID = focus.bundleIdentifier,
           (focusBundleID == ownerBundleID || focusBundleID.hasPrefix(ownerBundleID + "."))
        {
            return true
        }

        guard let ownerRoot = owner.bundleURL?.standardizedFileURL.path,
              let focusExecutable = focus.executableURL?.standardizedFileURL.path
        else { return false }
        return focusExecutable.hasPrefix(ownerRoot + "/Contents/")
    }

    static func windowID(of element: AXUIElement) -> CGWindowID? {
        var identifier = CGWindowID.zero
        guard AXUIElementGetWindowID(element, &identifier) == .success,
              identifier != 0
        else { return nil }
        return identifier
    }

    static func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value
        else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    static func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? Bool
    }

    static func numberAttribute(_ element: AXUIElement, _ attribute: String) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return (value as? NSNumber)?.intValue
    }

    static func attributeNames(_ element: AXUIElement) -> Set<String> {
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(element, &names) == .success,
              let values = names as? [String]
        else { return [] }
        return Set(values)
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard let position = pointAttribute(element, kAXPositionAttribute),
              let size = sizeAttribute(element, kAXSizeAttribute)
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    private static func pointAttribute(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard
              AXValueGetType(axValue) == .cgPoint
        else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
    }

    private static func sizeAttribute(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard
              AXValueGetType(axValue) == .cgSize
        else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
    }
}

enum WindowInspector {
    static func normalWindows(excludingPID: pid_t) -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let rawWindows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return rawWindows.compactMap { raw in
            guard number(raw[kCGWindowLayer as String]) == 0,
                  number(raw[kCGWindowAlpha as String]) > 0,
                  let idNumber = raw[kCGWindowNumber as String] as? NSNumber,
                  let pidNumber = raw[kCGWindowOwnerPID as String] as? NSNumber,
                  let boundsDictionary = raw[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
            else { return nil }

            let pid = pidNumber.int32Value
            guard pid != excludingPID,
                  bounds.width >= 120,
                  bounds.height >= 80,
                  let application = NSRunningApplication(processIdentifier: pid),
                  application.activationPolicy == .regular
            else { return nil }

            return WindowInfo(
                id: CGWindowID(idNumber.uint32Value),
                ownerPID: pid,
                ownerName: raw[kCGWindowOwnerName as String] as? String ?? "Unknown",
                title: raw[kCGWindowName as String] as? String ?? "",
                bounds: bounds
            )
        }
    }

    static func frontmostWindow() -> WindowInfo? {
        normalWindows(excludingPID: getpid()).first
    }

    private static func number(_ value: Any?) -> Double {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) ?? 0 }
        return 0
    }
}

enum WindowActivator {
    static func activate(_ window: WindowInfo) -> Bool {
        guard let application = NSRunningApplication(processIdentifier: window.ownerPID) else {
            return false
        }

        _ = application.activate(options: [.activateIgnoringOtherApps])
        FocusInspector.enableEnhancedAccessibility(for: window.ownerPID)
        Thread.sleep(forTimeInterval: 0.12)

        let appElement = AXUIElementCreateApplication(window.ownerPID)
        if let exactWindow = matchingWindow(in: appElement, expected: window) {
            _ = AXUIElementPerformAction(exactWindow, kAXRaiseAction as CFString)
            _ = AXUIElementSetAttributeValue(
                appElement,
                kAXFocusedWindowAttribute as CFString,
                exactWindow
            )
        }

        Thread.sleep(forTimeInterval: 0.18)
        return WindowInspector.frontmostWindow()?.id == window.id
    }

    private static func matchingWindow(in app: AXUIElement, expected: WindowInfo) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement]
        else { return nil }

        let identifierMatches = windows.filter {
            FocusInspector.windowID(of: $0) == expected.id
        }
        if identifierMatches.count == 1 { return identifierMatches[0] }

        let numberMatches = windows.filter {
            FocusInspector.numberAttribute($0, "AXWindowNumber") == Int(expected.id)
        }
        if numberMatches.count == 1 { return numberMatches[0] }

        let geometryMatches = windows.filter {
            guard let frame = FocusInspector.frame(of: $0) else { return false }
            return approximatelyEqual(frame, expected.bounds)
        }
        if geometryMatches.count == 1 { return geometryMatches[0] }

        if geometryMatches.count > 1, !expected.title.isEmpty {
            let titleMatches = geometryMatches.filter {
                FocusInspector.stringAttribute($0, kAXTitleAttribute) == expected.title
            }
            if titleMatches.count == 1 { return titleMatches[0] }
        }

        return nil
    }

    private static func approximatelyEqual(_ first: CGRect, _ second: CGRect) -> Bool {
        let tolerance: CGFloat = 4
        return abs(first.minX - second.minX) <= tolerance
            && abs(first.minY - second.minY) <= tolerance
            && abs(first.width - second.width) <= tolerance
            && abs(first.height - second.height) <= tolerance
    }
}

enum Capturer {
    static func copyWindowToClipboard(_ id: CGWindowID) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard let window = content.windows.first(where: { $0.windowID == id }) else {
            throw AppsnapError.captureFailed(1)
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.showsCursor = false
        configuration.width = max(1, Int(window.frame.width))
        configuration.height = max(1, Int(window.frame.height))

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        let representation = NSBitmapImageRep(cgImage: image)
        guard let png = representation.representation(using: .png, properties: [:]) else {
            throw AppsnapError.captureFailed(1)
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setData(png, forType: .png) else {
            throw AppsnapError.captureFailed(1)
        }
    }
}

enum Paster {
    static func commandV() throws {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        else {
            throw AppsnapError.pasteTargetUnavailable
        }

        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
