import Foundation

// MARK: - PlexPlaylist (domain model)

struct PlexPlaylist: Identifiable, Sendable {
    let id: String      // = ratingKey
    let ratingKey: String
    let title: String
    let trackCount: Int
}

// MARK: - Decodable response types

struct PlexPlaylistsContainer: Decodable {
    let mediaContainer: PlexPlaylistsMediaContainer

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

struct PlexPlaylistsMediaContainer: Decodable {
    let metadata: [PlexPlaylistResponse]?

    enum CodingKeys: String, CodingKey {
        case metadata = "Metadata"
    }
}

struct PlexPlaylistResponse: Decodable {
    let ratingKey: String
    let title: String
    let leafCount: Int?
}

// MARK: - Conversion

extension PlexPlaylist {
    init(from response: PlexPlaylistResponse) {
        self.ratingKey  = response.ratingKey
        self.id         = response.ratingKey
        self.title      = response.title
        self.trackCount = response.leafCount ?? 0
    }
}
