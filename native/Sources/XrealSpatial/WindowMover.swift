import AppKit
import ApplicationServices

/// Moves the frontmost app's focused window onto a given display and fills it,
/// via the Accessibility API. Requires Accessibility permission.
enum WindowMover {

    /// Prompt for Accessibility permission if not yet granted.
    @discardableResult
    static func ensurePermission() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(opts)
        if !trusted {
            print("""
            Accessibility permission needed to move windows onto panes:
            System Settings > Privacy & Security > Accessibility -> enable your
            terminal, then restart. (Head tracking still works without it.)
            """)
        }
        return trusted
    }

    /// Move + resize the focused window of the frontmost app to fill `displayID`.
    static func move(toDisplay displayID: CGDirectDisplayID) {
        guard displayID != 0, let app = NSWorkspace.shared.frontmostApplication else { return }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var winRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &winRef) == .success,
              let winRef else { return }
        let win = winRef as! AXUIElement

        let bounds = CGDisplayBounds(displayID)
        var origin = bounds.origin
        var size = bounds.size
        if let v = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, v)
        }
        if let v = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, v)
        }
        // set position again: some apps clamp the first move before resizing
        if let v = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, v)
        }
    }
}
