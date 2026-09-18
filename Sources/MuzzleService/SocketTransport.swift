import Foundation
import Darwin

public enum SocketTransport {
    public static let maxBytes = 65536

    public static func address(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw ServiceFailure("Service socket path is too long.") }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        return address
    }

    public static func configure(_ fd: Int32, timeout: Int = 20) {
        var enabled: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
        var value = timeval(tv_sec: timeout, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &value, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &value, socklen_t(MemoryLayout<timeval>.size))
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
    }

    public static func read(_ fd: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count <= maxBytes {
            let count = Darwin.recv(fd, &buffer, buffer.count, 0)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw ServiceFailure("The blocking service did not respond. Install or update it from the Muzzle menu.") }
            if let newline = buffer[..<count].firstIndex(of: 10) {
                data.append(contentsOf: buffer[..<newline])
                guard data.count <= maxBytes else { break }
                return data
            }
            data.append(contentsOf: buffer[..<count])
        }
        throw ServiceFailure("Service message exceeds the size limit.")
    }

    public static func write<T: Encodable>(_ value: T, to fd: Int32) throws {
        var data = try JSONEncoder().encode(value)
        guard data.count <= maxBytes else { throw ServiceFailure("Service message exceeds the size limit.") }
        data.append(10)
        try data.withUnsafeBytes { bytes in
            var sent = 0
            while sent < bytes.count {
                let count = Darwin.send(fd, bytes.baseAddress!.advanced(by: sent), bytes.count - sent, 0)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw ServiceFailure("Could not communicate with the blocking service.") }
                sent += count
            }
        }
    }

    public static func request(_ command: ServiceCommand) throws -> ServiceResponse {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ServiceFailure("Could not open a service connection.") }
        defer { Darwin.close(fd) }
        configure(fd)
        var address = try address(ServicePaths.socket)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { throw ServiceFailure("Install or update the blocking service from the Muzzle menu. Protection cannot be changed until it is available.") }
        var uid: uid_t = 0; var gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == 0 else { throw ServiceFailure("The blocking service is not running as root.") }
        try write(ServiceRequest(command), to: fd)
        let response = try JSONDecoder().decode(ServiceResponse.self, from: read(fd))
        guard response.version == ServicePaths.protocolVersion else { throw ServiceFailure("Update the blocking service to match this Muzzle build.") }
        return response
    }
}
