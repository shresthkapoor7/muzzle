/// Presentation state independent of AppKit's window server, also usable in CI.
struct PokeKeyDisclosureState {
    private var userChoice: Bool?

    func isExpanded(isConfigured: Bool) -> Bool {
        userChoice ?? !isConfigured
    }

    mutating func setExpanded(_ expanded: Bool) {
        userChoice = expanded
    }

    mutating func toggle(isConfigured: Bool) {
        userChoice = !isExpanded(isConfigured: isConfigured)
    }

    mutating func configurationChanged(isConfigured: Bool) {
        userChoice = !isConfigured
    }
}

struct StatusMenuPresentation {
    let showsQuit: Bool
    let serviceStatusTitle: String?

    init(usesPrivilegedService: Bool, serviceConnected: Bool, canQuit: Bool) {
        showsQuit = canQuit
        serviceStatusTitle = usesPrivilegedService
            ? (serviceConnected ? "Blocking service: running" : "Blocking service: unavailable")
            : nil
    }
}
