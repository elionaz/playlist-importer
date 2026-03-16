import Foundation

struct MusicTrack: Identifiable, Sendable {
    let id: String          // = persistentID
    let persistentID: String
    let title: String
    let artist: String
    let album: String
    let year: Int?
    let duration: Double    // segundos (AppleScript devuelve Double)
    let filePath: String?   // nil para tracks de iCloud / Apple Music streaming

    /// Duración en milisegundos para comparar con Plex
    var durationMs: Int { Int(duration * 1000) }
}
