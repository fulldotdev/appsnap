ObjC.import("AppKit");
ObjC.import("CoreGraphics");

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

  if (Number(applications.count) === 0) {
    return null;
  }

  return Number(applications.objectAtIndex(0).processIdentifier);
}

function run(argv) {
  const bundleIdentifier = argv[0];
  if (!bundleIdentifier) {
    return JSON.stringify({ error: "Missing frontmost application bundle identifier." });
  }

  const targetPID = pidForBundleIdentifier(bundleIdentifier);
  if (!targetPID) {
    return JSON.stringify({ error: "Could not resolve the frontmost application process." });
  }

  const windows = normalWindows();
  const targetIndex = windows.findIndex(
    (window) => Number(window.kCGWindowOwnerPID) === targetPID,
  );

  if (targetIndex < 0) {
    return JSON.stringify({ error: "Could not find the current app window." });
  }

  const target = windows[targetIndex];
  const behind = windows[targetIndex + 1];

  if (!behind) {
    return JSON.stringify({ error: "No window was found behind the current app." });
  }

  return JSON.stringify({
    target: {
      id: Number(target.kCGWindowNumber),
      owner: String(target.kCGWindowOwnerName || "Current app"),
      title: String(target.kCGWindowName || ""),
    },
    behind: {
      id: Number(behind.kCGWindowNumber),
      owner: String(behind.kCGWindowOwnerName || "Window"),
      title: String(behind.kCGWindowName || ""),
    },
  });
}
