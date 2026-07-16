ObjC.import("AppKit");
ObjC.import("ApplicationServices");
ObjC.import("CoreGraphics");

const TEXT_ROLES = new Set([
  "AXTextField",
  "AXTextArea",
  "AXComboBox",
  "AXSearchField",
]);

function axValue(element, attribute) {
  const valueRef = Ref();
  const error = $.AXUIElementCopyAttributeValue(element, attribute, valueRef);
  if (Number(error) !== 0) return null;
  return valueRef[0];
}

function axString(element, attribute) {
  const value = axValue(element, attribute);
  if (!value) return "";
  return String(ObjC.unwrap(value));
}

function focusedElementInfo(expectedPID) {
  const trusted = Boolean($.AXIsProcessTrusted());
  if (!trusted) {
    return { trusted: false, isTextInput: false };
  }

  const root = expectedPID
    ? $.AXUIElementCreateApplication(Number(expectedPID))
    : $.AXUIElementCreateSystemWide();
  const focused = axValue(root, "AXFocusedUIElement");
  if (!focused) {
    return { trusted: true, isTextInput: false };
  }

  const pidRef = Ref();
  const pidError = $.AXUIElementGetPid(focused, pidRef);
  const pid = Number(pidError) === 0 ? Number(pidRef[0]) : null;
  const role = axString(focused, "AXRole");
  const subrole = axString(focused, "AXSubrole");
  const roleDescription = axString(focused, "AXRoleDescription").toLowerCase();

  let hasSelectedTextRange = false;
  const namesRef = Ref();
  const namesError = $.AXUIElementCopyAttributeNames(focused, namesRef);
  if (Number(namesError) === 0 && namesRef[0]) {
    const names = ObjC.deepUnwrap(ObjC.castRefToObject(namesRef[0])) || [];
    hasSelectedTextRange = names.includes("AXSelectedTextRange");
  }

  const isTextInput =
    TEXT_ROLES.has(role) ||
    TEXT_ROLES.has(subrole) ||
    roleDescription.includes("text field") ||
    roleDescription.includes("text area") ||
    roleDescription.includes("search field") ||
    hasSelectedTextRange;

  return {
    trusted: true,
    pid,
    role,
    subrole,
    roleDescription,
    isTextInput,
  };
}

function normalWindows() {
  const options =
    $.kCGWindowListOptionOnScreenOnly |
    $.kCGWindowListExcludeDesktopElements;
  const ref = $.CGWindowListCopyWindowInfo(options, $.kCGNullWindowID);
  const object = ObjC.castRefToObject(ref);
  const windows = ObjC.deepUnwrap(object) || [];

  return windows.filter((window) => {
    const bounds = window.kCGWindowBounds || {};
    return (
      window.kCGWindowLayer === 0 &&
      window.kCGWindowAlpha > 0 &&
      window.kCGWindowNumber &&
      window.kCGWindowOwnerPID &&
      Number(bounds.Width || 0) >= 120 &&
      Number(bounds.Height || 0) >= 80
    );
  });
}

function pidForBundleIdentifier(bundleIdentifier) {
  const applications = $.NSRunningApplication.runningApplicationsWithBundleIdentifier(
    bundleIdentifier,
  );

  if (Number(applications.count) === 0) return null;
  return Number(applications.objectAtIndex(0).processIdentifier);
}

function serializeWindow(window) {
  return {
    id: Number(window.kCGWindowNumber),
    pid: Number(window.kCGWindowOwnerPID),
    owner: String(window.kCGWindowOwnerName || "Window"),
    title: String(window.kCGWindowName || ""),
  };
}

function inspect(bundleIdentifier) {
  if (!bundleIdentifier) {
    return { error: "Missing frontmost application bundle identifier." };
  }

  const targetPID = pidForBundleIdentifier(bundleIdentifier);
  if (!targetPID) {
    return { error: "Could not resolve the frontmost application process." };
  }

  const windows = normalWindows();
  const targetIndex = windows.findIndex(
    (window) => Number(window.kCGWindowOwnerPID) === targetPID,
  );

  if (targetIndex < 0) {
    return { error: "Could not find the current app window." };
  }

  const target = windows[targetIndex];
  const candidates = [];
  const seenPIDs = new Set();

  for (const window of windows.slice(targetIndex + 1)) {
    const pid = Number(window.kCGWindowOwnerPID);
    if (seenPIDs.has(pid)) continue;
    seenPIDs.add(pid);
    candidates.push(serializeWindow(window));
    if (candidates.length === 3) break;
  }

  return {
    focus: focusedElementInfo(targetPID),
    target: serializeWindow(target),
    candidates,
  };
}

function activate(pid) {
  const application = $.NSRunningApplication.runningApplicationWithProcessIdentifier(
    Number(pid),
  );
  if (!application) return { activated: false };

  const options =
    $.NSApplicationActivateAllWindows |
    $.NSApplicationActivateIgnoringOtherApps;
  const activated = Boolean(application.activateWithOptions(options));
  return { activated };
}

function run(argv) {
  const mode = argv[0] || "inspect";

  if (mode === "inspect") {
    return JSON.stringify(inspect(argv[1]));
  }

  if (mode === "focus") {
    return JSON.stringify({ focus: focusedElementInfo(argv[1]) });
  }

  if (mode === "activate") {
    return JSON.stringify(activate(argv[1]));
  }

  return JSON.stringify({ error: `Unknown mode: ${mode}` });
}
