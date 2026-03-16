import Testing
@testable import PlaylistImporter

// MARK: - Helpers

private func makeMusic(
    id: String = "1",
    title: String,
    artist: String = "",
    album: String = "",
    year: Int? = nil,
    durationSec: Double = 200,
    filePath: String? = nil
) -> MusicTrack {
    MusicTrack(
        id: id,
        persistentID: id,
        title: title,
        artist: artist,
        album: album,
        year: year,
        duration: durationSec,
        filePath: filePath
    )
}

private func makePlex(
    id: String = "p1",
    title: String,
    artist: String = "",
    album: String = "",
    year: Int? = nil,
    durationMs: Int = 200_000,
    filePath: String? = nil
) -> PlexTrack {
    PlexTrack(
        id: id,
        ratingKey: id,
        title: title,
        artist: artist,
        album: album,
        duration: durationMs,
        year: year,
        filePath: filePath
    )
}

// MARK: - normalizePath

@Suite("TrackMatchingService.normalizePath")
struct NormalizePathTests {

    @Test("Prefix vacío → path sin cambios")
    func emptyPrefix() {
        let result = TrackMatchingService.normalizePath(
            "/music/track.mp3", removing: "", replacing: "local"
        )
        #expect(result == "/music/track.mp3")
    }

    @Test("Reemplaza prefijo con barra final incluida")
    func replacePrefixWithTrailingSlash() {
        let result = TrackMatchingService.normalizePath(
            "/plex/music/track.mp3", removing: "plex", replacing: "local"
        )
        #expect(result == "/local/music/track.mp3")
    }

    @Test("Reemplaza prefijo sin barra final")
    func replacePrefixWithoutTrailingSlash() {
        let result = TrackMatchingService.normalizePath(
            "/plex/music/track.mp3", removing: "/plex", replacing: "local"
        )
        #expect(result == "/local/music/track.mp3")
    }

    @Test("Prefijo no coincide → path sin cambios")
    func nonMatchingPrefix() {
        let result = TrackMatchingService.normalizePath(
            "/other/music/track.mp3", removing: "plex", replacing: "local"
        )
        #expect(result == "/other/music/track.mp3")
    }

    @Test("Replace vacío → quita solo el prefijo")
    func emptyReplace() {
        let result = TrackMatchingService.normalizePath(
            "/plex/music/track.mp3", removing: "plex", replacing: ""
        )
        #expect(result == "/music/track.mp3")
    }

    @Test("Case insensitive")
    func caseInsensitive() {
        let result = TrackMatchingService.normalizePath(
            "/PLEX/Music/Track.mp3", removing: "plex", replacing: "local"
        )
        // El path resultante conserva el case original salvo el prefijo
        #expect(result.hasPrefix("/local/"))
    }

    @Test("Prefijo con barras extras se maneja correctamente")
    func prefixWithSlashes() {
        let result = TrackMatchingService.normalizePath(
            "/media/plex/music/track.mp3", removing: "plex", replacing: "local"
        )
        // El prefijo /plex no está al inicio → sin cambios
        #expect(result == "/media/plex/music/track.mp3")
    }
}

// MARK: - metadataScore

@Suite("TrackMatchingService.metadataScore")
struct MetadataScoreTests {

    @Test("Tracks idénticos → score 1.0")
    func identicalTracks() {
        let music = makeMusic(title: "Song", artist: "Artist", album: "Album", year: 2020, durationSec: 200)
        let plex  = makePlex(title: "Song", artist: "Artist", album: "Album", year: 2020, durationMs: 200_000)
        let score = TrackMatchingService.metadataScore(track: music, plex: plex)
        #expect(score == 1.0)
    }

    @Test("Score está siempre en [0, 1]")
    func scoreInRange() {
        let music = makeMusic(title: "X", artist: "Y", album: "Z", durationSec: 100)
        let plex  = makePlex(title: "A", artist: "B", album: "C", durationMs: 999_999)
        let score = TrackMatchingService.metadataScore(track: music, plex: plex)
        #expect(score >= 0.0 && score <= 1.0)
    }

