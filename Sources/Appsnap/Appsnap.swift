import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct Options {
    var dryRun = false
    var copyOnly = false
    var verbose = false
    var activationDelay: TimeInterval = 0.7
    var pasteDelay: TimeInterval = 0.15
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
            return "Accessibility permission is required for the launcher (normally Raycast)."
        case .screenRecordingPermission:
            return "Screen Recording permission is required for the launcher (normally Raycast)."
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

@main
struct Appsnap {
    static func main() {
        do {
            print(try run(options: parseOptions()))
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

        let windows = WindowInspector.normalWindows(excludingPID: getpid())
        guard let current = windows.first else {
            throw AppsnapError.noCurrentWindow
        }
        guard windows.count > 1 else {
            throw AppsnapError.noBehindWindow
        }
        let behind = windows[1]
        FocusInspector.enableEnhancedAccessibility(for: current.ownerPID)
        Thread.sleep(forTimeInterval: 0.05)
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
            try Capturer.copyWindowToClipboard(behind.id)
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

            Thread.sleep(forTimeInterval: options.pasteDelay)
            try Paster.commandV()
            return "Pasted \(behind.ownerName) into \(current.ownerName)."
        }

        try Capturer.copyWindowToClipboard(current.id)
        if options.copyOnly {
            return "Captured \(current.ownerName) to the clipboard."
        }

        let activated = WindowActivator.activate(behind)
        if activated {
            Thread.sleep(forTimeInterval: options.activationDelay)
            if WindowInspector.frontmostWindow()?.id == behind.id,
               let focus = FocusInspector.currentFocus(),
               focus.isTextInput,
               FocusInspector.belongsToWindow(focus, window: behind)
            {
                Thread.sleep(forTimeInterval: options.pasteDelay)
                try Paster.commandV()
                return "Pasted \(current.ownerName) into \(behind.ownerName)."
            }
        }

        _ = WindowActivator.activate(current)
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
            case "--activation-delay":
                if let value = iterator.next(), let delay = Double(value) {
                    options.activationDelay = max(0, delay)
                }
            case "--paste-delay":
                if let value = iterator.next(), let delay = Double(value) {
                    options.pasteDelay = max(0, delay)
                }
            case "--help", "-h":
                print("""
                Usage: appsnap [options]
                  --dry-run                    Inspect without capturing or pasting
                  --copy-only                  Capture without changing focus or pasting
                  --activation-delay SECONDS   Wait after activating the behind window
                  --paste-delay SECONDS        Wait before Command-V
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
            frame: frame(of: element)
        )
    }

    static func belongsToWindow(_ focus: FocusInfo, window: WindowInfo) -> Bool {
        if let frame = focus.frame {
            let expanded = window.bounds.insetBy(dx: -4, dy: -4)
            return expanded.contains(CGPoint(x: frame.midX, y: frame.midY))
        }
        return focus.pid == window.ownerPID
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
    static func copyWindowToClipboard(_ id: CGWindowID) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-c", "-l", String(id)]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw AppsnapError.captureFailed(process.terminationStatus)
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
