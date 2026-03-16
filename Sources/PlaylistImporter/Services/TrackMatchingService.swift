import Foundation

// MARK: - TrackMatchingService

/// Servicio sin estado que matchea MusicTracks contra un índice de PlexTracks.
/// L1: matching por file path normalizado.
/// L2: matching fuzzy por metadata (título, artista, álbum, duración).
enum TrackMatchingService {

    // MARK: - Thresholds

    static let autoMatchThreshold:   Double = 0.85
    static let ambiguousThreshold:   Double = 0.60

    // Score weights
    private static let wTitle:    Double = 0.40
    private static let wArtist:   Double = 0.30
    private static let wAlbum:    Double = 0.20
    private static let wDuration: Double = 0.10
    private static let bonusYear: Double = 0.05

    // MARK: - Index Building

    static func buildIndex(
        from plexTracks: [PlexTrack],
        localPrefix: String,
        plexPrefix: String
    ) -> MatchIndex {
        var pathIndex:   [String: PlexTrack]     = [:]
        var artistIndex: [String: [PlexTrack]]   = [:]

        for track in plexTracks {
            // L1 path index
            if let path = track.filePath {
                let normalized = normalizePath(path, removing: plexPrefix, replacing: localPrefix)
                pathIndex[normalized] = track
            }

            // L2 artist bucket (normalized)
            let artistKey = StringSimilarity.normalize(track.artist)
            if !artistKey.isEmpty {
                artistIndex[artistKey, default: []].append(track)
            }
        }

        return MatchIndex(
            pathIndex:   pathIndex,
            artistIndex: artistIndex,
            allTracks:   plexTracks,
            localPrefix: localPrefix,
            plexPrefix:  plexPrefix
        )
    }

    // MARK: - Match (L1 + L2)

    static func match(_ track: MusicTrack, index: MatchIndex) -> MatchResult {

        // ── L1: file path exacto ────────────────────────────────────────────
        if let filePath = track.filePath, !filePath.isEmpty {
            let normalized = normalizePath(filePath,
                                           removing: index.localPrefix,
                                           replacing: index.plexPrefix)
            if let plexTrack = index.pathIndex[normalized] {
                return .matched(plexTrack, confidence: 1.0, method: .filePath)
            }
            if let plexTrack = index.pathIndex[filePath] {
                return .matched(plexTrack, confidence: 1.0, method: .filePath)
            }
        }

        // ── L2: fuzzy metadata ──────────────────────────────────────────────
        return matchL2(track, index: index)
    }

    static func matchAll(tracks: [MusicTrack], index: MatchIndex) -> [String: MatchResult] {
        var results: [String: MatchResult] = [:]
        for track in tracks {
            results[track.persistentID] = match(track, index: index)
        }
        return results
    }

    // MARK: - L2 Implementation

    private static func matchL2(_ track: MusicTrack, index: MatchIndex) -> MatchResult {
        let candidates = findCandidates(for: track, index: index)
        guard !candidates.isEmpty else { return .unmatched }

        // Score cada candidato
        let scored = candidates
            .map { ($0, metadataScore(track: track, plex: $0)) }
            .filter { $0.1 >= ambiguousThreshold }
            .sorted { $0.1 > $1.1 }

        guard let (best, bestScore) = scored.first else { return .unmatched }

        if bestScore >= autoMatchThreshold {
            return .matched(best, confidence: bestScore, method: .metadata)
        }

        // Entre 0.60 y 0.85 → ambiguous si hay varios candidatos cercanos
        let nearBest = scored.filter { abs($0.1 - bestScore) < 0.10 }.map { $0.0 }
        if nearBest.count > 1 {
            return .ambiguous(nearBest)
        }
        return .ambiguous([best])
    }

    /// Obtiene candidatos del artistIndex + fallback al catálogo completo si no hay artista.
    private static func findCandidates(for track: MusicTrack, index: MatchIndex) -> [PlexTrack] {
        let normArtist = StringSimilarity.normalize(track.artist)

        // Búsqueda exacta por artista normalizado
        if !normArtist.isEmpty, let exact = index.artistIndex[normArtist] {
            return exact
        }

        // Búsqueda por similitud de artista (toma los buckets con score > 0.75)
        if !normArtist.isEmpty {
            let similar = index.artistIndex
                .filter { StringSimilarity.score($0.key, normArtist) > 0.75 }
                .flatMap { $0.value }
            if !similar.isEmpty { return similar }
        }

        // Sin artista o ningún match de artista → buscar solo por título en todo el catálogo
        // (limitado a los primeros 200 candidatos por título para no ser O(n))
        let normTitle = StringSimilarity.normalize(track.title)
        return index.allTracks
            .filter { StringSimilarity.score(StringSimilarity.normalize($0.title), normTitle) > 0.70 }
            .prefix(200)
            .map { $0 }
    }

    // MARK: - Metadata Score

    /// Score ponderado 0.0–1.0+bonus entre un MusicTrack y un PlexTrack.
    static func metadataScore(track: MusicTrack, plex: PlexTrack) -> Double {
        let titleScore  = StringSimilarity.score(track.title,  plex.title)
        let artistScore = StringSimilarity.score(track.artist, plex.artist)
        let albumScore  = StringSimilarity.score(track.album,  plex.album)
        let durScore    = DurationCompare.score(trackMs: track.durationMs, plexMs: plex.duration)

        var score = titleScore  * wTitle
                  + artistScore * wArtist
                  + albumScore  * wAlbum
                  + durScore    * wDuration

        // Bonus por año exacto
        if let ty = track.year, let py = plex.year, ty == py {
            score += bonusYear
        }

        return min(score, 1.0)
    }

    // MARK: - Path Normalization

    static func normalizePath(
        _ path: String,
        removing removePrefix: String,
        replacing replacePrefix: String
    ) -> String {
        let clean   = removePrefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let replace = replacePrefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !clean.isEmpty else { return path }

        let lowPath   = path.lowercased().replacingOccurrences(of: "\\", with: "/")
        let lowClean  = ("/" + clean + "/").lowercased()
        let lowClean2 = ("/" + clean).lowercased()

        var suffix: String
        if lowPath.hasPrefix(lowClean) {
            suffix = String(path.dropFirst(lowClean.count - 1))
        } else if lowPath.hasPrefix(lowClean2) {
            suffix = String(path.dropFirst(lowClean2.count))
            if !suffix.hasPrefix("/") { suffix = "/" + suffix }
        } else {
            return path
        }

        return replace.isEmpty ? suffix : "/" + replace + suffix
    }
}

// MARK: - MatchIndex

struct MatchIndex: Sendable {
    let pathIndex:   [String: PlexTrack]
    let artistIndex: [String: [PlexTrack]]  // normalized artist → tracks (para L2)
    let allTracks:   [PlexTrack]
    let localPrefix: String
    let plexPrefix:  String

    var trackCount: Int       { allTracks.count }
    var indexedPathCount: Int { pathIndex.count }
}
