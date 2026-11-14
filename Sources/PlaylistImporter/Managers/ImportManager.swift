import Foundation

// MARK: - Supporting Types

enum ImportStep: String, Sendable {
    case idle        = "Ready"
    case loadingPlex = "Loading Plex library…"
    case buildingIndex = "Building search index…"
    case matching    = "Matching tracks…"
    case creating    = "Creating playlists…"
    case done        = "Done"
    case cancelled   = "Cancelled"
    case failed      = "Failed"
}

enum DuplicateAction: String, CaseIterable, Sendable {
    case skip          = "Skip"
    case replace       = "Replace"
    case appendMissing = "Append missing"
    case rename        = "Rename (add suffix)"
}

struct ImportLogEntry: Identifiable, Sendable {
    let id = UUID()
    let playlistName: String
    let tracksTotal: Int
    let tracksMatched: Int
    let tracksSkipped: Int
    let tracksUnmatched: Int
    let action: String
    let timestamp: Date
    let plexPlaylistID: String?   // ratingKey — nil si no se creó/actualizó

    var csvRow: String {
        let ts = ISO8601DateFormatter().string(from: timestamp)
        return "\"\(playlistName)\",\(tracksTotal),\(tracksMatched),\(tracksSkipped),\(tracksUnmatched),\"\(action)\",\"\(ts)\""
    }
}

// MARK: - ImportManager

@MainActor
@Observable final class ImportManager {

    // MARK: - Observable State

    var step: ImportStep = .idle
    var plexLoadProgress: Double = 0          // 0–1 mientras carga Plex
    var currentPlaylistName: String = ""
    var currentPlaylistIndex: Int = 0
    var totalPlaylists: Int = 0
    var currentTrackIndex: Int = 0
    var currentTrackTotal: Int = 0
    var matchResults: [String: [String: MatchResult]] = [:]  // playlistName → persistentID → result
    var importLog: [ImportLogEntry] = []
    var errorMessage: String?

    var isRunning: Bool { step != .idle && step != .done && step != .cancelled && step != .failed }

    var overallProgress: Double {
        guard totalPlaylists > 0 else { return 0 }
        let playlistProgress = Double(currentPlaylistIndex) / Double(totalPlaylists)
        let withinPlaylist = currentTrackTotal > 0
            ? Double(currentTrackIndex) / Double(currentTrackTotal) / Double(totalPlaylists)
            : 0
        return min(playlistProgress + withinPlaylist, 1.0)
    }

    // MARK: - Private

    private let settings: AppSettings
    private let plexAPI: PlexAPIService
    private let entitlement: EntitlementManager?
    private var importTask: Task<Void, Never>?

    // MARK: - Init

    init(settings: AppSettings, plexAPI: PlexAPIService, entitlement: EntitlementManager? = nil) {
        self.settings    = settings
        self.plexAPI     = plexAPI
        self.entitlement = entitlement
    }

    // MARK: - Public API

    func startImport(
        playlists: [MusicPlaylist],
        duplicateAction: DuplicateAction
    ) {
        guard !playlists.isEmpty else { return }
        cancel()  // cancela cualquier import previo

        importLog = []
        errorMessage = nil
        matchResults = [:]
        totalPlaylists = playlists.count
        currentPlaylistIndex = 0

        importTask = Task {
            await runImport(playlists: playlists, duplicateAction: duplicateAction)
        }
    }

    func cancel() {
        importTask?.cancel()
        importTask = nil
        if isRunning { step = .cancelled }
    }

    /// Vuelve al estado inicial para permitir un nuevo import.
    func reset() {
        cancel()
        step = .idle
        matchResults = [:]
        importLog = []
        errorMessage = nil
        plexLoadProgress = 0
        currentPlaylistName = ""
        currentPlaylistIndex = 0
        totalPlaylists = 0
    }

    /// Devuelve el log como CSV listo para exportar.
    func exportCSV() -> String {
        let header = "Playlist,Total,Matched,Skipped,Unmatched,Action,Timestamp"
        let rows   = importLog.map { $0.csvRow }
        return ([header] + rows).joined(separator: "\n")
    }

    // MARK: - Import Workflow

