import ScreenCaptureKit
import CoreVideo
import Metal

/// Captures one display via ScreenCaptureKit and exposes its latest frame as a
/// Metal texture. Frames arrive IOSurface-backed, so the conversion to
/// MTLTexture is zero-copy through a CVMetalTextureCache.
@available(macOS 13.0, *)
final class ScreenCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    private let device: MTLDevice
    private var stream: SCStream?
    private var cache: CVMetalTextureCache!
    private let lock = NSLock()
    private var latest: MTLTexture?
    private var retain: CVMetalTexture?   // keep the CVMetalTexture alive while used

    init(device: MTLDevice) {
        self.device = device
        super.init()
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
    }

    func currentTexture() -> MTLTexture? {
        lock.lock(); defer { lock.unlock() }
        return latest
    }

    /// Begin capturing the given display. Prints guidance if permission is missing.
    /// Retries a few times because a freshly created virtual display may take a
    /// moment to appear in the shareable content list.
    func start(displayID: CGDirectDisplayID) {
        Task {
            do {
                var found: SCDisplay?
                for attempt in 0..<20 {
                    let content = try await SCShareableContent.excludingDesktopWindows(
                        false, onScreenWindowsOnly: false)
                    if let d = content.displays.first(where: { $0.displayID == displayID }) {
                        found = d
                        break
                    }
                    if attempt == 0 { _ = content }   // permission check happens here
                    try await Task.sleep(nanoseconds: 200_000_000)
                }
                guard let disp = found else {
                    print("capture: display \(displayID) not found after retries")
                    return
                }
                let filter = SCContentFilter(display: disp, excludingWindows: [])
                let cfg = SCStreamConfiguration()
                cfg.width = disp.width
                cfg.height = disp.height
                cfg.pixelFormat = kCVPixelFormatType_32BGRA
                cfg.queueDepth = 3
                cfg.showsCursor = true

                let s = SCStream(filter: filter, configuration: cfg, delegate: self)
                try s.addStreamOutput(self, type: .screen,
                                      sampleHandlerQueue: DispatchQueue(label: "xreal.capture"))
                try await s.startCapture()
                self.stream = s
                print("capture: streaming display \(disp.displayID) at \(disp.width)x\(disp.height)")
            } catch {
                print("""
                capture: FAILED (\(error.localizedDescription)).
                Grant Screen Recording to your terminal:
                System Settings > Privacy & Security > Screen Recording, then restart.
                Panels stay as flat placeholders until then.
                """)
            }
        }
    }

    func stop() {
        stream?.stopCapture { _ in }
        stream = nil
    }

    // MARK: SCStreamOutput
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen,
              let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        var cvtex: CVMetalTexture?
        let r = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, cache, pb, nil, .bgra8Unorm, w, h, 0, &cvtex)
        guard r == kCVReturnSuccess, let cvtex,
              let tex = CVMetalTextureGetTexture(cvtex) else { return }
        lock.lock()
        latest = tex
        retain = cvtex
        lock.unlock()
    }

    // MARK: SCStreamDelegate
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("capture: stopped with error \(error.localizedDescription)")
    }
}