    @Test("Mismo título+artista+duración, álbum completamente diferente → score ≥ 0.80")
    func sameTitleArtistDuration() {
        // Álbumes con 0 similitud para aislar el peso de los otros campos
        let music = makeMusic(title: "Song", artist: "Artist", album: "AAAA AAAA AAAA", durationSec: 200)
        let plex  = makePlex(title: "Song", artist: "Artist", album: "ZZZZ ZZZZ ZZZZ", durationMs: 200_000)
        let score = TrackMatchingService.metadataScore(track: music, plex: plex)
        // title(1.0)*0.40 + artist(1.0)*0.30 + album(~0)*0.20 + duration(1.0)*0.10 = ~0.80
        #expect(score >= 0.78 && score <= 0.85)
    }

    @Test("Título completamente distinto → score bajo")
    func differentTitle() {
        let music = makeMusic(title: "AAAA", artist: "Artist", album: "Album", durationSec: 200)
        let plex  = makePlex(title: "ZZZZ", artist: "Artist", album: "Album", durationMs: 200_000)
        let score = TrackMatchingService.metadataScore(track: music, plex: plex)
        #expect(score < 0.7)
    }

    @Test("Bonus de año incrementa el score cuando coincide")
    func yearBonus() {
        let musicNoYear  = makeMusic(title: "Song", artist: "Artist", album: "Album", year: nil,  durationSec: 200)
        let musicYear    = makeMusic(title: "Song", artist: "Artist", album: "Album", year: 2020, durationSec: 200)
        let plex         = makePlex(title: "Song", artist: "Artist", album: "Album", year: 2020, durationMs: 200_000)

        let scoreNoYear = TrackMatchingService.metadataScore(track: musicNoYear, plex: plex)
        let scoreYear   = TrackMatchingService.metadataScore(track: musicYear,   plex: plex)
        #expect(scoreYear > scoreNoYear)
    }

    @Test("Duración fuera de tolerancia reduce el score")
    func durationPenalty() {
        let music = makeMusic(title: "Song", artist: "Artist", album: "Album", durationSec: 200)
        let plexOk  = makePlex(title: "Song", artist: "Artist", album: "Album", durationMs: 200_000)
        let plexBad = makePlex(title: "Song", artist: "Artist", album: "Album", durationMs: 999_000)
        let scoreOk  = TrackMatchingService.metadataScore(track: music, plex: plexOk)
        let scoreBad = TrackMatchingService.metadataScore(track: music, plex: plexBad)
        #expect(scoreOk > scoreBad)
    }
}

// MARK: - buildIndex + match

@Suite("TrackMatchingService.buildIndex + match")
struct MatchTests {

    private func makeIndex(_ plexTracks: [PlexTrack], localPrefix: String = "", plexPrefix: String = "") -> MatchIndex {
        TrackMatchingService.buildIndex(from: plexTracks, localPrefix: localPrefix, plexPrefix: plexPrefix)
    }

    @Test("buildIndex incluye todos los tracks en allTracks")
    func indexContainsAllTracks() {
        let tracks = [
            makePlex(id: "1", title: "A", artist: "X"),
            makePlex(id: "2", title: "B", artist: "Y"),
        ]
        let index = makeIndex(tracks)
        #expect(index.trackCount == 2)
    }

    @Test("buildIndex indexa path cuando está disponible")
    func indexesFilePath() {
        let tracks = [makePlex(id: "1", title: "A", artist: "X", filePath: "/plex/music/a.mp3")]
        let index = makeIndex(tracks, localPrefix: "local", plexPrefix: "plex")
        #expect(index.indexedPathCount == 1)
    }

    @Test("L1: match por file path exacto → confidence 1.0, method .filePath")
    func l1PathMatch() {
        let filePath = "/music/track.mp3"
        let plex  = makePlex(id: "1", title: "Track", artist: "Artist", filePath: filePath)
        let index = makeIndex([plex])
        let music = makeMusic(title: "Track", artist: "Artist", filePath: filePath)

        let result = TrackMatchingService.match(music, index: index)
        if case .matched(let t, let c, let m) = result {
            #expect(t.id == "1")
            #expect(c == 1.0)
            #expect(m == .filePath)
        } else {
            Issue.record("Esperaba .matched pero got \(result)")
        }
    }

