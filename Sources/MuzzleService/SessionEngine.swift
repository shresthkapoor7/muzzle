import Foundation

/// Serialized by the helper's policy queue. Only the helper persists this object.
public struct ProtectedState: Codable {
    var session: ProtectedSession?
    var needsApply = false
    public init() {}
}

struct ProtectedSession: Codable {
    var id = UUID()
    var domains: [String]
    var startedAt: Date
    var endsAt: Date?
    var bypassStartedAt: Date?
    var bypassEndsAt: Date?
    var remaining: Int
    var dailyLimit: Int
    var renewsAt: Date
    var unlockCode: String
    var unlockFailures = 0
    var unlockRetryAt: Date?
    var extraCode: String?
    var extraExpiresAt: Date?
    var extraDelivered = false
    var extraAttempts = 0
    var pokeToken: String?
}

public struct PokeDelivery: Sendable {
    public let sessionID: UUID
    public let token: String
    public let payload: [String: String]
    public let approvalCode: String?
}

public final class SessionEngine {
    public private(set) var state: ProtectedState
    private let persist: (ProtectedState) throws -> Void
    private let apply: ([String]) throws -> Void
    private let makeCode: () -> String
    private var appliedDomains: [String]?
    private var lastError: String?

    public init(state: ProtectedState = ProtectedState(), persist: @escaping (ProtectedState) throws -> Void,
                apply: @escaping ([String]) throws -> Void,
                makeCode: @escaping () -> String = { String(format: "%06d", Int.random(in: 0..<1_000_000)) }) {
        self.state = state
        self.persist = persist
        self.apply = apply
        self.makeCode = makeCode
    }

    public func snapshot() -> ServiceSnapshot {
        var result = ServiceSnapshot()
        if let session = state.session {
            result.sessionID = session.id
            result.domains = session.domains
            result.startedAt = session.startedAt
            result.endsAt = session.endsAt
            result.bypassStartedAt = session.bypassStartedAt
            result.bypassEndsAt = session.bypassEndsAt
            result.remaining = session.remaining
            result.dailyLimit = session.dailyLimit
            result.renewsAt = session.renewsAt
            result.isEnforced = appliedDomains == session.domains
        }
        result.error = lastError
        return result
    }

    /// Run at launch and every second. Deadlines depend on saved wall-clock dates,
    /// not on the app process, a client request, or user authorization dialogs.
    public func tick(now: Date = Date(), force: Bool = false) {
        var updated = state
        var changed = false
        if var session = updated.session {
            if let end = session.endsAt, now >= end {
                updated.session = nil
                changed = true
            } else {
                if let end = session.bypassEndsAt, now >= end {
                    session.bypassStartedAt = nil
                    session.bypassEndsAt = nil
                    changed = true
                }
                if now >= session.renewsAt {
                    let days = floor(now.timeIntervalSince(session.renewsAt) / 86400) + 1
                    session.renewsAt.addTimeInterval(days * 86400)
                    session.remaining = session.dailyLimit
                    changed = true
                }
                updated.session = session
            }
        }
        if changed {
            updated.needsApply = true
            do {
                try persist(updated)
                state = updated
            } catch {
                // Disk failure must never extend an expired bypass.
                do { try applyEffectiveRules(for: updated, now: now) } catch { }
                lastError = "Could not save the protection deadline. The service will retry."
                return
            }
        }
        if force || state.needsApply || appliedDomains == nil {
            do {
                try applyEffectiveRules(for: state, now: now)
                var saved = state
                saved.needsApply = false
                if state.needsApply { try persist(saved) }
                state = saved
                lastError = nil
            } catch {
                lastError = "Protection update failed: \(error.localizedDescription). The service will retry."
            }
        }
    }

