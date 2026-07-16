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

function axBoolean(element, attribute) {
  const value = axValue(element, attribute);
  return value ? Boolean(ObjC.unwrap(value)) : false;
}

function axElements(element, attribute) {
  const value = axValue(element, attribute);
  if (!value) return [];

  const array = ObjC.castRefToObject(value);
  const count = Number(array.count);
  if (!Number.isFinite(count)) return [];

  const elements = [];
  for (let index = 0; index < count; index += 1) {
    elements.push(array.objectAtIndex(index));
  }
  return elements;
}

function hasSelectedTextRange(element) {
  const namesRef = Ref();
  const error = $.AXUIElementCopyAttributeNames(element, namesRef);
  if (Number(error) !== 0 || !namesRef[0]) return false;

  const names = ObjC.deepUnwrap(ObjC.castRefToObject(namesRef[0])) || [];
  return names.includes("AXSelectedTextRange");
}

function textElementTraits(element) {
  const role = axString(element, "AXRole");
  const subrole = axString(element, "AXSubrole");
  const roleDescription = axString(element, "AXRoleDescription").toLowerCase();
  const selectedTextRange = hasSelectedTextRange(element);
  const isTextInput =
    TEXT_ROLES.has(role) ||
    TEXT_ROLES.has(subrole) ||
    roleDescription.includes("text field") ||
    roleDescription.includes("text area") ||
    roleDescription.includes("search field") ||
    selectedTextRange;

  return { role, subrole, roleDescription, selectedTextRange, isTextInput };
}

function findRememberedTextElement(application) {
  const roots = [];
  const focusedWindow = axValue(application, "AXFocusedWindow");
  const mainWindow = axValue(application, "AXMainWindow");
  if (focusedWindow) roots.push(focusedWindow);
  if (mainWindow) roots.push(mainWindow);
  roots.push(...axElements(application, "AXWindows"));

  const queue = roots;
  let fallback = null;
  let visited = 0;

  while (queue.length > 0 && visited < 1500) {
    const element = queue.shift();
    visited += 1;

    const traits = textElementTraits(element);
    if (traits.isTextInput) {
      if (axBoolean(element, "AXFocused")) return element;
      if (!fallback && traits.selectedTextRange) fallback = element;
    }

    queue.push(...axElements(element, "AXChildren"));
  }

  return fallback;
}

function focusedElementInfo(expectedPID) {
  const trusted = Boolean($.AXIsProcessTrusted());
  if (!trusted) {
    return { trusted: false, isTextInput: false };
  }

  const root = expectedPID
    ? $.AXUIElementCreateApplication(Number(expectedPID))
    : $.AXUIElementCreateSystemWide();
  let focused = axValue(root, "AXFocusedUIElement");
  let remembered = false;
  if ((!focused || !textElementTraits(focused).isTextInput) && expectedPID) {
    const rememberedElement = findRememberedTextElement(root);
    if (rememberedElement) {
      focused = rememberedElement;
      remembered = true;
    }
  }

  if (!focused) {
    return { trusted: true, isTextInput: false };
  }

  const pidRef = Ref();
  const pidError = $.AXUIElementGetPid(focused, pidRef);
  const pid = Number(pidError) === 0 ? Number(pidRef[0]) : null;
  const traits = textElementTraits(focused);

  return {
    trusted: true,
    pid,
    role: traits.role,
    subrole: traits.subrole,
    roleDescription: traits.roleDescription,
    isTextInput: traits.isTextInput,
    remembered,
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
  const behind = windows[targetIndex + 1];

  return {
    focus: focusedElementInfo(targetPID),
    target: serializeWindow(target),
    behind: behind ? serializeWindow(behind) : null,
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
