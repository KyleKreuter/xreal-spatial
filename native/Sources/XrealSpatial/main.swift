import AppKit
import MetalKit
import CVDShim

// ---- MTKView subclass that forwards key presses ----------------------------
final class KeyView: MTKView {
    var onKey: ((NSEvent) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) { onKey?(event) }
}

func displayID(of screen: NSScreen) -> CGDirectDisplayID {
    (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
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

// ---- displays: left/right = virtual, center = the real main display --------
let vdCount = Int(ProcessInfo.processInfo.environment["XREAL_VD_COUNT"] ?? "2") ?? 2
print("CGVirtualDisplay available: \(CVDFactory.isAvailable())")

var displayIDs: [CGDirectDisplayID?] = [nil, CGMainDisplayID(), nil]  // left, center, right
var virtualIDs = Set<CGDirectDisplayID>()
if CVDFactory.isAvailable() {
    if vdCount >= 1 {
        let id = CVDFactory.createDisplay(withWidth: 1920, height: 1080, name: "XREAL Left")
        if id != 0 { displayIDs[0] = id; virtualIDs.insert(id); print("virtual display Left  -> id \(id)") }
    }
    if vdCount >= 2 {
        let id = CVDFactory.createDisplay(withWidth: 1920, height: 1080, name: "XREAL Right")
        if id != 0 { displayIDs[2] = id; virtualIDs.insert(id); print("virtual display Right -> id \(id)") }
    }
}

// ---- window on the glasses (excluding our virtual displays) ----------------
let screen = pickGlasses(excluding: virtualIDs)
let window = NSWindow(contentRect: screen.frame, styleMask: .borderless,
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

print("XrealSpatial native — window on \(screen.localizedName) \(screen.frame.size)")
print("Keys: space=recenter  up/down=ppd  x/c/v=flip yaw/pitch/roll  g=grid  q/esc=quit")
print("Start head_source.py in another terminal to feed head tracking.\n")

app.run()
