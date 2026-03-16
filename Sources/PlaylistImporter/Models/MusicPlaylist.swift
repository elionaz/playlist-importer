import Foundation

struct MusicPlaylist: Identifiable, Sendable {
    let id: String      // nombre de la playlist (único en Music)
    let name: String
    var tracks: [MusicTrack]

    var trackCount: Int { tracks.count }
}
