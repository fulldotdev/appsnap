ObjC.import("AppKit");
ObjC.import("CoreGraphics");

const TEXT_ROLES = new Set([
  "AXTextField",
  "AXTextArea",
  "AXComboBox",
  "AXSearchField",
]);
const GEOMETRY_TOLERANCE = 3;

function systemEventsAttribute(element, name) {
  const attributes = element.attributes.whose({ name })();
  if (attributes.length === 0) return null;
  return attributes[0].value();
}

function optionalSystemEventsAttribute(element, name) {
  try {
    return systemEventsAttribute(element, name);
  } catch (_error) {
    return null;
  }
}

function enableSystemEventsAccessibility(process) {
  for (const name of ["AXManualAccessibility", "AXEnhancedUserInterface"]) {
    try {
      const attributes = process.attributes.whose({ name })();
      if (attributes.length > 0) attributes[0].value = true;
    } catch (_error) {
      // Apps that do not expose Chromium's opt-in attributes ignore this.
    }
  }
}

function textElementTraits(element) {
  const role = String(systemEventsAttribute(element, "AXRole") || "");
  const subrole = String(systemEventsAttribute(element, "AXSubrole") || "");
  const roleDescription = String(
    systemEventsAttribute(element, "AXRoleDescription") || "",
  ).toLowerCase();
  const selectedTextRange =
    systemEventsAttribute(element, "AXSelectedTextRange") !== null;
  const isTextInput =
    TEXT_ROLES.has(role) ||
    TEXT_ROLES.has(subrole) ||
    roleDescription.includes("text field") ||
    roleDescription.includes("text area") ||
    roleDescription.includes("search field") ||
    selectedTextRange;

  return {
    role,
    subrole,
    roleDescription,
    selectedTextRange,
    isTextInput,
  };
}

function numberPair(value) {
  if (!value) return null;
  let candidate = value;
  try {
    candidate = ObjC.deepUnwrap(value);
  } catch (_error) {
    // System Events can already return a plain JavaScript array.
  }
  try {
    if (candidate.length < 2) return null;
    const first = Number(candidate[0]);
    const second = Number(candidate[1]);
    return Number.isFinite(first) && Number.isFinite(second)
      ? [first, second]
      : null;
  } catch (_error) {
    return null;
  }
}

function accessibilityWindowGeometry(window) {
  const position = numberPair(
    optionalSystemEventsAttribute(window, "AXPosition"),
  );
  const size = numberPair(optionalSystemEventsAttribute(window, "AXSize"));
  if (!position || !size) return null;
  return {
    x: position[0],
    y: position[1],
    width: size[0],
    height: size[1],
  };
}

function near(first, second) {
  return Math.abs(Number(first) - Number(second)) <= GEOMETRY_TOLERANCE;
}

function windowMatches(window, expected) {
  const geometry = accessibilityWindowGeometry(window);
  return Boolean(
    geometry &&
      near(geometry.x, expected.x) &&
      near(geometry.y, expected.y) &&
      near(geometry.width, expected.width) &&
      near(geometry.height, expected.height),
  );
}

function elementWithinWindow(element, expected) {
  const position = numberPair(
    optionalSystemEventsAttribute(element, "AXPosition"),
  );
  const size = numberPair(optionalSystemEventsAttribute(element, "AXSize"));
  if (!position || !size) return false;
  return (
    position[0] >= expected.x - GEOMETRY_TOLERANCE &&
    position[1] >= expected.y - GEOMETRY_TOLERANCE &&
    position[0] + size[0] <=
      expected.x + expected.width + GEOMETRY_TOLERANCE &&
    position[1] + size[1] <=
      expected.y + expected.height + GEOMETRY_TOLERANCE
  );
}

function safeNumber(value) {
  try {
    return Number(value);
  } catch (_error) {
    return Number.NaN;
  }
}

function processWindow(process, expected) {
  const windows = process.windows();
  const numberMatches = windows.filter(
    (window) =>
      safeNumber(optionalSystemEventsAttribute(window, "AXWindowNumber")) ===
      expected.id,
  );
  if (numberMatches.length === 1) return numberMatches[0];

  const geometryMatches = windows.filter((window) => windowMatches(window, expected));
  if (geometryMatches.length === 1) return geometryMatches[0];

  if (geometryMatches.length > 1 && expected.title) {
    const titleMatches = geometryMatches.filter(
      (window) =>
        String(optionalSystemEventsAttribute(window, "AXTitle") || "") ===
        expected.title,
    );
    if (titleMatches.length === 1) return titleMatches[0];
  }
  return null;
}

function processForPID(systemEvents, pid) {
  const processes = systemEvents.applicationProcesses.whose({
    unixId: Number(pid),
  })();
  return processes.length === 1 ? processes[0] : null;
}

function frontmostPID(systemEvents) {
  const processes = systemEvents.applicationProcesses.whose({ frontmost: true })();
  return processes.length === 1 ? Number(processes[0].unixId()) : null;
}

function runningApplication(pid) {
  return $.NSRunningApplication.runningApplicationWithProcessIdentifier(
    Number(pid),
  );
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
    const application = runningApplication(window.kCGWindowOwnerPID);
    return (
      application &&
      Number(application.activationPolicy) === 0 &&
      window.kCGWindowLayer === 0 &&
      window.kCGWindowAlpha > 0 &&
      window.kCGWindowNumber &&
      Number(bounds.Width || 0) >= 120 &&
      Number(bounds.Height || 0) >= 80
    );
  });
}

function expectedWindowIsFrontmost(expected) {
  const windows = normalWindows();
  if (windows.length === 0) return false;
  return (
    Number(windows[0].kCGWindowNumber) === expected.id &&
    Number(windows[0].kCGWindowOwnerPID) === expected.pid
  );
}

