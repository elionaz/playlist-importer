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

    // No longer needed — kept so existing call sites compile
    func requestAutomationPermissionIfNeeded() {}

    // MARK: - Ensure Music is running

    private func ensureMusicRunning() async throws {
        if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty {
            return
        }
        let musicURL = URL(fileURLWithPath: "/System/Applications/Music.app")
        NSWorkspace.shared.open(musicURL)
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(500))
            if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty {
                try await Task.sleep(for: .seconds(3)) // wait for library to load
                return
            }
        }
        throw MusicLibraryError.musicAppNotRunning
    }

    // MARK: - Playlist Names

    func fetchPlaylistNames() async throws -> [String] {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        try await ensureMusicRunning()

        let script = """
        tell application id "com.apple.Music"
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

    func fetchTrackCount(for playlistName: String) async throws -> Int {
        let escaped = playlistName.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application id "com.apple.Music"
            return (count of tracks of user playlist "\(escaped)") as string
        end tell
        """
        let raw = try await runAppleScript(script)
        return Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    // MARK: - Fetch Playlist with Progress

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
        tell application id "com.apple.Music"
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
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var errorDict: NSDictionary?
                let script = NSAppleScript(source: source)
                guard let descriptor = script?.executeAndReturnError(&errorDict) else {
                    let errNum = errorDict?[NSAppleScript.errorNumber] as? Int
                    let msg    = errorDict?[NSAppleScript.errorMessage] as? String
                    print("[MusicLibraryService] NSAppleScript error \(errNum ?? 0): \(msg ?? "nil")")
                    switch errNum {
                    case -600:  continuation.resume(throwing: MusicLibraryError.musicAppNotRunning)
                    case -1743: continuation.resume(throwing: MusicLibraryError.permissionDenied)
                    default:
                        let lower = (msg ?? "").lowercased()
                        if lower.contains("not authorized") || lower.contains("access") {
                            continuation.resume(throwing: MusicLibraryError.permissionDenied)
                        } else {
                            continuation.resume(throwing: MusicLibraryError.scriptError(msg ?? "Error \(errNum ?? -1)"))
                        }
                    }
                    return
                }
                continuation.resume(returning: descriptor.stringValue ?? "")
            }
        }
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
