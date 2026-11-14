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

    // Límite duro de candidatos para el fallback por título.
    private static let titleFallbackLimit: Int = 200
    private static let artistSimilarityThreshold: Double = 0.75
    private static let titleFallbackThreshold:    Double = 0.70

    // MARK: - Index Building

    static func buildIndex(
        from plexTracks: [PlexTrack],
        localPrefix: String,
        plexPrefix: String
    ) -> MatchIndex {
        var pathIndex:   [String: PlexTrack]            = [:]
        var artistIndex: [String: [PlexTrackNorm]]      = [:]
        var allNorm:     [PlexTrackNorm]                = []
        allNorm.reserveCapacity(plexTracks.count)

        for track in plexTracks {
            // L1 path index
            if let path = track.filePath {
                let normalized = normalizePath(path, removing: plexPrefix, replacing: localPrefix)
                pathIndex[normalized] = track
            }

            // Pre-normalizar para evitar miles de regex en el hot loop
            let norm = PlexTrackNorm(
                track:      track,
                normTitle:  StringSimilarity.normalize(track.title),
                normArtist: StringSimilarity.normalize(track.artist),
                normAlbum:  StringSimilarity.normalize(track.album)
            )

            if !norm.normArtist.isEmpty {
                artistIndex[norm.normArtist, default: []].append(norm)
            }
            allNorm.append(norm)
        }

        return MatchIndex(
            pathIndex:   pathIndex,
            artistIndex: artistIndex,
            allTracks:   allNorm,
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

        // ── L2: pre-normalizar el MusicTrack una sola vez ───────────────────
        let normTrack = MusicTrackNorm(
            normTitle:  StringSimilarity.normalize(track.title),
            normArtist: StringSimilarity.normalize(track.artist),
            normAlbum:  StringSimilarity.normalize(track.album),
            durationMs: track.durationMs,
            year:       track.year
        )
        return matchL2(normTrack, index: index)
    }

    /// Matchea un batch de tracks. Diseñado para correr en background — no toca MainActor.
    /// `onProgress` se invoca periódicamente con el índice actual; el caller decide cómo publicar.
    static func matchAll(
        tracks: [MusicTrack],
        index: MatchIndex,
        onProgress: (@Sendable (Int) -> Void)? = nil
    ) -> [String: MatchResult] {
        var results: [String: MatchResult] = [:]
        results.reserveCapacity(tracks.count)

        // Procesamos en chunks envueltos en autoreleasepool para drenar los
        // NSString/NSRegularExpression que Foundation deja atrás.
        let chunk = 100
        var i = 0
        while i < tracks.count {
            let end = Swift.min(i + chunk, tracks.count)
            autoreleasepool {
                for j in i..<end {
                    let track = tracks[j]
                    results[track.persistentID] = match(track, index: index)
                }
            }
            onProgress?(end)
            i = end
        }
        return results
    }

    // MARK: - L2 Implementation

    private static func matchL2(_ track: MusicTrackNorm, index: MatchIndex) -> MatchResult {
        let candidates = findCandidates(for: track, index: index)
        guard !candidates.isEmpty else { return .unmatched }

        // Score cada candidato usando strings YA normalizados.
        let scored: [(PlexTrack, Double)] = candidates
            .map { ($0.track, metadataScoreNorm(track: track, plex: $0)) }
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
    private static func findCandidates(for track: MusicTrackNorm, index: MatchIndex) -> [PlexTrackNorm] {
        let normArtist = track.normArtist

        // 1) Match exacto por artista normalizado (sin regex, sin allocs extra).
        if !normArtist.isEmpty, let exact = index.artistIndex[normArtist] {
            return exact
        }

        // 2) Búsqueda por similitud de artista entre los buckets — sin re-normalizar.
        if !normArtist.isEmpty {
            var similar: [PlexTrackNorm] = []
            for (key, bucket) in index.artistIndex {
                if StringSimilarity.scoreNormalized(key, normArtist) > artistSimilarityThreshold {
                    similar.append(contentsOf: bucket)
                }
            }
            if !similar.isEmpty { return similar }
        }

        // 3) Fallback por título sobre todo el catálogo, con corte temprano.
        //    `index.allTracks` ya tiene normTitle precomputado, así que solo
        //    se ejecuta Levenshtein — nada de regex aquí.
        let normTitle = track.normTitle
        guard !normTitle.isEmpty else { return [] }

        var results: [PlexTrackNorm] = []
        results.reserveCapacity(titleFallbackLimit)
        for p in index.allTracks {
            if StringSimilarity.scoreNormalized(p.normTitle, normTitle) > titleFallbackThreshold {
                results.append(p)
                if results.count >= titleFallbackLimit { break }
            }
        }
        return results
    }

    // MARK: - Metadata Score (public — usado por tests y por matching)

    /// Score ponderado 0.0–1.0+bonus entre un MusicTrack y un PlexTrack.
    /// API pública: normaliza ambos lados al vuelo (úsala fuera de hot loops).
    static func metadataScore(track: MusicTrack, plex: PlexTrack) -> Double {
        let normTrack = MusicTrackNorm(
            normTitle:  StringSimilarity.normalize(track.title),
            normArtist: StringSimilarity.normalize(track.artist),
            normAlbum:  StringSimilarity.normalize(track.album),
            durationMs: track.durationMs,
            year:       track.year
        )
        let normPlex = PlexTrackNorm(
            track:      plex,
            normTitle:  StringSimilarity.normalize(plex.title),
            normArtist: StringSimilarity.normalize(plex.artist),
            normAlbum:  StringSimilarity.normalize(plex.album)
        )
        return metadataScoreNorm(track: normTrack, plex: normPlex)
    }

    /// Variante interna que asume los strings ya normalizados.
    private static func metadataScoreNorm(track: MusicTrackNorm, plex: PlexTrackNorm) -> Double {
        let titleScore  = StringSimilarity.scoreNormalized(track.normTitle,  plex.normTitle)
        let artistScore = StringSimilarity.scoreNormalized(track.normArtist, plex.normArtist)
        let albumScore  = StringSimilarity.scoreNormalized(track.normAlbum,  plex.normAlbum)
        let durScore    = DurationCompare.score(trackMs: track.durationMs, plexMs: plex.track.duration)

        var score = titleScore  * wTitle
                  + artistScore * wArtist
                  + albumScore  * wAlbum
                  + durScore    * wDuration

        if let ty = track.year, let py = plex.track.year, ty == py {
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

// MARK: - Normalized projections

struct PlexTrackNorm: Sendable {
    let track:      PlexTrack
    let normTitle:  String
    let normArtist: String
    let normAlbum:  String
}

struct MusicTrackNorm: Sendable {
    let normTitle:  String
    let normArtist: String
    let normAlbum:  String
    let durationMs: Int
    let year:       Int?
}

// MARK: - MatchIndex

struct MatchIndex: Sendable {
    let pathIndex:   [String: PlexTrack]
    let artistIndex: [String: [PlexTrackNorm]]  // normalized artist → tracks (para L2)
    let allTracks:   [PlexTrackNorm]
    let localPrefix: String
    let plexPrefix:  String

    var trackCount: Int       { allTracks.count }
    var indexedPathCount: Int { pathIndex.count }
}
