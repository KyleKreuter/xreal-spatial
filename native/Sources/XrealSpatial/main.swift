import AppKit
import MetalKit

// ---- MTKView subclass that forwards key presses ----------------------------
final class KeyView: MTKView {
    var onKey: ((NSEvent) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) { onKey?(event) }
}

// ---- pick the glasses display ----------------------------------------------
// XREAL One reports as a 1920x1080 external screen; default to that, else the
// last (non-main) screen. Override with `--display N`.
func pickScreen() -> NSScreen {
    let screens = NSScreen.screens
    if let i = CommandLine.arguments.firstIndex(of: "--display"),
       i + 1 < CommandLine.arguments.count,
       let n = Int(CommandLine.arguments[i + 1]), n >= 0, n < screens.count {
        return screens[n]
    }
    if let one = screens.first(where: { $0.frame.width == 1920 && $0.frame.height == 1080 }) {
        return one
    }
    return screens.last ?? screens[0]
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

let screen = pickScreen()
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

// capture the main (built-in) display onto the center panel
let capture = ScreenCapture(device: device)
capture.start(displayID: CGMainDisplayID())

let renderer = Renderer(view: view, head: head, texProvider: { capture.currentTexture() })
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

print("XrealSpatial native — display \(screen.frame.size)")
print("Keys: space=recenter  up/down=ppd  x/c/v=flip yaw/pitch/roll  g=grid  q/esc=quit")
print("Start head_source.py in another terminal to feed head tracking.\n")

app.run()
