import Foundation

struct PokeClient {
    private let endpoint = URL(string: "https://poke.com/api/v1/inbound/api-message")!

    enum PokeError: LocalizedError {
        case missingAPIKey
        case invalidResponse
        case rejected(Int)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                "Poke delivery is not configured. Add your bearer token to POKE_API_KEY in Muzzle’s .env file."
            case .invalidResponse:
                "Poke did not return a valid response."
            case .rejected(let statusCode):
                "Poke rejected the request with HTTP status \(statusCode)."
            }
        }
    }

    func sendLockKey(
        _ key: String,
        workingOn: String? = nil,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let completionBox = CompletionBox(completion)
        guard let apiKey = loadAPIKey() else {
            completionBox.call(.failure(PokeError.missingAPIKey))
            return
        }

        let payload = LockKeyPayload(key: key, date: currentDateString(), workingOn: workingOn)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(payload)
        } catch {
            completionBox.call(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error {
                completionBox.call(.failure(error))
                return
            }
            guard let response = response as? HTTPURLResponse else {
                completionBox.call(.failure(PokeError.invalidResponse))
                return
            }
            guard (200...299).contains(response.statusCode) else {
                completionBox.call(.failure(PokeError.rejected(response.statusCode)))
                return
            }
            completionBox.call(.success(()))
        }.resume()
    }

    func sendBypass(minutes: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        let completionBox = CompletionBox(completion)
        guard let apiKey = loadAPIKey() else {
            completionBox.call(.failure(PokeError.missingAPIKey))
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(BypassPayload(minutes: minutes, date: currentDateString()))
        } catch {
            completionBox.call(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error {
                completionBox.call(.failure(error))
                return
            }
            guard let response = response as? HTTPURLResponse else {
                completionBox.call(.failure(PokeError.invalidResponse))
                return
            }
            guard (200...299).contains(response.statusCode) else {
                completionBox.call(.failure(PokeError.rejected(response.statusCode)))
                return
            }
            completionBox.call(.success(()))
        }.resume()
    }

    private func loadAPIKey() -> String? {
        if let key = ProcessInfo.processInfo.environment["POKE_API_KEY"], !key.isEmpty {
            return key
        }

        for envURL in envFileLocations() {
            guard let contents = try? String(contentsOf: envURL, encoding: .utf8) else { continue }
            for line in contents.split(whereSeparator: \.isNewline) {
                let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2,
                      parts[0].trimmingCharacters(in: .whitespaces) == "POKE_API_KEY" else { continue }
                let key = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty { return key }
            }
        }
        return nil
    }

    private func envFileLocations() -> [URL] {
        let projectDirectory = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return [projectDirectory.appendingPathComponent(".env"), currentDirectory.appendingPathComponent(".env")]
    }

    private func currentDateString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

private final class CompletionBox: @unchecked Sendable {
    private let completion: (Result<Void, Error>) -> Void

    init(_ completion: @escaping (Result<Void, Error>) -> Void) {
        self.completion = completion
    }

    func call(_ result: Result<Void, Error>) {
        completion(result)
    }
}

private struct LockKeyPayload: Encodable {
    let event = "lock_key"
    let key: String
    let date: String
    let workingOn: String?

    enum CodingKeys: String, CodingKey {
        case event
        case key
        case date
        case workingOn = "working_on"
    }
}

private struct BypassPayload: Encodable {
    let event = "bypass"
    let minutes: Int
    let date: String
}
