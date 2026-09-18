import Foundation
import Darwin
import MuzzleService

enum RootFiles {
    static func directory(_ path: String, mode: Int = 0o700) throws {
        if !FileManager.default.fileExists(atPath: path) {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false,
                                                   attributes: [.posixPermissions: mode, .ownerAccountID: 0])
        }
        try check(path, directory: true)
    }

    static func check(_ path: String, directory: Bool = false) throws {
        var info = stat()
        guard lstat(path, &info) == 0, info.st_uid == 0,
              info.st_mode & 0o022 == 0,
              info.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG) else {
            throw ServiceFailure("Unsafe ownership, permissions, or file type at \(path).")
        }
    }

    static func write(_ data: Data, to path: String, mode: Int = 0o600) throws {
        if FileManager.default.fileExists(atPath: path) { try check(path) }
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        guard chmod(path, mode_t(mode)) == 0 else { throw ServiceFailure("Could not secure service data.") }
    }
}

/// Fixed executable + argument arrays only. No shell interpolation or client paths.
enum RootProcess {
    @discardableResult
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 5) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
        timer.resume()
        defer { timer.cancel() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ServiceFailure("A system blocking operation failed (\(URL(fileURLWithPath: executable).lastPathComponent)).") }
        return data
    }
}