    /// Returns a Poke delivery for the server to perform asynchronously, never on
    /// the policy/deadline queue. Secrets are never included in a client response.
    public func handle(_ command: ServiceCommand, now: Date = Date()) throws -> PokeDelivery? {
        tick(now: now)
        switch command {
        case .status: return nil
        case .retry: tick(now: now, force: true); return nil
        case let .add(rawDomain, minutes, limit):
            let domain = try ServiceValidation.domain(rawDomain)
            var updated = state
            if var session = updated.session {
                guard session.domains.count < 64 else { throw ServiceFailure("The limit is 64 websites.") }
                if !session.domains.contains(domain) { session.domains.append(domain); session.domains.sort() }
                updated.session = session
            } else {
                guard (0...3).contains(limit) else { throw ServiceFailure("Choose 0–3 bypasses.") }
                let duration = try minutes.map(ServiceValidation.seconds)
                updated.session = ProtectedSession(domains: [domain], startedAt: now,
                    endsAt: duration.map { now.addingTimeInterval($0) }, remaining: limit, dailyLimit: limit,
                    renewsAt: now.addingTimeInterval(86400), unlockCode: makeCode())
            }
            try commit(updated, applyRules: true, now: now)
        case .bypass(let minutes):
            guard var session = state.session else { throw ServiceFailure("No protection session is active.") }
            guard session.bypassEndsAt == nil else { throw ServiceFailure("A bypass is already active or awaiting restoration.") }
            guard session.remaining > 0 else { throw ServiceFailure("No bypasses remain.") }
            let duration = try ServiceValidation.seconds(minutes)
            session.remaining -= 1
            session.bypassStartedAt = now
            session.bypassEndsAt = min(now.addingTimeInterval(duration), session.endsAt ?? .distantFuture)
            var updated = state; updated.session = session
            try commit(updated, applyRules: true, now: now)
        case .end(let code):
            guard var session = state.session else { return nil }
            guard session.endsAt == nil else { throw ServiceFailure("Timed protection ends at its saved deadline.") }
            if let retry = session.unlockRetryAt, now < retry { throw ServiceFailure("Too many incorrect keys. Try again in 15 minutes.") }
            if session.unlockRetryAt != nil { session.unlockFailures = 0; session.unlockRetryAt = nil }
            guard code == session.unlockCode else {
                session.unlockFailures += 1
                if session.unlockFailures >= 5 { session.unlockRetryAt = now.addingTimeInterval(900) }
                var updated = state; updated.session = session
                try commit(updated, applyRules: false, now: now)
                throw ServiceFailure("That session key does not match.")
            }
            var updated = state; updated.session = nil
            try commit(updated, applyRules: true, now: now)
        case let .deliverKey(token, context):
            guard var session = state.session, session.endsAt == nil else { throw ServiceFailure("No untimed session is active.") }
            try validateToken(token)
            guard (context?.utf8.count ?? 0) <= 500 else { throw ServiceFailure("Work context is too long.") }
            session.pokeToken = token
            var updated = state; updated.session = session
            try commit(updated, applyRules: false, now: now)
            var payload = ["event": "lock_key", "key": session.unlockCode, "date": dateString(now)]
            if let context, !context.isEmpty { payload["working_on"] = context }
            return PokeDelivery(sessionID: session.id, token: token, payload: payload, approvalCode: nil)
        case .requestExtra(let token):
            guard var session = state.session else { throw ServiceFailure("No protection session is active.") }
            guard session.remaining < 3 else { throw ServiceFailure("Three bypasses are already available.") }
            try validateToken(token)
            session.extraCode = makeCode()
            session.extraExpiresAt = now.addingTimeInterval(900)
            session.extraDelivered = false
            session.extraAttempts = 5
            var updated = state; updated.session = session
            try commit(updated, applyRules: false, now: now)
            return PokeDelivery(sessionID: session.id, token: token,
                payload: ["event": "bypass_request", "key": session.extraCode!, "date": dateString(now),
                          "message": "The user requests one extra Muzzle bypass. Share this key if approved. It expires in 15 minutes and does not end protection."],
                approvalCode: session.extraCode)
        case .redeemExtra(let code):
            guard var session = state.session, session.extraDelivered,
                  let expiry = session.extraExpiresAt, now < expiry, session.extraAttempts > 0 else {
                throw ServiceFailure("Request an extra bypass from Poke; the previous code is missing, expired, or exhausted.")
            }
            guard code.trimmingCharacters(in: .whitespacesAndNewlines) == session.extraCode else {
                session.extraAttempts -= 1
                var updated = state; updated.session = session
                try commit(updated, applyRules: false, now: now)
                throw ServiceFailure("That approval code does not match.")
            }
            guard session.remaining < 3 else { throw ServiceFailure("Three bypasses are already available.") }
            session.remaining += 1
            session.extraCode = nil
            session.extraDelivered = false
            var updated = state; updated.session = session
            try commit(updated, applyRules: false, now: now)
        }
        return nil
    }

    public func confirmDelivery(_ delivery: PokeDelivery, now: Date = Date()) throws {
        guard let code = delivery.approvalCode, var session = state.session,
              session.id == delivery.sessionID, session.extraCode == code,
              session.extraExpiresAt.map({ now < $0 }) == true else { return }
        session.extraDelivered = true
        var updated = state; updated.session = session
        try commit(updated, applyRules: false, now: now)
    }

    public func restorationNotice(_ result: String, now: Date = Date()) -> PokeDelivery? {
        guard let session = state.session, session.endsAt == nil, let token = session.pokeToken else { return nil }
        return PokeDelivery(sessionID: session.id, token: token,
            payload: ["event": "bypass_restoration", "state": result, "date": dateString(now),
                      "message": result == "restored"
                        ? "Muzzle's background service restored protection after the bypass."
                        : "Muzzle's background service could not fully restore protection and is retrying automatically."],
            approvalCode: nil)
    }

    private func commit(_ updated: ProtectedState, applyRules: Bool, now: Date) throws {
        var updated = updated
        updated.needsApply = updated.needsApply || applyRules
        try persist(updated)
        state = updated
        if applyRules { tick(now: now, force: true) }
        if let lastError, applyRules { throw ServiceFailure(lastError) }
    }

    private func applyEffectiveRules(for state: ProtectedState, now: Date) throws {
        let domains: [String]
        if let session = state.session, session.endsAt.map({ now < $0 }) ?? true,
           !(session.bypassEndsAt.map({ now < $0 }) ?? false) {
            domains = session.domains
        } else { domains = [] }
        try apply(domains)
        appliedDomains = domains
    }

    private func validateToken(_ token: String) throws {
        guard !token.isEmpty, token.utf8.count <= 8192, !token.contains("\n"), !token.contains("\r") else {
            throw ServiceFailure("A valid Poke API key is required.")
        }
    }

    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
