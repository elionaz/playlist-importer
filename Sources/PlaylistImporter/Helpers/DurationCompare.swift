import Foundation

// MARK: - DurationCompare

enum DurationCompare {
    /// Tolerancia en milisegundos (±3 segundos).
    static let toleranceMs: Int = 3_000

    /// Devuelve 1.0 si la diferencia es ≤ tolerancia, 0.0 si es mayor.
    static func score(trackMs: Int, plexMs: Int) -> Double {
        abs(trackMs - plexMs) <= toleranceMs ? 1.0 : 0.0
    }

    static func isMatch(trackMs: Int, plexMs: Int) -> Bool {
        abs(trackMs - plexMs) <= toleranceMs
    }
}
