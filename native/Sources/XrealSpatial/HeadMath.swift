import Foundation

/// Quaternion (w, x, y, z).
struct Q {
    var w, x, y, z: Double
    static let identity = Q(w: 1, x: 0, y: 0, z: 0)
}

func quatMul(_ a: Q, _ b: Q) -> Q {
    Q(w: a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
      x: a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
      y: a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
      z: a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w)
}

func quatConj(_ q: Q) -> Q { Q(w: q.w, x: -q.x, y: -q.y, z: -q.z) }

/// Rotate a 3-vector by a quaternion.
func quatRotate(_ q: Q, _ v: (Double, Double, Double)) -> (Double, Double, Double) {
    let tx = 2 * (q.y * v.2 - q.z * v.1)
    let ty = 2 * (q.z * v.0 - q.x * v.2)
    let tz = 2 * (q.x * v.1 - q.y * v.0)
    return (v.0 + q.w * tx + (q.y * tz - q.z * ty),
            v.1 + q.w * ty + (q.z * tx - q.x * tz),
            v.2 + q.w * tz + (q.x * ty - q.y * tx))
}

/// Mounting-correct head decomposition (port of xreal.head_angles).
/// XREAL One frame: up = +Y, right = +X, forward = +Z. No cross-coupling.
func headAngles(_ q: Q, ref: Q?) -> (az: Double, el: Double, roll: Double) {
    let qq = ref != nil ? quatMul(quatConj(ref!), q) : q
    let f = quatRotate(qq, (0, 0, 1))    // forward
    let u = quatRotate(qq, (0, 1, 0))    // up
    let deg = 180.0 / Double.pi
    let az = atan2(f.0, f.2) * deg
    let el = atan2(f.1, hypot(f.0, f.2)) * deg
    // right = cross((0,1,0), f) = (f.z, 0, -f.x)
    var rx = f.2, ry = 0.0, rz = -f.0
    let rn = (rx * rx + ry * ry + rz * rz).squareRoot()
    var roll = 0.0
    if rn > 1e-9 {
        rx /= rn; ry /= rn; rz /= rn
        // realUp = cross(f, right)
        let ux = f.1 * rz - f.2 * ry
        let uy = f.2 * rx - f.0 * rz
        let uz = f.0 * ry - f.1 * rx
        let dotR = u.0 * rx + u.1 * ry + u.2 * rz
        let dotU = u.0 * ux + u.1 * uy + u.2 * uz
        roll = atan2(dotR, dotU) * deg
    }
    return (az, el, roll)
}

func wrapDeg(_ a: Double) -> Double {
    var v = a
    while v > 180 { v -= 360 }
    while v < -180 { v += 360 }
    return v
}

/// Thread-safe latest head pose + recenter reference + per-mount sign flags.
final class HeadState {
    private let lock = NSLock()
    private var q = Q.identity
    private var ref: Q?
    private var stamp = 0.0

    // Validated defaults for the XREAL One mount.
    var signYaw = 1.0
    var signPitch = -1.0
    var signRoll = 1.0
    private(set) var hasData = false

    func update(_ nq: Q, stamp t: Double) {
        lock.lock()
        q = nq; stamp = t
        if ref == nil { ref = nq }
        hasData = true
        lock.unlock()
    }

    func recenter() {
        lock.lock(); ref = q; lock.unlock()
    }

    /// (azimuth, elevation, roll) in degrees, plus data age in seconds.
    func angles() -> (az: Double, el: Double, roll: Double, age: Double) {
        lock.lock()
        let cq = q, cr = ref, st = stamp
        lock.unlock()
        let a = headAngles(cq, ref: cr)
        let age = Date().timeIntervalSince1970 - st
        return (a.az * signYaw, a.el * signPitch, a.roll * signRoll, age)
    }
}
