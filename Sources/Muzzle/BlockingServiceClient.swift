import AppKit
import MuzzleService

enum BlockingServiceClient {
    static func request(_ command: ServiceCommand) throws -> ServiceResponse {
        try SocketTransport.request(command)
    }

    @MainActor
    static func install() throws {
        let app = Bundle.main.bundleURL
        let helper = app.appendingPathComponent("Contents/Library/HelperTools/MuzzleHelper")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw ServiceFailure("Run the packaged Muzzle.app built by scripts/build-app.sh to install the blocking service.")
        }
        func quote(_ string: String) -> String { "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let command = "\(quote(helper.path)) --install \(quote(app.path)) \(getuid())"
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var error: NSDictionary?
        guard let script = NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges") else {
            throw ServiceFailure("Could not prepare service installation.")
        }
        script.executeAndReturnError(&error)
        if let error {
            throw ServiceFailure(error[NSAppleScript.errorMessage] as? String ?? "Blocking service installation was cancelled.")
        }
    }
}