    @Test("L2: match por metadata → .matched con method .metadata")
    func l2MetadataMatch() {
        let plex  = makePlex(id: "1", title: "Bohemian Rhapsody", artist: "Queen", album: "A Night at the Opera", durationMs: 354_000)
        let index = makeIndex([plex])
        let music = makeMusic(title: "Bohemian Rhapsody", artist: "Queen", album: "A Night at the Opera", durationSec: 354)

        let result = TrackMatchingService.match(music, index: index)
        if case .matched(_, _, let m) = result {
            #expect(m == .metadata)
        } else {
            Issue.record("Esperaba .matched pero got \(result)")
        }
    }

    @Test("Sin candidatos → .unmatched")
    func noMatch() {
        let plex  = makePlex(id: "1", title: "ZZZZZZ", artist: "ZZZZZ")
        let index = makeIndex([plex])
        let music = makeMusic(title: "AAAAAA", artist: "AAAAA")

        let result = TrackMatchingService.match(music, index: index)
        if case .unmatched = result {
            // OK
        } else {
            Issue.record("Esperaba .unmatched pero got \(result)")
        }
    }

    @Test("matchAll devuelve resultado por cada track")
    func matchAll() {
        let plexTracks = [
            makePlex(id: "p1", title: "Song One", artist: "Artist A"),
            makePlex(id: "p2", title: "Song Two", artist: "Artist B"),
        ]
        let index = makeIndex(plexTracks)
        let musicTracks = [
            makeMusic(id: "m1", title: "Song One", artist: "Artist A"),
            makeMusic(id: "m2", title: "Song Two", artist: "Artist B"),
        ]

        let results = TrackMatchingService.matchAll(tracks: musicTracks, index: index)
        #expect(results.count == 2)
        #expect(results["m1"] != nil)
        #expect(results["m2"] != nil)
    }

    @Test("Track L1 tiene prioridad sobre L2 aunque metadata también coincida")
    func l1HasPriorityOverL2() {
        let filePath = "/music/track.mp3"
        let plex = makePlex(id: "p1", title: "Track", artist: "Artist",
                            durationMs: 200_000, filePath: filePath)
        let index = makeIndex([plex])
        let music = makeMusic(title: "Track", artist: "Artist", durationSec: 200, filePath: filePath)

        let result = TrackMatchingService.match(music, index: index)
        if case .matched(_, let c, let m) = result {
            #expect(m == .filePath)
            #expect(c == 1.0)
        } else {
            Issue.record("Esperaba .matched(filePath) pero got \(result)")
        }
    }
}

// MARK: - MatchResult helpers

@Suite("MatchResult helpers")
struct MatchResultTests {

    @Test("isResolved es true para .matched")
    func matchedIsResolved() {
        let plex = makePlex(id: "1", title: "T")
        let result = MatchResult.matched(plex, confidence: 0.9, method: .metadata)
        #expect(result.isResolved)
    }

    @Test("isResolved es true para .skipped")
    func skippedIsResolved() {
        #expect(MatchResult.skipped.isResolved)
    }

    @Test("isResolved es false para .unmatched")
    func unmatchedNotResolved() {
        #expect(!MatchResult.unmatched.isResolved)
    }

    @Test("isResolved es false para .ambiguous")
    func ambiguousNotResolved() {
        let plex = makePlex(id: "1", title: "T")
        #expect(!MatchResult.ambiguous([plex]).isResolved)
    }

    @Test("matchedTrack devuelve el track correcto")
    func matchedTrackAccessor() {
        let plex = makePlex(id: "42", title: "T")
        let result = MatchResult.matched(plex, confidence: 0.95, method: .filePath)
        #expect(result.matchedTrack?.id == "42")
    }

    @Test("matchedTrack es nil para .unmatched")
    func matchedTrackNilForUnmatched() {
        #expect(MatchResult.unmatched.matchedTrack == nil)
    }

    @Test("statusLabel muestra porcentaje para .matched")
    func statusLabelMatched() {
        let plex = makePlex(id: "1", title: "T")
        let result = MatchResult.matched(plex, confidence: 0.92, method: .metadata)
        #expect(result.statusLabel.contains("92%"))
        #expect(result.statusLabel.contains("Metadata"))
    }

    @Test("statusLabel para .unmatched")
    func statusLabelUnmatched() {
        #expect(MatchResult.unmatched.statusLabel == "No match")
    }

    @Test("statusLabel para .skipped")
    func statusLabelSkipped() {
        #expect(MatchResult.skipped.statusLabel == "Streaming only")
    }
}
