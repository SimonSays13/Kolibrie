import Darwin
import Foundation

/// Chooses a TCP port for a new model's server.
public enum PortPicker {
    /// The first port from `start` that no other model uses and that nothing is listening on.
    public static func nextFree(startingAt start: Int = 8000, avoiding taken: Set<Int> = []) -> Int {
        var port = start
        while port < 65535 {
            if !taken.contains(port), isFree(port) { return port }
            port += 1
        }
        return start
    }

    /// True when a listener could bind to the port on the loopback address.
    public static func isFree(_ port: Int) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        var reuse: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }
}
