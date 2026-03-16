import Foundation

// MARK: - MatchMethod

enum MatchMethod: String, Sendable {
    case filePath   = "File Path"
    case metadata   = "Metadata"
    case manual     = "Manual"
}

// MARK: - MatchResult

enum MatchResult: Sendable {
    /// Match encontrado con confianza suficiente.
    case matched(PlexTrack, confidence: Double, method: MatchMethod)
    /// Varios candidatos — requiere elección manual.
    case ambiguous([PlexTrack])
    /// Sin match encontrado.
    case unmatched
    /// Track de streaming (sin archivo local y sin match en Plex).
    case skipped

    // MARK: Helpers

    var isResolved: Bool {
        if case .matched = self { return true }
        if case .skipped = self { return true }
        return false
    }

    var matchedTrack: PlexTrack? {
        if case .matched(let t, _, _) = self { return t }
        return nil
    }

    var statusLabel: String {
        switch self {
        case .matched(_, let c, let m): return "\(m.rawValue) (\(Int(c * 100))%)"
        case .ambiguous(let c):         return "Ambiguous (\(c.count) candidates)"
        case .unmatched:                return "No match"
        case .skipped:                  return "Streaming only"
        }
    }
}
