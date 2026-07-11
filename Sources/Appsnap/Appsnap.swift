import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct Options {
    var dryRun = false
    var copyOnly = false
    var verbose = false
    var pasteDelay: TimeInterval = 0.4
    var candidateDelay: TimeInterval = 0.35
    var maxCandidates = 3
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

enum AppsnapError: LocalizedError {
    case accessibilityPermission
    case screenRecordingPermission
    case noFocusedElement
    case noCaptureWindow
    case captureFailed(Int32)
    case pasteTargetUnavailable

    var errorDescription: String? {
        switch self {
        case .accessibilityPermission:
            return "Accessibility permission is required. Enable Appsnap's launcher (Raycast or Terminal) in System Settings → Privacy & Security → Accessibility."
        case .screenRecordingPermission:
            return "Screen Recording permission is required. Enable Appsnap's launcher (Raycast or Terminal) in System Settings → Privacy & Security → Screen & System Audio Recording."
        case .noFocusedElement:
            return "Could not inspect the currently focused element."
        case .noCaptureWindow:
            return "No useful window was available to capture."
        case .captureFailed(let status):
            return "Window capture failed with status \(status)."
        case .pasteTargetUnavailable:
            return "Screenshot copied. Focus a text field and press Command-V."
        }
    }
}

@main
struct Appsnap {
    static func main() {
        let options = parseOptions()

        do {
            let result = try run(options: options)
            print(result)
        } catch {
            fputs("Appsnap: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    static func run(options: Options) throws -> String {
        guard AXIsProcessTrusted() else {
            throw AppsnapError.accessibilityPermission
        }

        guard options.dryRun || CGPreflightScreenCaptureAccess() else {
            throw AppsnapError.screenRecordingPermission
        }

        let originalFocus = FocusInspector.currentFocus()
        let windows = WindowInspector.normalWindows(excludingPID: getpid())

        if options.verbose {
            print("Focused app: \(originalFocus?.appName ?? "none")")
            print("Focused role: \(originalFocus?.role ?? "none")")
            for (index, window) in windows.enumerated() {
                print("[\(index)] \(window)")
            }
        }

        if let focus = originalFocus, focus.isTextInput {
            guard let currentIndex = windows.firstIndex(where: { $0.ownerPID == focus.pid }),
                  let captureWindow = windows.dropFirst(currentIndex + 1).first
            else {
                throw AppsnapError.noCaptureWindow
            }

            if options.dryRun {
                return "Would capture behind: \(captureWindow); then paste into \(focus.appName) [\(focus.role)]"
            }

            try Capturer.copyWindowToClipboard(captureWindow.id)

            if options.copyOnly {
                return "Captured \(captureWindow.ownerName) to clipboard."
            }

            guard FocusInspector.currentFocus()?.matchesTextTarget(focus) == true else {
                throw AppsnapError.pasteTargetUnavailable
            }

            Thread.sleep(forTimeInterval: options.pasteDelay)
            Paster.commandV()
            return "Captured \(captureWindow.ownerName) and pasted into \(focus.appName)."
        }

        guard let captureWindow = windows.first else {
            throw AppsnapError.noCaptureWindow
        }

        if options.dryRun {
            let candidates = windows.dropFirst().prefix(options.maxCandidates)
            let names = candidates.map(\.ownerName).joined(separator: ", ")
            return "Would capture current: \(captureWindow); then inspect up to \(options.maxCandidates) window(s): \(names)"
        }

        try Capturer.copyWindowToClipboard(captureWindow.id)

        if options.copyOnly {
            return "Captured \(captureWindow.ownerName) to clipboard."
        }

        var visitedPIDs = Set<pid_t>()
        visitedPIDs.insert(captureWindow.ownerPID)
        var attempts = 0

        for candidate in windows.dropFirst() {
            guard attempts < options.maxCandidates else { break }
            guard visitedPIDs.insert(candidate.ownerPID).inserted else { continue }
            guard let app = NSRunningApplication(processIdentifier: candidate.ownerPID) else { continue }

            attempts += 1
            app.activate(options: [.activateAllWindows])
            Thread.sleep(forTimeInterval: options.candidateDelay)

            if let focus = FocusInspector.currentFocus(),
               focus.pid == candidate.ownerPID,
               focus.isTextInput {
                Thread.sleep(forTimeInterval: options.pasteDelay)
                Paster.commandV()
                return "Captured \(captureWindow.ownerName) and pasted into \(focus.appName)."
            }
        }

        throw AppsnapError.pasteTargetUnavailable
    }

    static func parseOptions() -> Options {
        var options = Options()
        var iterator = CommandLine.arguments.dropFirst().makeIterator()

        while let argument = iterator.next() {
            switch argument {
            case "--dry-run": options.dryRun = true
            case "--copy-only": options.copyOnly = true
            case "--verbose", "-v": options.verbose = true
            case "--paste-delay":
                if let value = iterator.next(), let delay = Double(value) { options.pasteDelay = delay }
            case "--candidate-delay":
                if let value = iterator.next(), let delay = Double(value) { options.candidateDelay = delay }
            case "--max-candidates":
                if let value = iterator.next(), let count = Int(value) { options.maxCandidates = max(0, count) }
            case "--help", "-h":
                print("""
                Usage: appsnap [options]
                  --dry-run                 Inspect focus/windows without capturing or pasting
                  --copy-only               Capture to clipboard without changing focus or pasting
                  --paste-delay SECONDS      Delay before paste (default: 0.4)
                  --candidate-delay SECONDS  Delay after activating a candidate window (default: 0.35)
                  --max-candidates COUNT     Maximum previous apps to inspect (default: 3)
                  --verbose, -v              Print focus and window diagnostics
                """)
                exit(0)
            default: break
            }
        }

        return options
    }
}

struct FocusInfo {
    let pid: pid_t
    let appName: String
    let role: String
    let subrole: String
    let isTextInput: Bool

    func matchesTextTarget(_ other: FocusInfo) -> Bool {
        pid == other.pid && isTextInput
    }
}

enum FocusInspector {
    static func currentFocus() -> FocusInfo? {
        let system = AXUIElementCreateSystemWide()
        guard let element = elementAttribute(system, kAXFocusedUIElementAttribute) else { return nil }

        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }

        let role = stringAttribute(element, kAXRoleAttribute) ?? ""
        let subrole = stringAttribute(element, kAXSubroleAttribute) ?? ""
        let roleDescription = stringAttribute(element, kAXRoleDescriptionAttribute) ?? ""
        let appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "Unknown"

        return FocusInfo(
            pid: pid,
            appName: appName,
            role: role,
            subrole: subrole,
            isTextInput: isTextInput(element: element, role: role, subrole: subrole, roleDescription: roleDescription)
        )
    }

    static func isTextInput(element: AXUIElement, role: String, subrole: String, roleDescription: String) -> Bool {
        let knownRoles: Set<String> = [
            kAXTextFieldRole,
            kAXTextAreaRole,
            kAXComboBoxRole,
            "AXSearchField"
        ]

        if knownRoles.contains(role) || knownRoles.contains(subrole) { return true }

        let description = roleDescription.lowercased()
        if description.contains("text field") || description.contains("text area") || description.contains("search field") {
            return true
        }

        let attributes = attributeNames(element)
        return attributes.contains(kAXSelectedTextRangeAttribute)
            && attributes.contains(kAXValueAttribute)
            && boolAttribute(element, kAXFocusedAttribute) == true
    }

    private static func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value
        else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? Bool
    }

    private static func attributeNames(_ element: AXUIElement) -> Set<String> {
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(element, &names) == .success,
              let values = names as? [String]
        else { return [] }
        return Set(values)
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
                  bounds.height >= 80
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

    private static func number(_ value: Any?) -> Double {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) ?? 0 }
        return 0
    }
}

enum Capturer {
    static func copyWindowToClipboard(_ id: CGWindowID) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-c", "-l", String(id)]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw AppsnapError.captureFailed(process.terminationStatus)
        }
    }
}

enum Paster {
    static func commandV() {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        else { return }

        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
