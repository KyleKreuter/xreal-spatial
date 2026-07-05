import MetalKit

/// Flat colored vertex: packed 2D position (NDC) + RGBA. 24 bytes.
struct Vertex {
    var x: Float; var y: Float
    var r: Float; var g: Float; var b: Float; var a: Float
}

/// Textured vertex: packed 2D position (NDC) + UV. 16 bytes.
struct TVertex {
    var x: Float; var y: Float
    var u: Float; var v: Float
}

private let shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct Vertex { packed_float2 pos; packed_float4 col; };
struct VOut { float4 position [[position]]; float4 col; };
vertex VOut v_main(uint vid [[vertex_id]], const device Vertex* verts [[buffer(0)]]) {
    VOut o; o.position = float4(float2(verts[vid].pos), 0.0, 1.0); o.col = verts[vid].col; return o;
}
fragment float4 f_main(VOut in [[stage_in]]) { return in.col; }

struct TVertex { packed_float2 pos; packed_float2 uv; };
struct TOut { float4 position [[position]]; float2 uv; };
vertex TOut vt_main(uint vid [[vertex_id]], const device TVertex* verts [[buffer(0)]]) {
    TOut o; o.position = float4(float2(verts[vid].pos), 0.0, 1.0); o.uv = verts[vid].uv; return o;
}
fragment float4 ft_main(TOut in [[stage_in]], texture2d<float> tex [[texture(0)]],
                        sampler smp [[sampler(0)]]) {
    return tex.sample(smp, in.uv);
}
"""

private struct Panel { let az, el, w, h: Double }
private let panels = [
    Panel(az: -40, el: 0, w: 30, h: 17),   // display slot 0 (left)
    Panel(az:   0, el: 0, w: 30, h: 17),   // display slot 1 (center)
    Panel(az:  40, el: 0, w: 30, h: 17),   // display slot 2 (right)
]

final class Renderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let flatPipeline: MTLRenderPipelineState
    private let texPipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private let head: HeadState
    private let texProvider: (Int) -> MTLTexture?

    var ppd: Double = 46.0
    var showGrid = true

    private var frames = 0
    private var lastStats = CACurrentMediaTime()

    init(view: MTKView, head: HeadState, texProvider: @escaping (Int) -> MTLTexture?) {
        let dev = view.device!            // local: avoids touching self before super.init
        let fmt = view.colorPixelFormat
        self.device = dev
        self.head = head
        self.texProvider = texProvider
        self.queue = dev.makeCommandQueue()!

        let lib = try! dev.makeLibrary(source: shaderSource, options: nil)

        func makePipeline(_ vfn: String, _ ffn: String) -> MTLRenderPipelineState {
            let pd = MTLRenderPipelineDescriptor()
            pd.vertexFunction = lib.makeFunction(name: vfn)
            pd.fragmentFunction = lib.makeFunction(name: ffn)
            let ca = pd.colorAttachments[0]!
            ca.pixelFormat = fmt
            ca.isBlendingEnabled = true
            ca.rgbBlendOperation = .add
            ca.alphaBlendOperation = .add
            ca.sourceRGBBlendFactor = .sourceAlpha
            ca.sourceAlphaBlendFactor = .sourceAlpha
            ca.destinationRGBBlendFactor = .oneMinusSourceAlpha
            ca.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try! dev.makeRenderPipelineState(descriptor: pd)
        }
        flatPipeline = makePipeline("v_main", "f_main")
        texPipeline = makePipeline("vt_main", "ft_main")

        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear
        sd.magFilter = .linear
        sd.sAddressMode = .clampToEdge
        sd.tAddressMode = .clampToEdge
        sampler = dev.makeSamplerState(descriptor: sd)!
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let rpd = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else { return }
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1)

        let W = Double(view.drawableSize.width)
        let H = Double(view.drawableSize.height)

        var gridLines: [Vertex] = []
        var flatTris: [Vertex] = []
        var edgeLines: [Vertex] = []
        var textured: [(MTLTexture, [TVertex])] = []

        if head.hasData {
            build(W: W, H: H, gridLines: &gridLines, flatTris: &flatTris,
                  edgeLines: &edgeLines, textured: &textured)
        }
        appendCrosshair(&edgeLines)

        let cmd = queue.makeCommandBuffer()!
        let enc = cmd.makeRenderCommandEncoder(descriptor: rpd)!

        enc.setRenderPipelineState(flatPipeline)
        drawFlat(&gridLines, .line, enc)          // grid behind
        drawFlat(&flatTris, .triangle, enc)       // not-yet-captured panels

        for (tex, verts) in textured {             // one display texture per panel
            enc.setRenderPipelineState(texPipeline)
            let b = device.makeBuffer(bytes: verts, length: verts.count * MemoryLayout<TVertex>.stride)!
            enc.setVertexBuffer(b, offset: 0, index: 0)
            enc.setFragmentTexture(tex, index: 0)
            enc.setFragmentSamplerState(sampler, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: verts.count)
        }
        enc.setRenderPipelineState(flatPipeline)
        drawFlat(&edgeLines, .line, enc)          // edges + crosshair on top
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()

        frames += 1
        let now = CACurrentMediaTime()
        if now - lastStats >= 1.0 {
            let a = head.angles()
            print(String(format: "\r%4.0f fps  az %+6.1f el %+6.1f roll %+6.1f  IMU-age %4.0f ms  ppd %.0f  %d/3 live   ",
                         Double(frames) / (now - lastStats), a.az, a.el, a.roll, a.age * 1000, ppd,
                         textured.count), terminator: "")
            fflush(stdout)
            frames = 0; lastStats = now
        }
    }

    private func drawFlat(_ verts: inout [Vertex], _ type: MTLPrimitiveType, _ enc: MTLRenderCommandEncoder) {
        guard !verts.isEmpty else { return }
        let b = device.makeBuffer(bytes: verts, length: verts.count * MemoryLayout<Vertex>.stride)!
        enc.setVertexBuffer(b, offset: 0, index: 0)
        enc.drawPrimitives(type: type, vertexStart: 0, vertexCount: verts.count)
    }

    private func build(W: Double, H: Double,
                       gridLines: inout [Vertex], flatTris: inout [Vertex],
                       edgeLines: inout [Vertex], textured: inout [(MTLTexture, [TVertex])]) {
        let a = head.angles()
        let rr = a.roll * .pi / 180.0
        let cr = cos(rr), sr = sin(rr)

        func project(_ azP: Double, _ elP: Double) -> (Float, Float) {
            let dx = (azP - a.az) * ppd
            let dy = -(elP - a.el) * ppd
            let rx = dx * cr - dy * sr
            let ry = dx * sr + dy * cr
            return (Float((W / 2 + rx) / W * 2 - 1), Float(1 - (H / 2 + ry) / H * 2))
        }
        func fv(_ p: (Float, Float), _ c: (Float, Float, Float, Float)) -> Vertex {
            Vertex(x: p.0, y: p.1, r: c.0, g: c.1, b: c.2, a: c.3)
        }
        func tv(_ p: (Float, Float), _ u: Float, _ v: Float) -> TVertex {
            TVertex(x: p.0, y: p.1, u: u, v: v)
        }

        let gridCol: (Float, Float, Float, Float) = (0.16, 0.17, 0.21, 1)
        let fill: (Float, Float, Float, Float) = (0.24, 0.47, 0.82, 0.35)
        let edge: (Float, Float, Float, Float) = (0.47, 0.65, 0.95, 1)
        let edgeHL: (Float, Float, Float, Float) = (0.45, 0.90, 0.65, 1)

        if showGrid {
            let a0 = a.az - 60, a1 = a.az + 60, e0 = a.el - 40, e1 = a.el + 40
            var az = (a0 / 5).rounded(.down) * 5
            while az <= a1 { gridLines.append(fv(project(az, e0), gridCol)); gridLines.append(fv(project(az, e1), gridCol)); az += 5 }
            var el = (e0 / 5).rounded(.down) * 5
            while el <= e1 { gridLines.append(fv(project(a0, el), gridCol)); gridLines.append(fv(project(a1, el), gridCol)); el += 5 }
        }

        for (idx, p) in panels.enumerated() {
            let tl = project(p.az - p.w / 2, p.el + p.h / 2)
            let tr = project(p.az + p.w / 2, p.el + p.h / 2)
            let br = project(p.az + p.w / 2, p.el - p.h / 2)
            let bl = project(p.az - p.w / 2, p.el - p.h / 2)
            if let tex = texProvider(idx) {
                // textured quad: tl(0,0) tr(1,0) br(1,1) bl(0,1)
                let q = [tv(tl, 0, 0), tv(tr, 1, 0), tv(br, 1, 1),
                         tv(tl, 0, 0), tv(br, 1, 1), tv(bl, 0, 1)]
                textured.append((tex, q))
            } else {
                flatTris.append(fv(tl, fill)); flatTris.append(fv(tr, fill)); flatTris.append(fv(br, fill))
                flatTris.append(fv(tl, fill)); flatTris.append(fv(br, fill)); flatTris.append(fv(bl, fill))
            }
            let centered = abs(wrapDeg(p.az - a.az)) < p.w / 2
            let ec = centered ? edgeHL : edge
            let corners = [tl, tr, br, bl]
            for i in 0..<4 {
                edgeLines.append(fv(corners[i], ec)); edgeLines.append(fv(corners[(i + 1) % 4], ec))
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
