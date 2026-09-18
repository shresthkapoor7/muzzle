import Foundation
import Darwin
import MuzzleService

umask(0o077)
do {
    guard geteuid() == 0 else { throw ServiceFailure("MuzzleHelper must be installed and run as root by launchd.") }
    let arguments = CommandLine.arguments
    if arguments.count == 4, arguments[1] == "--install", let uid = UInt32(arguments[3]) {
        try Installation.install(appPath: arguments[2], ownerUID: uid)
    } else if arguments.count == 1 {
        try ServiceServer().run()
    } else { throw ServiceFailure("Invalid helper invocation.") }
} catch {
    // Never print requests, tokens, session keys, or protected state.
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
