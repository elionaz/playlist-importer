import Foundation

// MARK: - Errors

enum PlexAPIError: LocalizedError {
    case notConfigured
    case networkError(Error)
    case httpError(Int)
    case decodingError(Error)
    case noMusicLibrary
    case emptyPlaylist

    var errorDescription: String? {
        switch self {
        case .notConfigured:         return "Plex server URL or token is not configured."
        case .networkError(let e):   return "Network error: \(e.localizedDescription)"
        case .httpError(let code):   return "HTTP error \(code)"
        case .decodingError(let e):  return "Response parsing error: \(e.localizedDescription)"
        case .noMusicLibrary:        return "No music library found on the Plex server."
        case .emptyPlaylist:         return "Cannot create an empty playlist."
        }
    }
}

// MARK: - PlexAPIService

@MainActor
@Observable final class PlexAPIService {

    private let settings: AppSettings
    private let pageSize = 500
    private let decoder = JSONDecoder()

    init(settings: AppSettings) {
        self.settings = settings
    }

    // MARK: - Identity

    /// Fetches the server's machine identifier and stores it in AppSettings.
    func fetchAndStoreIdentity() async throws {
        let container: PlexIdentityContainer = try await get(path: "/identity")
        settings.plexMachineIdentifier = container.mediaContainer.machineIdentifier
    }

    // MARK: - Library Sections

    /// Returns all library sections.
    func fetchLibrarySections() async throws -> [PlexLibrarySection] {
        let container: PlexSectionsContainer = try await get(path: "/library/sections")
        let responses = container.mediaContainer.directory ?? []
        return responses.map { PlexLibrarySection(from: $0) }
    }

    /// Finds the first music section and stores its ID in AppSettings.
    @discardableResult
    func fetchAndStoreMusicSection() async throws -> PlexLibrarySection {
        let sections = try await fetchLibrarySections()
        guard let music = sections.first(where: { $0.isMusic }) else {
            throw PlexAPIError.noMusicLibrary
        }
        settings.plexLibrarySectionID = music.key
        return music
    }

    // MARK: - Tracks

