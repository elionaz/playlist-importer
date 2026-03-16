import Foundation
import AppKit

// MARK: - Errors

enum MusicLibraryError: LocalizedError {
    case musicAppNotRunning
    case scriptError(String)
    case noPlaylists
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .musicAppNotRunning: return "Music app is not running. Please open it and try again."
        case .scriptError(let msg): return "AppleScript error: \(msg)"
        case .noPlaylists:        return "No playlists found in Music library."
        case .permissionDenied:   return "Permission denied. Go to System Settings → Privacy → Automation → PlaylistImporter → Music ✓"
        }
    }
}

// MARK: - MusicLibraryService

@MainActor
@Observable final class MusicLibraryService {

    var isLoading = false
    var loadError: String?

    private let batchSize = 500

    // MARK: - Playlist Names

    func fetchPlaylistNames() async throws -> [String] {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        let script = """
        tell application "Music"
            set output to ""
            repeat with p in (every user playlist)
                set output to output & (name of p) & "\n"
            end repeat
            return output
        end tell
        """
        let raw   = try await runAppleScript(script)
        let names = raw
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !names.isEmpty else { throw MusicLibraryError.noPlaylists }
        return names
    }

    // MARK: - Track Count

    /// Devuelve el número de tracks de la playlist sin cargar su metadata.
    func fetchTrackCount(for playlistName: String) async throws -> Int {
        let escaped = playlistName.replacingOccurrences(of: "\"", with: "\\\"")
        // Coercionamos a string dentro del script para que stringValue no devuelva nil
        let script = """
        tell application "Music"
            return (count of tracks of user playlist "\(escaped)") as string
        end tell
        """
        let raw = try await runAppleScript(script)
        return Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    // MARK: - Fetch Playlist with Progress

    /// Carga una playlist en batches de \(batchSize) tracks.
    /// `onProgress` recibe (tracksLoaded, totalTracks) — se llama en MainActor.
    func fetchPlaylist(
        named name: String,
        onProgress: (@MainActor (Int, Int) -> Void)? = nil
    ) async throws -> MusicPlaylist {
        let total = try await fetchTrackCount(for: name)
        await onProgress?(0, total)

        var allTracks: [MusicTrack] = []
        allTracks.reserveCapacity(total)

        var offset = 0
        while offset < total {
            let from  = offset + 1
            let to    = min(offset + batchSize, total)
            let batch = try await fetchTrackBatch(playlistName: name, from: from, to: to)
            allTracks.append(contentsOf: batch)
            offset = to
            await onProgress?(offset, total)
        }

        return MusicPlaylist(id: name, name: name, tracks: allTracks)
    }

    /// Carga varias playlists con progreso.
    func fetchPlaylists(
        named names: [String],
        onProgress: (@MainActor (Int, Int) -> Void)? = nil
    ) async throws -> [MusicPlaylist] {
        var result: [MusicPlaylist] = []
        for (i, name) in names.enumerated() {
            await onProgress?(i, names.count)
            let playlist = try await fetchPlaylist(named: name)
            result.append(playlist)
        }
        await onProgress?(names.count, names.count)
        return result
    }

    // MARK: - Batch Fetch

    private func fetchTrackBatch(playlistName: String, from: Int, to: Int) async throws -> [MusicTrack] {
        let escaped = playlistName.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Music"
            set output to ""
            set p to user playlist "\(escaped)"
            set allTracks to every track of p
            set realTotal to count of allTracks
            set actualFrom to \(from)
            set actualTo to \(to)
            if actualTo > realTotal then set actualTo to realTotal
            if actualFrom > realTotal then return ""
            set batchTracks to items actualFrom through actualTo of allTracks
            repeat with t in batchTracks
                set tID to persistent ID of t
                set tName to name of t
                set tArtist to ""
                try
                    set tArtist to artist of t
                end try
                set tAlbum to ""
                try
                    set tAlbum to album of t
                end try
                set tYear to 0
                try
                    set tYear to year of t
                end try
                set tDur to duration of t
                set tPath to ""
                try
                    set loc to location of t
                    if loc is not missing value then
                        set tPath to POSIX path of loc
                    end if
                end try
                set output to output & tID & "|||" & tName & "|||" & tArtist & "|||" & tAlbum & "|||" & tYear & "|||" & tDur & "|||" & tPath & "\n"
            end repeat
            return output
        end tell
        """
        let raw = try await runAppleScript(script)
        return parseTracks(from: raw)
    }

    // MARK: - AppleScript Runner

    private func runAppleScript(_ source: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            var errorDict: NSDictionary?
            let script = NSAppleScript(source: source)
            guard let descriptor = script?.executeAndReturnError(&errorDict) else {
                if let err = errorDict {
                    let errNum = err[NSAppleScript.errorNumber] as? Int
                    // -600 = procNotFound. Si Music está corriendo, es falta de permiso de Automatización.
                    // Si no está corriendo, es que realmente no está abierta.
                    if errNum == -600 {
                        let musicRunning = !NSRunningApplication
                            .runningApplications(withBundleIdentifier: "com.apple.Music")
                            .isEmpty
                        if musicRunning {
                            throw MusicLibraryError.permissionDenied
                        } else {
                            throw MusicLibraryError.musicAppNotRunning
                        }
                    }
                    // -1743 = not authorized to send Apple Events
                    if errNum == -1743 {
                        throw MusicLibraryError.permissionDenied
                    }
                    let msg = (err[NSAppleScript.errorMessage] as? String)
                           ?? errNum.map { "Error \($0)" }
                           ?? "Unknown AppleScript error"
                    let lower = msg.lowercased()
                    if lower.contains("not authorized") || lower.contains("access") {
                        throw MusicLibraryError.permissionDenied
                    }
                    throw MusicLibraryError.scriptError(msg)
                }
                throw MusicLibraryError.scriptError("Script returned no result")
            }
            return descriptor.stringValue ?? ""
        }.value
    }

    // MARK: - Parser

    private func parseTracks(from raw: String) -> [MusicTrack] {
        raw
            .components(separatedBy: "\n")
            .compactMap { line -> MusicTrack? in
                let parts = line.components(separatedBy: "|||")
                guard parts.count >= 6 else { return nil }

                let persistentID = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let title        = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                let artist       = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
                let album        = parts[3].trimmingCharacters(in: .whitespacesAndNewlines)
                let year         = Int(parts[4].trimmingCharacters(in: .whitespacesAndNewlines))
                let duration     = Double(parts[5].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                let filePath     = parts.count > 6
                    ? parts[6].trimmingCharacters(in: .whitespacesAndNewlines)
                    : ""

                guard !persistentID.isEmpty, !title.isEmpty else { return nil }

                return MusicTrack(
                    id:           persistentID,
                    persistentID: persistentID,
                    title:        title,
                    artist:       artist,
                    album:        album,
                    year:         (year == 0) ? nil : year,
                    duration:     duration,
                    filePath:     filePath.isEmpty ? nil : filePath
                )
            }
    }
}
