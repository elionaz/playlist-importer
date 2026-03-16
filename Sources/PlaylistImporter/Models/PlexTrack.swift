import Foundation

// MARK: - PlexTrack (domain model)

struct PlexTrack: Identifiable, Sendable {
    let id: String          // = ratingKey
    let ratingKey: String
    let title: String
    let artist: String      // grandparentTitle
    let album: String       // parentTitle
    let duration: Int       // milliseconds
    let year: Int?
    let filePath: String?   // server-side file path from Media[0].Part[0].file
}

// MARK: - Decodable response types (Plex JSON envelope)

struct PlexTracksContainer: Decodable {
    let mediaContainer: PlexTracksMediaContainer

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

struct PlexTracksMediaContainer: Decodable {
    let size: Int
    let totalSize: Int?
    let offset: Int?
    let metadata: [PlexTrackResponse]?

    enum CodingKeys: String, CodingKey {
        case size
        case totalSize
        case offset
        case metadata = "Metadata"
    }
}

struct PlexTrackResponse: Decodable {
    let ratingKey: String
    let title: String
    let grandparentTitle: String?
    let parentTitle: String?
    let duration: Int?
    let year: Int?
    let media: [PlexMediaItem]?

    enum CodingKeys: String, CodingKey {
        case ratingKey
        case title
        case grandparentTitle
        case parentTitle
        case duration
        case year
        case media = "Media"
    }

    struct PlexMediaItem: Decodable {
        let part: [PlexPart]

        enum CodingKeys: String, CodingKey {
            case part = "Part"
        }

        struct PlexPart: Decodable {
            let file: String?
        }
    }
}

// MARK: - Conversion

extension PlexTrack {
    init(from response: PlexTrackResponse) {
        self.ratingKey = response.ratingKey
        self.id        = response.ratingKey
        self.title     = response.title
        self.artist    = response.grandparentTitle ?? ""
        self.album     = response.parentTitle ?? ""
        self.duration  = response.duration ?? 0
        self.year      = response.year
        self.filePath  = response.media?.first?.part.first?.file
    }
}
