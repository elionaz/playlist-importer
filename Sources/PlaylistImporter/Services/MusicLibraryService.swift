import Foundation
import iTunesLibrary

// MARK: - Errors

enum MusicLibraryError: LocalizedError {
    case libraryUnavailable(String)
    case noPlaylists
    case playlistNotFound(String)

    var errorDescription: String? {
        switch self {
        case .libraryUnavailable(let msg):
            return "Could not open Music library: \(msg)"
        case .noPlaylists:
            return "No playlists found in Music library."
        case .playlistNotFound(let name):
            return "Playlist '\(name)' not found."
        }
    }
}

// MARK: - MusicLibraryService

@MainActor
@Observable final class MusicLibraryService {

    var isLoading = false
    var loadError: String?

    // No longer needed — kept so existing call sites compile
    func requestAutomationPermissionIfNeeded() {}

    // MARK: - Playlist Names

    func fetchPlaylistNames() async throws -> [String] {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        return try await Task.detached(priority: .userInitiated) {
            let lib = try ITLibrary(apiVersion: "1.1")
            let names = lib.allPlaylists
                .filter { Self.isUserPlaylist($0) }
                .map { $0.name }
            guard !names.isEmpty else { throw MusicLibraryError.noPlaylists }
            return names
        }.value
    }

    // MARK: - Track Count

    func fetchTrackCount(for playlistName: String) async throws -> Int {
        return try await Task.detached(priority: .userInitiated) {
            let lib = try ITLibrary(apiVersion: "1.1")
            guard let playlist = lib.allPlaylists.first(where: {
                $0.name == playlistName && Self.isUserPlaylist($0)
            }) else { return 0 }
            return playlist.items.count
        }.value
    }

    // MARK: - Fetch Playlist with Progress

    func fetchPlaylist(
        named name: String,
        onProgress: (@MainActor (Int, Int) -> Void)? = nil
    ) async throws -> MusicPlaylist {
        return try await Task.detached(priority: .userInitiated) {
            let lib = try ITLibrary(apiVersion: "1.1")
            guard let playlist = lib.allPlaylists.first(where: {
                $0.name == name && Self.isUserPlaylist($0)
            }) else {
                throw MusicLibraryError.playlistNotFound(name)
            }

            let items = playlist.items
            let total = items.count
            var tracks: [MusicTrack] = []
            tracks.reserveCapacity(total)

            for (i, item) in items.enumerated() {
                if let track = Self.convertItem(item) {
                    tracks.append(track)
                }
                if i % 100 == 0 {
                    let loaded = i
                    await MainActor.run { onProgress?(loaded, total) }
                }
            }
            await MainActor.run { onProgress?(total, total) }
            return MusicPlaylist(id: name, name: name, tracks: tracks)
        }.value
    }

    func fetchPlaylists(
        named names: [String],
        onProgress: (@MainActor (Int, Int) -> Void)? = nil
    ) async throws -> [MusicPlaylist] {
        var result: [MusicPlaylist] = []
        for (i, name) in names.enumerated() {
            await onProgress?(i, names.count)
            result.append(try await fetchPlaylist(named: name))
        }
        await onProgress?(names.count, names.count)
        return result
    }

    // MARK: - Helpers

    private nonisolated static func isUserPlaylist(_ playlist: ITLibPlaylist) -> Bool {
        !playlist.isMaster && playlist.distinguishedKind == .kindNone
    }

    private nonisolated static func convertItem(_ item: ITLibMediaItem) -> MusicTrack? {
        guard item.mediaKind == .kindSong else { return nil }
        let persistentID = String(format: "%llX", item.persistentID)
        let title = item.title
        guard !persistentID.isEmpty, !title.isEmpty else { return nil }
        return MusicTrack(
            id:           persistentID,
            persistentID: persistentID,
            title:        title,
            artist:       item.artist?.name ?? "",
            album:        item.album.title ?? "",
            year:         item.year == 0 ? nil : item.year,
            duration:     Double(item.totalTime) / 1000.0,
            filePath:     item.location?.path
        )
    }
}
