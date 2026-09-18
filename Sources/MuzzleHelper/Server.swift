import Foundation
import Darwin
import MuzzleService

final class ServiceServer: @unchecked Sendable {
    private let config: ServiceConfiguration
    private let queue = DispatchQueue(label: "local.muzzle.helper.policy")
    private let engine: SessionEngine
    private var timer: DispatchSourceTimer?
    private let clients = DispatchSemaphore(value: 8)
    private var lastRestorationNotice: String?
    private var restoringSessionID: UUID?

    init() throws {
        try RootFiles.check(ServicePaths.directory, directory: true)
        try RootFiles.check(Installation.configPath)
        config = try JSONDecoder().decode(ServiceConfiguration.self, from: Data(contentsOf: URL(fileURLWithPath: Installation.configPath)))
        let statePath = ServicePaths.directory + "/session.json"
        let state: ProtectedState
        if FileManager.default.fileExists(atPath: statePath) {
            try RootFiles.check(statePath)
            state = try JSONDecoder().decode(ProtectedState.self, from: Data(contentsOf: URL(fileURLWithPath: statePath)))
        } else { state = ProtectedState() }
        let rules = try SystemRules()
        engine = SessionEngine(state: state, persist: {
            try RootFiles.write(try JSONEncoder().encode($0), to: statePath)
        }, apply: rules.apply)
    }

    func run() throws -> Never {
        try RootFiles.directory(ServicePaths.socketDirectory, mode: 0o755)
        // Only root can unlink entries in this directory.
        if FileManager.default.fileExists(atPath: ServicePaths.socket) {
            try FileManager.default.removeItem(atPath: ServicePaths.socket)
        }
        let listener = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else { throw ServiceFailure("Could not create helper socket.") }
        SocketTransport.configure(listener)
        var address = try SocketTransport.address(ServicePaths.socket)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard result == 0, chown(ServicePaths.socket, config.ownerUID, 0) == 0,
              chmod(ServicePaths.socket, 0o600) == 0, listen(listener, 8) == 0 else {
            throw ServiceFailure("Could not secure helper socket.")
        }
        queue.sync { tickAndNotify(force: true) }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1)
        timer.setEventHandler { [weak self] in self?.tickAndNotify() }
        timer.resume()
        self.timer = timer
        while true {
            clients.wait()
            let fd = accept(listener, nil, nil)
            guard fd >= 0 else { clients.signal(); continue }
            SocketTransport.configure(fd, timeout: 5)
            DispatchQueue.global().async { [self] in
                guard PeerAuthentication.validate(fd: fd, config: config) else {
                    reply(ServiceResponse(error: "This app build is not authorized. Open the Muzzle window and choose Set Up Blocking Service."), fd: fd)
                    return
                }
                do {
                    let request = try JSONDecoder().decode(ServiceRequest.self, from: SocketTransport.read(fd))
                    guard request.version == ServicePaths.protocolVersion else { throw ServiceFailure("The app and service versions do not match.") }
                    queue.async { [self] in
                        do {
                            tickAndNotify()
                            if let delivery = try engine.handle(request.command) {
                                deliver(delivery) { [self] result in
                                    queue.async { [self] in
                                        do {
                                            try result.get()
                                            try engine.confirmDelivery(delivery)
                                            reply(ServiceResponse(snapshot: engine.snapshot()), fd: fd)
                                        } catch { reply(ServiceResponse(snapshot: engine.snapshot(), error: error.localizedDescription), fd: fd) }
                                    }
                                }
                            } else { reply(ServiceResponse(snapshot: engine.snapshot()), fd: fd) }
                        } catch { reply(ServiceResponse(snapshot: engine.snapshot(), error: error.localizedDescription), fd: fd) }
                    }
                } catch { reply(ServiceResponse(error: "Invalid service request."), fd: fd) }
            }
        }
    }

    private func reply(_ response: ServiceResponse, fd: Int32) {
        DispatchQueue.global().async { [self] in
            defer { Darwin.close(fd); clients.signal() }
            try? SocketTransport.write(response, to: fd)
        }
    }

    private func tickAndNotify(force: Bool = false) {
        let before = engine.snapshot()
        if let deadline = before.bypassEndsAt, deadline <= Date() { restoringSessionID = before.sessionID }
        engine.tick(force: force)
        let after = engine.snapshot()
        guard let id = restoringSessionID, after.sessionID == id else { restoringSessionID = nil; return }
        let result = after.isEnforced ? "restored" : "failed"
        let noticeID = id.uuidString + result
        if lastRestorationNotice != noticeID, let delivery = engine.restorationNotice(result) {
            lastRestorationNotice = noticeID
            deliver(delivery) { _ in /* Delivery never gates enforcement. */ }
        }
        if after.isEnforced, after.bypassEndsAt == nil { restoringSessionID = nil; lastRestorationNotice = nil }
    }

    private func deliver(_ delivery: PokeDelivery, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        var request = URLRequest(url: URL(string: "https://poke.com/api/v1/inbound/api-message")!, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("Bearer \(delivery.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do { request.httpBody = try JSONEncoder().encode(delivery.payload) }
        catch { completion(.failure(error)); return }
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error { completion(.failure(error)); return }
            guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode),
                  let data, let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  result["success"] as? Bool == true else {
                completion(.failure(ServiceFailure("Poke did not confirm delivery. Check the API key and connection, then try again.")))
                return
            }
            completion(.success(()))
        }.resume()
    }
}