    /// Loads all tracks from the music section, paginated.
    /// - Parameter onProgress: called with 0.0–1.0 as pages load.
    func fetchAllTracks(
        sectionID: String? = nil,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> [PlexTrack] {
        let section = sectionID ?? settings.plexLibrarySectionID
        let path = "/library/sections/\(section)/all"
        let baseParams = ["type": "10"]

        // First page — also reveals totalSize
        let first: PlexTracksContainer = try await get(
            path: path,
            params: baseParams.merging(["X-Plex-Container-Start": "0",
                                        "X-Plex-Container-Size": "\(pageSize)"]) { $1 }
        )

        let total = first.mediaContainer.totalSize ?? first.mediaContainer.size
        var allTracks = (first.mediaContainer.metadata ?? []).map { PlexTrack(from: $0) }
        onProgress?(min(Double(allTracks.count) / Double(max(total, 1)), 1.0))

        // Remaining pages
        var offset = allTracks.count
        while allTracks.count < total {
            let page: PlexTracksContainer = try await get(
                path: path,
                params: baseParams.merging([
                    "X-Plex-Container-Start": "\(offset)",
                    "X-Plex-Container-Size": "\(pageSize)"
                ]) { $1 }
            )
            let batch = (page.mediaContainer.metadata ?? []).map { PlexTrack(from: $0) }
            if batch.isEmpty { break }
            allTracks.append(contentsOf: batch)
            offset = allTracks.count
            onProgress?(min(Double(allTracks.count) / Double(max(total, 1)), 1.0))
        }

        return allTracks
    }

    // MARK: - Path Debug

    /// Returns the server-side file path of the first track in the selected music section.
    /// Useful for calibrating the Plex path prefix in Settings.
    func fetchSampleTrackPath() async throws -> String? {
        let section = settings.plexLibrarySectionID
        guard !section.isEmpty else { return nil }
        let container: PlexTracksContainer = try await get(
            path: "/library/sections/\(section)/all",
            params: ["type": "10", "X-Plex-Container-Start": "0", "X-Plex-Container-Size": "1"]
        )
        return container.mediaContainer.metadata?.first.flatMap { PlexTrack(from: $0).filePath }
    }

    // MARK: - Playlists

    /// Returns the tracks currently in a playlist.
    func fetchPlaylistItems(id: String) async throws -> [PlexTrack] {
        let container: PlexTracksContainer = try await get(path: "/playlists/\(id)/items")
        return (container.mediaContainer.metadata ?? []).map { PlexTrack(from: $0) }
    }

    /// Returns all audio playlists on the server.
    func fetchPlaylists() async throws -> [PlexPlaylist] {
        let container: PlexPlaylistsContainer = try await get(
            path: "/playlists",
            params: ["playlistType": "audio"]
        )
        return (container.mediaContainer.metadata ?? []).map { PlexPlaylist(from: $0) }
    }

    /// Creates a new audio playlist with the given tracks.
    /// Plex requires at least one track to create a playlist.
    @discardableResult
    func createPlaylist(name: String, ratingKeys: [String]) async throws -> PlexPlaylist {
        guard !ratingKeys.isEmpty else { throw PlexAPIError.emptyPlaylist }

        let machineID = settings.plexMachineIdentifier
        let uri = buildMetadataURI(machineID: machineID, ratingKeys: ratingKeys)

        let container: PlexPlaylistsContainer = try await post(
            path: "/playlists",
            params: [
                "type":  "audio",
                "title": name,
                "smart": "0",
                "uri":   uri
            ]
        )
        guard let response = container.mediaContainer.metadata?.first else {
            throw PlexAPIError.decodingError(
                NSError(domain: "PlexAPI", code: 0,
                        userInfo: [NSLocalizedDescriptionKey: "No playlist in response"])
            )
        }
        return PlexPlaylist(from: response)
    }

    /// Appends tracks to an existing playlist. Batches at 500 keys per request.
    func addTracks(ratingKeys: [String], toPlaylist playlistID: String) async throws {
        let machineID = settings.plexMachineIdentifier
        for batch in ratingKeys.chunked(into: pageSize) {
            let uri = buildMetadataURI(machineID: machineID, ratingKeys: batch)
            try await put(path: "/playlists/\(playlistID)/items", params: ["uri": uri])
        }
    }

    /// Deletes a playlist by its ratingKey.
    func deletePlaylist(id: String) async throws {
        try await delete(path: "/playlists/\(id)")
    }

    // MARK: - HTTP Helpers

    private func get<T: Decodable>(path: String, params: [String: String] = [:]) async throws -> T {
        let request = try buildRequest(method: "GET", path: path, params: params)
        return try await perform(request)
    }

    private func post<T: Decodable>(path: String, params: [String: String] = [:]) async throws -> T {
        let request = try buildRequest(method: "POST", path: path, params: params)
        return try await perform(request)
    }

    private func put(path: String, params: [String: String] = [:]) async throws {
        let request = try buildRequest(method: "PUT", path: path, params: params)
        let (_, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response)
    }

    private func delete(path: String) async throws {
        let request = try buildRequest(method: "DELETE", path: path, params: [:])
        let (_, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response)
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw PlexAPIError.networkError(error)
        }
        try validateHTTP(response)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw PlexAPIError.decodingError(error)
        }
    }

    private func buildRequest(
        method: String,
        path: String,
        params: [String: String]
    ) throws -> URLRequest {
        let base = settings.plexServerURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !base.isEmpty, !settings.plexToken.isEmpty else {
            throw PlexAPIError.notConfigured
        }

        var components = URLComponents(string: base + path)!
        var queryItems = [URLQueryItem(name: "X-Plex-Token", value: settings.plexToken)]
        for (key, value) in params {
            queryItems.append(URLQueryItem(name: key, value: value))
        }
        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(settings.plexToken, forHTTPHeaderField: "X-Plex-Token")
        return request
    }

    private func validateHTTP(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw PlexAPIError.httpError(http.statusCode)
        }
    }

    // MARK: - URI Builder

    private func buildMetadataURI(machineID: String, ratingKeys: [String]) -> String {
        let keys = ratingKeys.joined(separator: ",")
        return "server://\(machineID)/com.plexapp.plugins.library/library/metadata/\(keys)"
    }
}

// MARK: - Array chunking helper

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
