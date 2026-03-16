import Foundation

// MARK: - PlexLibrarySection (domain model)

struct PlexLibrarySection: Identifiable, Sendable {
    let id: String      // = key
    let key: String
    let title: String
    let type: String    // "artist" for music, "movie", "show", etc.

    var isMusic: Bool { type == "artist" }
}

// MARK: - Decodable response types

struct PlexSectionsContainer: Decodable {
    let mediaContainer: PlexSectionsMediaContainer

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

struct PlexSectionsMediaContainer: Decodable {
    let directory: [PlexSectionResponse]?

    enum CodingKeys: String, CodingKey {
        case directory = "Directory"
    }
}

struct PlexSectionResponse: Decodable {
    let key: String
    let title: String
    let type: String
}

// MARK: - Identity response

struct PlexIdentityContainer: Decodable {
    let mediaContainer: PlexIdentityMediaContainer

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

struct PlexIdentityMediaContainer: Decodable {
    let machineIdentifier: String
}

// MARK: - Conversion

extension PlexLibrarySection {
    init(from response: PlexSectionResponse) {
        self.key   = response.key
        self.id    = response.key
        self.title = response.title
        self.type  = response.type
    }
}
