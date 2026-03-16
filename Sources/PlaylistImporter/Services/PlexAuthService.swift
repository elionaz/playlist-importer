import Foundation
import AppKit

// MARK: - Models

private struct PlexPinResponse: Decodable {
    let id: Int
    let code: String
    let authToken: String?

    enum CodingKeys: String, CodingKey {
        case id
        case code
        case authToken = "authToken"
    }
}

// MARK: - Errors

enum PlexAuthError: LocalizedError {
    case networkError(Error)
    case invalidResponse
    case timeout
    case cancelled

    var errorDescription: String? {
        switch self {
        case .networkError(let e): return "Network error: \(e.localizedDescription)"
        case .invalidResponse:     return "Invalid response from plex.tv"
        case .timeout:             return "Authentication timed out. Please try again."
        case .cancelled:           return "Authentication was cancelled."
        }
    }
}

// MARK: - PlexAuthService

@MainActor
@Observable final class PlexAuthService {

    private let clientID: String
    private let clientName = "PlaylistImporter"
    private let clientVersion = "1.0"

    var isAuthenticating = false
    var authError: String?
    private var pollingTask: Task<Void, Never>?

    init() {
        // Stable client ID per installation
        if let saved = UserDefaults.standard.string(forKey: "plexClientID") {
            self.clientID = saved
        } else {
            let newID = UUID().uuidString
            UserDefaults.standard.set(newID, forKey: "plexClientID")
            self.clientID = newID
        }
    }

    // MARK: - Public API

    /// Starts the PIN OAuth flow. Calls `onSuccess` with the token when done.
    func startAuthFlow(onSuccess: @escaping @MainActor @Sendable (String) -> Void) {
        isAuthenticating = true
        authError = nil

        pollingTask = Task {
            do {
                let token = try await performAuthFlow()
                isAuthenticating = false
                onSuccess(token)
            } catch PlexAuthError.cancelled {
                isAuthenticating = false
            } catch {
                isAuthenticating = false
                authError = error.localizedDescription
            }
        }
    }

    func cancelAuth() {
        pollingTask?.cancel()
        pollingTask = nil
        isAuthenticating = false
        authError = nil
    }

    // MARK: - Internal Flow

    private func performAuthFlow() async throws -> String {
        // Step 1: Get a PIN
        let pin = try await requestPin()

        // Step 2: Open browser for user authorization
        let authURL = buildAuthURL(code: pin.code)
        NSWorkspace.shared.open(authURL)

        // Step 3: Poll until token is available (max 5 minutes)
        return try await pollForToken(pinID: pin.id)
    }

    private func requestPin() async throws -> PlexPinResponse {
        var request = URLRequest(url: URL(string: "https://plex.tv/api/v2/pins?strong=true")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        addPlexHeaders(to: &request)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 201 else {
                throw PlexAuthError.invalidResponse
            }
            return try JSONDecoder().decode(PlexPinResponse.self, from: data)
        } catch let error as PlexAuthError {
            throw error
        } catch {
            throw PlexAuthError.networkError(error)
        }
    }

    private func pollForToken(pinID: Int) async throws -> String {
        let url = URL(string: "https://plex.tv/api/v2/pins/\(pinID)")!
        let maxAttempts = 150 // 5 minutes at 2s intervals

        for _ in 0..<maxAttempts {
            try Task.checkCancellation()
            try await Task.sleep(for: .seconds(2))
            try Task.checkCancellation()

            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            addPlexHeaders(to: &request)

            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                let pin = try JSONDecoder().decode(PlexPinResponse.self, from: data)
                if let token = pin.authToken, !token.isEmpty {
                    return token
                }
            } catch is CancellationError {
                throw PlexAuthError.cancelled
            } catch {
                // Transient network error — keep polling
                continue
            }
        }

        throw PlexAuthError.timeout
    }

    private func buildAuthURL(code: String) -> URL {
        // Plex auth URL format: https://app.plex.tv/auth#?clientID=...&code=...
        // The '?' must be INSIDE the hash fragment — URLComponents would strip it,
        // so we build the string directly.
        let params = [
            "clientID=\(clientID)",
            "code=\(code)",
            "context[device][product]=\(clientName)",
            "context[device][platform]=macOS"
        ].joined(separator: "&")
        return URL(string: "https://app.plex.tv/auth#?\(params)")!
    }

    private func addPlexHeaders(to request: inout URLRequest) {
        request.setValue(clientID,      forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.setValue(clientName,    forHTTPHeaderField: "X-Plex-Product")
        request.setValue(clientVersion, forHTTPHeaderField: "X-Plex-Version")
        request.setValue("macOS",       forHTTPHeaderField: "X-Plex-Platform")
    }
}
