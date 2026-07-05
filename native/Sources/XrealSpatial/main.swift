import AppKit
import MetalKit
import CVDShim

// ---- MTKView subclass that forwards key presses ----------------------------
final class KeyView: MTKView {
    var onKey: ((NSEvent) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) { onKey?(event) }
}

// A borderless window cannot become key by default, so it would never receive
// keyboard events (recenter etc.). Force it.
final class SpatialWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

func displayID(of screen: NSScreen) -> CGDirectDisplayID {
    (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
}

/// Arrange the virtual displays in a predictable row directly above the main
/// display (Left | Center | Right), so mouse/window travel is intuitive:
/// push the cursor up from the main screen to reach Center, then left/right.
func arrangeVirtualDisplays(_ ids: [CGDirectDisplayID?]) {
    var cfg: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&cfg) == .success, let cfg else { return }
    let origins: [(Int32, Int32)] = [(-1920, -1080), (0, -1080), (1920, -1080)]
    for (i, maybeID) in ids.enumerated() where i < origins.count {
        if let id = maybeID {
            CGConfigureDisplayOrigin(cfg, id, origins[i].0, origins[i].1)
        }
    }
    CGCompleteDisplayConfiguration(cfg, .permanently)
}

/// Pick the XREAL One's display. Matches by name first ("One"), then a 1080p
/// screen that is neither our virtual displays nor the main display. Falls back
/// to the main display (visible) with a warning, never to a virtual one.
func pickGlasses(excluding virtual: Set<CGDirectDisplayID>) -> NSScreen {
    let screens = NSScreen.screens
    if let i = CommandLine.arguments.firstIndex(of: "--display"),
       i + 1 < CommandLine.arguments.count,
       let n = Int(CommandLine.arguments[i + 1]), n >= 0, n < screens.count {
        return screens[n]
    }
    if let s = screens.first(where: { $0.localizedName.localizedCaseInsensitiveContains("One") }) {
        return s
    }
    if let s = screens.first(where: {
        $0.frame.width == 1920 && $0.frame.height == 1080
            && !virtual.contains(displayID(of: $0))
            && displayID(of: $0) != CGMainDisplayID()
    }) { return s }
    print("WARN: XREAL One display not found — using the main display. Connect the glasses or pass --display N.")
    return NSScreen.main ?? screens[0]
}

// ---- app ----------------------------------------------------------------
let app = NSApplication.shared
app.setActivationPolicy(.regular)

let head = HeadState()
guard let receiver = UDPReceiver(port: 51234, head: head) else {
    fatalError("Could not bind UDP :51234")
}
receiver.start()

guard let device = MTLCreateSystemDefaultDevice() else {
    fatalError("No Metal device")
}

// ---- displays: three off-screen virtual displays, one per panel ------------
// All three are virtual so the render target (glasses) is never captured -> no
// feedback tunnel. Your real Mac screen stays separate.
let vdCount = Int(ProcessInfo.processInfo.environment["XREAL_VD_COUNT"] ?? "3") ?? 3
print("CGVirtualDisplay available: \(CVDFactory.isAvailable())")

var displayIDs: [CGDirectDisplayID?] = [nil, nil, nil]  // left, center, right
var virtualIDs = Set<CGDirectDisplayID>()
let vdNames = ["XREAL Left", "XREAL Center", "XREAL Right"]
if CVDFactory.isAvailable() {
    for slot in 0..<min(max(vdCount, 0), 3) {
        let id = CVDFactory.createDisplay(withWidth: 1920, height: 1080, name: vdNames[slot])
        if id != 0 {
            displayIDs[slot] = id
            virtualIDs.insert(id)
            print("virtual \(vdNames[slot]) -> id \(id)")
        }
    }
    arrangeVirtualDisplays(displayIDs)   // Left | Center | Right, above main
}

// ---- window on the glasses (excluding our virtual displays) ----------------
let screen = pickGlasses(excluding: virtualIDs)
let window = SpatialWindow(contentRect: screen.frame, styleMask: .borderless,
                          backing: .buffered, defer: false, screen: screen)
window.level = .normal
window.isOpaque = true
window.backgroundColor = .black
window.setFrame(screen.frame, display: true)

let view = KeyView(frame: CGRect(origin: .zero, size: screen.frame.size), device: device)
view.colorPixelFormat = .bgra8Unorm
view.preferredFramesPerSecond = 120
view.isPaused = false
view.enableSetNeedsDisplay = false

// one capture stream per assigned display
var captures: [Int: ScreenCapture] = [:]
for (slot, maybeID) in displayIDs.enumerated() {
    guard let id = maybeID else { continue }
    let c = ScreenCapture(device: device)
    c.start(displayID: id)
    captures[slot] = c
}

let renderer = Renderer(view: view, head: head,
                        texProvider: { slot in captures[slot]?.currentTexture() })
view.delegate = renderer

view.onKey = { event in
    switch event.keyCode {
    case 53: NSApp.terminate(nil)                    // esc
    case 49: head.recenter()                          // space
    case 126: renderer.ppd += 1                       // up arrow
    case 125: renderer.ppd = max(10, renderer.ppd - 1) // down arrow
    default:
        switch event.charactersIgnoringModifiers?.lowercased() ?? "" {
        case "q": NSApp.terminate(nil)
        case "g": renderer.showGrid.toggle()
        case "x": head.signYaw *= -1
        case "c": head.signPitch *= -1
        case "v": head.signRoll *= -1
        default: break
        }
    }
}

window.contentView = view
window.makeKeyAndOrderFront(nil)
window.makeFirstResponder(view)
NSCursor.hide()
app.activate(ignoringOtherApps: true)

// ---- global hotkeys (work while you are in any app) ------------------------
// ctrl+opt+1/2/3 -> send focused window to Left/Center/Right pane
// ctrl+opt+space -> recenter the view
WindowMover.ensurePermission()
func handleHotkey(_ e: NSEvent) -> Bool {
    let mods = e.modifierFlags.intersection([.command, .control, .option, .shift])
    guard mods == [.control, .option] else { return false }
    switch e.keyCode {
    case 18: if let id = displayIDs[0] { WindowMover.move(toDisplay: id) }; return true   // 1
    case 19: if let id = displayIDs[1] { WindowMover.move(toDisplay: id) }; return true   // 2
    case 20: if let id = displayIDs[2] { WindowMover.move(toDisplay: id) }; return true   // 3
    case 49: head.recenter(); return true                                                 // space
    default: return false
    }
}
NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { _ = handleHotkey($0) }
NSEvent.addLocalMonitorForEvents(matching: .keyDown) { handleHotkey($0) ? nil : $0 }

print("XrealSpatial native — window on \(screen.localizedName) \(screen.frame.size)")
print("""
Global hotkeys:  ctrl+opt+1/2/3 = send window to Left/Center/Right pane
                 ctrl+opt+space = recenter
Window keys:     up/down=ppd  x/c/v=flip yaw/pitch/roll  g=grid  q/esc=quit
Start head_source.py in another terminal to feed head tracking.
""")

app.run()