function bundleIdentifierForPID(pid) {
  const application = runningApplication(pid);
  if (!application || !application.bundleIdentifier) return "";
  return String(ObjC.unwrap(application.bundleIdentifier));
}

function serializeWindow(window) {
  const bounds = window.kCGWindowBounds || {};
  return {
    id: Number(window.kCGWindowNumber),
    pid: Number(window.kCGWindowOwnerPID),
    owner: String(window.kCGWindowOwnerName || "Window"),
    title: String(window.kCGWindowName || ""),
    x: Number(bounds.X || 0),
    y: Number(bounds.Y || 0),
    width: Number(bounds.Width || 0),
    height: Number(bounds.Height || 0),
  };
}

function focusedElementInfo(expected, requireActive) {
  let stage = "start";
  try {
    stage = "system-events";
    const systemEvents = Application("System Events");
    const process = expected
      ? processForPID(systemEvents, expected.pid)
      : systemEvents.applicationProcesses.whose({ frontmost: true })()[0];

    if (!process) {
      return {
        trusted: true,
        isTextInput: false,
        activeWindowVerified: false,
        source: "System Events",
      };
    }

    stage = "enable-accessibility";
    enableSystemEventsAccessibility(process);
    stage = "verify-active-window";
    const activeWindowVerified = expected
      ? expectedWindowIsFrontmost(expected)
      : true;

    if (requireActive && !activeWindowVerified) {
      return {
        trusted: true,
        pid: Number(process.unixId()),
        isTextInput: false,
        activeWindowVerified: false,
        source: "System Events",
      };
    }

    stage = "focused-element";
    let focused = systemEventsAttribute(process, "AXFocusedUIElement");
    if (!focused) {
      $.NSThread.sleepForTimeInterval(0.15);
      focused = systemEventsAttribute(process, "AXFocusedUIElement");
    }

    stage = "focused-element-bounds";
    if (focused && expected && !requireActive) {
      if (!elementWithinWindow(focused, expected)) focused = null;
    }

    if (
      expected &&
      !requireActive &&
      (!focused || !textElementTraits(focused).isTextInput)
    ) {
      stage = "match-target-window";
      const targetWindow = processWindow(process, expected);
      if (targetWindow) {
        stage = "scan-target-window";
        const remembered = targetWindow.entireContents().find((element) => {
          const traits = textElementTraits(element);
          return traits.isTextInput && traits.selectedTextRange;
        });
        if (remembered) focused = remembered;
      }
    }

    if (!focused) {
      return {
        trusted: true,
        pid: Number(process.unixId()),
        isTextInput: false,
        activeWindowVerified,
        source: "System Events",
      };
    }

    stage = "focused-element-traits";
    const traits = textElementTraits(focused);
    return {
      trusted: true,
      pid: Number(process.unixId()),
      role: traits.role,
      subrole: traits.subrole,
      roleDescription: traits.roleDescription,
      selectedTextRange: traits.selectedTextRange,
      isTextInput: traits.isTextInput,
      activeWindowVerified,
      source: "System Events",
    };
  } catch (error) {
    return {
      trusted: false,
      isTextInput: false,
      activeWindowVerified: false,
      source: "System Events",
      error: `${stage}: ${String(error)}`,
    };
  }
}

function inspect(bundleIdentifier) {
  if (!bundleIdentifier) {
    return { error: "Missing frontmost application bundle identifier." };
  }

  const windows = normalWindows();
  const targetIndex = windows.findIndex(
    (window) =>
      bundleIdentifierForPID(window.kCGWindowOwnerPID) === bundleIdentifier,
  );
  if (targetIndex < 0) {
    return { error: "Could not find the current app window." };
  }

  const target = serializeWindow(windows[targetIndex]);
  const behind = windows[targetIndex + 1]
    ? serializeWindow(windows[targetIndex + 1])
    : null;
  return {
    focus: focusedElementInfo(target, false),
    target,
    behind,
  };
}

function activate(expected) {
  try {
    const application = runningApplication(expected.pid);
    if (!application) return { activated: false };

    const options = $.NSApplicationActivateIgnoringOtherApps;
    if (!application.activateWithOptions(options)) {
      return { activated: false };
    }
    $.NSThread.sleepForTimeInterval(0.2);

    const systemEvents = Application("System Events");
    const process = processForPID(systemEvents, expected.pid);
    if (process) {
      enableSystemEventsAccessibility(process);
      const target = processWindow(process, expected);
      if (target) {
        const raiseActions = target.actions.whose({ name: "AXRaise" })();
        if (raiseActions.length === 1) raiseActions[0].perform();
      }
    }

    $.NSThread.sleepForTimeInterval(0.15);
    return { activated: expectedWindowIsFrontmost(expected) };
  } catch (error) {
    return { activated: false, error: String(error) };
  }
}

function windowFromArguments(argv, offset) {
  return {
    pid: Number(argv[offset]),
    id: Number(argv[offset + 1]),
    title: String(argv[offset + 2] || ""),
    x: Number(argv[offset + 3]),
    y: Number(argv[offset + 4]),
    width: Number(argv[offset + 5]),
    height: Number(argv[offset + 6]),
  };
}

function run(argv) {
  const mode = argv[0] || "inspect";

  if (mode === "inspect") {
    return JSON.stringify(inspect(argv[1]));
  }

  if (mode === "focus-active") {
    return JSON.stringify({
      focus: focusedElementInfo(windowFromArguments(argv, 1), true),
    });
  }

  if (mode === "activate") {
    return JSON.stringify(activate(windowFromArguments(argv, 1)));
  }

  return JSON.stringify({ error: `Unknown mode: ${mode}` });
}
