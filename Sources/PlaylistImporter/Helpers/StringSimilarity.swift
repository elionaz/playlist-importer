import Foundation

// MARK: - StringSimilarity

enum StringSimilarity {

    /// Score de similitud normalizado 0.0–1.0 (1.0 = idéntico).
    static func score(_ a: String, _ b: String) -> Double {
        scoreNormalized(normalize(a), normalize(b))
    }

    /// Score asumiendo que ambas cadenas YA están normalizadas.
    /// Úsalo en hot loops para evitar repetir la regex de `normalize` por cada comparación.
    static func scoreNormalized(_ a: String, _ b: String) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 1.0 }
        guard !a.isEmpty, !b.isEmpty  else { return 0.0 }
        if a == b { return 1.0 }

        let dist = levenshtein(a, b)
        let maxLen = Double(max(a.count, b.count))
        return max(0, 1.0 - Double(dist) / maxLen)
    }

    // MARK: - Normalization

    /// Quita ruido común en títulos/artistas de música para mejorar el matching.
    static func normalize(_ s: String) -> String {
        var result = s.lowercased()

        // Quitar paréntesis/corchetes con contenido típico de versiones
        let noisePatterns = [
            #"\s*[\(\[](feat\.?|ft\.?|featuring)[^\)\]]*[\)\]]"#,   // (feat. X)
            #"\s*[\(\[](remaster(ed)?|remastered \d{4})[^\)\]]*[\)\]]"#,
            #"\s*[\(\[](live( at [^\)\]]*)?)[^\)\]]*[\)\]]"#,
            #"\s*[\(\[](radio edit|single version|album version|explicit)[^\)\]]*[\)\]]"#,
            #"\s*[\(\[]\d{4}( remaster)?\]"#,
        ]
        for pattern in noisePatterns {
            result = result.replacingOccurrences(
                of: pattern, with: "", options: .regularExpression
            )
        }

        // Quitar puntuación excepto letras, números y espacios
        result = result.components(separatedBy: .punctuationCharacters).joined(separator: " ")
        // Colapsar espacios
        result = result.components(separatedBy: .whitespaces)
                       .filter { !$0.isEmpty }
                       .joined(separator: " ")
                       .trimmingCharacters(in: .whitespaces)

        return result
    }

    // MARK: - Levenshtein (O(min(m,n)) space)

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        let m = aChars.count
        let n = bChars.count
        if m == 0 { return n }
        if n == 0 { return m }

        var prev = Array(0...n)
        var curr = [Int](repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                if aChars[i - 1] == bChars[j - 1] {
                    curr[j] = prev[j - 1]
                } else {
                    curr[j] = 1 + min(prev[j], curr[j - 1], prev[j - 1])
                }
            }
            swap(&prev, &curr)
        }
        return prev[n]
    }
}
