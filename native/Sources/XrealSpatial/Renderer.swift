import MetalKit

/// Interleaved vertex: packed 2D position (NDC) + RGBA. 24 bytes, matches the
/// packed_float2/packed_float4 layout in the shader.
struct Vertex {
    var x: Float; var y: Float
    var r: Float; var g: Float; var b: Float; var a: Float
}

private let shaderSource = """
#include <metal_stdlib>
using namespace metal;
struct Vertex { packed_float2 pos; packed_float4 col; };
struct VOut { float4 position [[position]]; float4 col; };
vertex VOut v_main(uint vid [[vertex_id]], const device Vertex* verts [[buffer(0)]]) {
    VOut o;
    float2 p = verts[vid].pos;
    o.position = float4(p, 0.0, 1.0);
    o.col = verts[vid].col;
    return o;
}
fragment float4 f_main(VOut in [[stage_in]]) { return in.col; }
"""

/// One placeholder "monitor": azimuth, elevation, width, height (degrees).
private struct Panel { let az, el, w, h: Double }
private let panels = [
    Panel(az: -40, el: 0, w: 30, h: 17),
    Panel(az:   0, el: 0, w: 30, h: 17),
    Panel(az:  40, el: 0, w: 30, h: 17),
]

final class Renderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let head: HeadState

    var ppd: Double = 46.0          // measured on a real XREAL One
    var showGrid = true

    private var frames = 0
    private var lastStats = CACurrentMediaTime()

    init(view: MTKView, head: HeadState) {
        self.device = view.device!
        self.head = head
        self.queue = device.makeCommandQueue()!

        let lib = try! device.makeLibrary(source: shaderSource, options: nil)
        let pd = MTLRenderPipelineDescriptor()
        pd.vertexFunction = lib.makeFunction(name: "v_main")
        pd.fragmentFunction = lib.makeFunction(name: "f_main")
        let ca = pd.colorAttachments[0]!
        ca.pixelFormat = view.colorPixelFormat
        ca.isBlendingEnabled = true
        ca.rgbBlendOperation = .add
        ca.alphaBlendOperation = .add
        ca.sourceRGBBlendFactor = .sourceAlpha
        ca.sourceAlphaBlendFactor = .sourceAlpha
        ca.destinationRGBBlendFactor = .oneMinusSourceAlpha
        ca.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        pipeline = try! device.makeRenderPipelineState(descriptor: pd)
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let rpd = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else { return }
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1)

        let W = Double(view.drawableSize.width)
        let H = Double(view.drawableSize.height)
        var tris: [Vertex] = []
        var lines: [Vertex] = []
        if head.hasData {
            buildScene(W: W, H: H, tris: &tris, lines: &lines)
        }
        // head-locked crosshair (fixed at gaze center)
        appendCrosshair(&lines)

        let cmd = queue.makeCommandBuffer()!
        let enc = cmd.makeRenderCommandEncoder(descriptor: rpd)!
        enc.setRenderPipelineState(pipeline)
        draw(&tris, type: .triangle, enc: enc)
        draw(&lines, type: .line, enc: enc)
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()

        frames += 1
        let now = CACurrentMediaTime()
        if now - lastStats >= 1.0 {
            let a = head.angles()
            let fps = Double(frames) / (now - lastStats)
            print(String(format: "\r%4.0f fps  az %+6.1f el %+6.1f roll %+6.1f  IMU-age %4.0f ms  ppd %.0f   ",
                         fps, a.az, a.el, a.roll, a.age * 1000, ppd), terminator: "")
            fflush(stdout)
            frames = 0; lastStats = now
        }
    }

    // MARK: - geometry

    private func draw(_ verts: inout [Vertex], type: MTLPrimitiveType, enc: MTLRenderCommandEncoder) {
        guard !verts.isEmpty else { return }
        let buf = device.makeBuffer(bytes: verts, length: verts.count * MemoryLayout<Vertex>.stride)!
        enc.setVertexBuffer(buf, offset: 0, index: 0)
        enc.drawPrimitives(type: type, vertexStart: 0, vertexCount: verts.count)
    }

    private func buildScene(W: Double, H: Double, tris: inout [Vertex], lines: inout [Vertex]) {
        let a = head.angles()
        let rollRad = a.roll * .pi / 180.0
        let cr = cos(rollRad), sr = sin(rollRad)

        // world (az,el) degrees -> NDC, with level-lock roll compensation
        func project(_ azP: Double, _ elP: Double) -> (Float, Float) {
            let dx = (azP - a.az) * ppd
            let dy = -(elP - a.el) * ppd
            let rx = dx * cr - dy * sr
            let ry = dx * sr + dy * cr
            let px = W / 2 + rx
            let py = H / 2 + ry
            return (Float(px / W * 2 - 1), Float(1 - py / H * 2))
        }
        func v(_ p: (Float, Float), _ c: (Float, Float, Float, Float)) -> Vertex {
            Vertex(x: p.0, y: p.1, r: c.0, g: c.1, b: c.2, a: c.3)
        }

        let gridCol: (Float, Float, Float, Float) = (0.16, 0.17, 0.21, 1)
        let fill: (Float, Float, Float, Float) = (0.24, 0.47, 0.82, 0.35)
        let fillHL: (Float, Float, Float, Float) = (0.35, 0.78, 0.55, 0.40)
        let edge: (Float, Float, Float, Float) = (0.47, 0.65, 0.95, 1)
        let edgeHL: (Float, Float, Float, Float) = (0.45, 0.90, 0.65, 1)

        if showGrid {
            let a0 = (a.az - 60), a1 = (a.az + 60)
            let e0 = (a.el - 40), e1 = (a.el + 40)
            var az = (a0 / 5).rounded(.down) * 5
            while az <= a1 { lines.append(v(project(az, e0), gridCol)); lines.append(v(project(az, e1), gridCol)); az += 5 }
            var el = (e0 / 5).rounded(.down) * 5
            while el <= e1 { lines.append(v(project(a0, el), gridCol)); lines.append(v(project(a1, el), gridCol)); el += 5 }
        }

        for p in panels {
            let centered = abs(wrapDeg(p.az - a.az)) < p.w / 2
            let fc = centered ? fillHL : fill
            let ec = centered ? edgeHL : edge
            let tl = project(p.az - p.w / 2, p.el + p.h / 2)
            let tr = project(p.az + p.w / 2, p.el + p.h / 2)
            let br = project(p.az + p.w / 2, p.el - p.h / 2)
            let bl = project(p.az - p.w / 2, p.el - p.h / 2)
            tris.append(v(tl, fc)); tris.append(v(tr, fc)); tris.append(v(br, fc))
            tris.append(v(tl, fc)); tris.append(v(br, fc)); tris.append(v(bl, fc))
            let corners = [tl, tr, br, bl]
            for i in 0..<4 {
                lines.append(v(corners[i], ec)); lines.append(v(corners[(i + 1) % 4], ec))
            }
        }
    }

    private func appendCrosshair(_ lines: inout [Vertex]) {
        let c: (Float, Float, Float, Float) = (0.90, 0.35, 0.35, 1)
        let d: Float = 0.02
        func v(_ x: Float, _ y: Float) -> Vertex { Vertex(x: x, y: y, r: c.0, g: c.1, b: c.2, a: c.3) }
        lines.append(v(-d, 0)); lines.append(v(d, 0))
        lines.append(v(0, -d * (16.0 / 9.0))); lines.append(v(0, d * (16.0 / 9.0)))
    }
}
