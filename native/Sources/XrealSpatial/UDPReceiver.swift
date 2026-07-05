import Foundation
import Darwin

/// Receives '<dffff' (wall_time, qw, qx, qy, qz) packets from head_source.py
/// and pushes them into a HeadState. Same wire format as the Python PoC.
final class UDPReceiver {
    private let fd: Int32
    private let head: HeadState
    private var running = true

    init?(port: UInt16, head: HeadState) {
        self.head = head
        fd = socket(AF_INET, SOCK_DGRAM, 0)
        if fd < 0 { return nil }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY

        let ok = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if ok < 0 { close(fd); return nil }
    }

    func start() {
        DispatchQueue.global(qos: .userInteractive).async { [self] in
            var buf = [UInt8](repeating: 0, count: 64)
            while running {
                let n = recv(fd, &buf, buf.count, 0)
                guard n == 24 else { continue }
                buf.withUnsafeBytes { raw in
                    let t = raw.loadUnaligned(fromByteOffset: 0, as: Double.self)
                    let w = raw.loadUnaligned(fromByteOffset: 8, as: Float.self)
                    let x = raw.loadUnaligned(fromByteOffset: 12, as: Float.self)
                    let y = raw.loadUnaligned(fromByteOffset: 16, as: Float.self)
                    let z = raw.loadUnaligned(fromByteOffset: 20, as: Float.self)
                    head.update(Q(w: Double(w), x: Double(x), y: Double(y), z: Double(z)),
                                stamp: t)
                }
            }
        }
    }

    func stop() {
        running = false
        close(fd)
    }
}
