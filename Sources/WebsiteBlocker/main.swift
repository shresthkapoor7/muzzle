import AppKit

if CommandLine.arguments.contains("--remove-website-blocker-hosts") {
    NSApplication.shared.setActivationPolicy(.accessory)
    do {
        try HostsFileController().apply([])
        exit(EXIT_SUCCESS)
    } catch {
        FileHandle.standardError.write(Data("Website Blocker could not remove its hosts-file entries: \(error.localizedDescription)\n".utf8))
        exit(EXIT_FAILURE)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