    private func runImport(
        playlists: [MusicPlaylist],
        duplicateAction: DuplicateAction
    ) async {
        do {
            // ── 1. Asegurar que tenemos machineIdentifier ──────────────────────
            if settings.plexMachineIdentifier.isEmpty {
                step = .loadingPlex
                try await plexAPI.fetchAndStoreIdentity()
            }

            // ── 2. Asegurar que tenemos sectionID ─────────────────────────────
            if settings.plexLibrarySectionID.isEmpty {
                step = .loadingPlex
                try await plexAPI.fetchAndStoreMusicSection()
            }

            // ── 3. Cargar todos los tracks de Plex ────────────────────────────
            step = .loadingPlex
            plexLoadProgress = 0
            let plexTracks = try await plexAPI.fetchAllTracks { [weak self] p in
                Task { @MainActor [weak self] in self?.plexLoadProgress = p }
            }
            try Task.checkCancellation()

            // ── 4. Construir índice ───────────────────────────────────────────
            step = .buildingIndex
            let index = TrackMatchingService.buildIndex(
                from: plexTracks,
                localPrefix: settings.localPathPrefix,
                plexPrefix: settings.plexPathPrefix
            )
            try Task.checkCancellation()

            // ── 5. Cargar playlists existentes en Plex ────────────────────────
            let existingPlaylists = try await plexAPI.fetchPlaylists()
            let existingByName = Dictionary(
                existingPlaylists.map { ($0.title.lowercased(), $0) },
                uniquingKeysWith: { first, _ in first }
            )
            try Task.checkCancellation()

            // ── 6. Por cada playlist ──────────────────────────────────────────
            step = .matching
            for (idx, playlist) in playlists.enumerated() {
                try Task.checkCancellation()
                currentPlaylistIndex = idx
                currentPlaylistName  = playlist.name
                currentTrackTotal    = playlist.trackCount
                currentTrackIndex    = 0

                // Matchear tracks en background para no ahogar el MainActor
                // ni el autorelease pool con regex/strings temporales.
                let tracks = playlist.tracks
                let results: [String: MatchResult] = await Task.detached(priority: .userInitiated) { [index] in
                    TrackMatchingService.matchAll(tracks: tracks, index: index) { progressIdx in
                        Task { @MainActor [weak self] in
                            self?.currentTrackIndex = progressIdx
                        }
                    }
                }.value
                try Task.checkCancellation()
                currentTrackIndex = playlist.trackCount
                matchResults[playlist.name] = results

                // Extraer ratingKeys de los matched
                let ratingKeys = playlist.tracks.compactMap { track -> String? in
                    guard let result = results[track.persistentID],
                          let plexTrack = result.matchedTrack else { return nil }
                    return plexTrack.ratingKey
                }

                let matched   = ratingKeys.count
                let skipped   = results.values.filter { if case .skipped   = $0 { return true }; return false }.count
                let unmatched = results.values.filter { if case .unmatched = $0 { return true }; return false }.count

                // Crear / manejar duplicado
                step = .creating
                var logAction: String
                var plexPlaylistID: String?

                if ratingKeys.isEmpty {
                    logAction = "Skipped — no matched tracks"
                } else if let existing = existingByName[playlist.name.lowercased()] {
                    switch duplicateAction {
                    case .skip:
                        logAction = "Skipped — already exists"
                        plexPlaylistID = existing.ratingKey

                    case .replace:
                        try await plexAPI.deletePlaylist(id: existing.ratingKey)
                        let created = try await plexAPI.createPlaylist(name: playlist.name, ratingKeys: ratingKeys)
                        logAction = "Replaced"
                        plexPlaylistID = created.ratingKey

                    case .appendMissing:
                        let existingTracks = try await plexAPI.fetchPlaylistItems(id: existing.ratingKey)
                        let existingKeys = Set(existingTracks.map { $0.ratingKey })
                        let newKeys = ratingKeys.filter { !existingKeys.contains($0) }
                        if newKeys.isEmpty {
                            logAction = "Up to date — no new tracks"
                        } else {
                            try await plexAPI.addTracks(ratingKeys: newKeys, toPlaylist: existing.ratingKey)
                            logAction = "Appended \(newKeys.count) track\(newKeys.count == 1 ? "" : "s")"
                        }
                        plexPlaylistID = existing.ratingKey

                    case .rename:
                        let newName = uniqueName(base: playlist.name, existing: existingByName)
                        let created = try await plexAPI.createPlaylist(name: newName, ratingKeys: ratingKeys)
                        logAction = "Renamed → \(newName)"
                        plexPlaylistID = created.ratingKey
                    }
                } else {
                    let created = try await plexAPI.createPlaylist(name: playlist.name, ratingKeys: ratingKeys)
                    logAction = "Created"
                    plexPlaylistID = created.ratingKey
                }

                importLog.append(ImportLogEntry(
                    playlistName:    playlist.name,
                    tracksTotal:     playlist.trackCount,
                    tracksMatched:   matched,
                    tracksSkipped:   skipped,
                    tracksUnmatched: unmatched,
                    action:          logAction,
                    timestamp:       Date(),
                    plexPlaylistID:  plexPlaylistID
                ))

                step = .matching
            }

            currentPlaylistIndex = totalPlaylists
            step = .done
            // Contabilizar uso gratuito solo si el import efectivamente hizo trabajo
            // (al menos una playlist creada/replaced/appended).
            let didRealWork = importLog.contains { $0.plexPlaylistID != nil }
            if didRealWork {
                entitlement?.recordImportCompleted()
            }

        } catch is CancellationError {
            step = .cancelled
        } catch {
            errorMessage = error.localizedDescription
            step = .failed
        }
    }

    // MARK: - Helpers

    /// Genera un nombre único agregando "(2)", "(3)", etc. si ya existe.
    private func uniqueName(base: String, existing: [String: PlexPlaylist]) -> String {
        var counter = 2
        var candidate = "\(base) (\(counter))"
        while existing[candidate.lowercased()] != nil {
            counter += 1
            candidate = "\(base) (\(counter))"
        }
        return candidate
    }

    // MARK: - Match Override (para UI de Fase 6)

    /// Permite reemplazar manualmente el resultado de un track antes de importar.
    func setManualMatch(
        playlistName: String,
        persistentID: String,
        plexTrack: PlexTrack
    ) {
        matchResults[playlistName]?[persistentID] = .matched(plexTrack, confidence: 1.0, method: .manual)
    }

    func markSkipped(playlistName: String, persistentID: String) {
        matchResults[playlistName]?[persistentID] = .skipped
    }
}
