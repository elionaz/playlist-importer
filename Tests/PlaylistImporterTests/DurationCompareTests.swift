import Testing
@testable import PlaylistImporter

@Suite("DurationCompare")
struct DurationCompareTests {

    // MARK: - score

    @Test("Misma duración → 1.0")
    func sameDuration() {
        #expect(DurationCompare.score(trackMs: 200_000, plexMs: 200_000) == 1.0)
    }

    @Test("Diferencia exactamente en tolerancia (3000ms) → 1.0")
    func exactlyAtTolerance() {
        #expect(DurationCompare.score(trackMs: 200_000, plexMs: 203_000) == 1.0)
        #expect(DurationCompare.score(trackMs: 203_000, plexMs: 200_000) == 1.0)
    }

    @Test("Diferencia 1ms sobre tolerancia → 0.0")
    func oneOverTolerance() {
        #expect(DurationCompare.score(trackMs: 200_000, plexMs: 203_001) == 0.0)
    }

    @Test("Diferencia grande → 0.0")
    func largeDiff() {
        #expect(DurationCompare.score(trackMs: 180_000, plexMs: 300_000) == 0.0)
    }

    @Test("Diferencia negativa (track más largo) → mismo resultado")
    func negativeDiff() {
        #expect(DurationCompare.score(trackMs: 203_000, plexMs: 200_000) == 1.0)
    }

    // MARK: - isMatch

    @Test("Misma duración → true")
    func sameDurationIsMatch() {
        #expect(DurationCompare.isMatch(trackMs: 180_000, plexMs: 180_000))
    }

    @Test("Dentro de tolerancia → true")
    func withinTolerance() {
        #expect(DurationCompare.isMatch(trackMs: 180_000, plexMs: 182_999))
    }

    @Test("En el límite exacto → true")
    func atLimit() {
        #expect(DurationCompare.isMatch(trackMs: 180_000, plexMs: 183_000))
    }

    @Test("1ms fuera de tolerancia → false")
    func justOutsideTolerance() {
        #expect(!DurationCompare.isMatch(trackMs: 180_000, plexMs: 183_001))
    }

    @Test("Tolerancia es ±3 segundos (valor constante)")
    func toleranceValue() {
        #expect(DurationCompare.toleranceMs == 3_000)
    }
}
