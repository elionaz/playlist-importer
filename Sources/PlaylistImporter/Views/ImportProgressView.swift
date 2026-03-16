import SwiftUI
import UniformTypeIdentifiers

struct ImportProgressView: View {
    @Environment(ImportManager.self) private var importManager

    @Binding var selectedNames: Set<String>
    @Binding var duplicateAction: DuplicateAction
    let loadedPlaylists: [String: MusicPlaylist]
    let onImport: () -> Void

    @State private var exportItem: CSVDocument?
    @State private var showExporter = false

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Import")
                    .font(.headline)
                Spacer()
                // Reset button cuando hay algo que limpiar
                if importManager.step == .done || importManager.step == .failed || importManager.step == .cancelled {
                    Button("New Import") {
                        importManager.reset()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.bar)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !importManager.isRunning {
                        settingsSection
                    }

                    if importManager.isRunning
                        || importManager.step == .done
                        || importManager.step == .failed
                        || importManager.step == .cancelled {
                        progressSection
                    }

                    if !importManager.importLog.isEmpty {
                        logSection
                    }
                }
                .padding(16)
            }
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportItem,
            contentType: .commaSeparatedText,
            defaultFilename: "playlist-import-log"
        ) { _ in }
    }

    // MARK: - Settings Section

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Settings", systemImage: "gearshape")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("If playlist already exists:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $duplicateAction) {
                    ForEach(DuplicateAction.allCases, id: \.self) { action in
                        Text(action.rawValue).tag(action)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            Divider()

            let selectedPlaylists = selectedNames.compactMap { loadedPlaylists[$0] }
            let totalTracks = selectedPlaylists.reduce(0) { $0 + $1.trackCount }

            VStack(alignment: .leading, spacing: 6) {
                if selectedNames.isEmpty {
                    Text("Select playlists to import")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(selectedNames.count) playlist\(selectedNames.count == 1 ? "" : "s") · \(totalTracks) tracks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    onImport()
                } label: {
                    Label("Start Import", systemImage: "arrow.up.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedNames.isEmpty || selectedPlaylists.count != selectedNames.count)
                .help(selectedPlaylists.count != selectedNames.count ? "Open each selected playlist to load its tracks first" : "")
            }
        }
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Progress", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if importManager.isRunning {
                    Button("Cancel") { importManager.cancel() }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            // Step + icon
            HStack(spacing: 8) {
                if importManager.isRunning {
                    ProgressView().scaleEffect(0.7)
                } else {
                    stepIcon
                }
                Text(importManager.step.rawValue)
                    .font(.subheadline)
            }

            // Progress bar
            if importManager.isRunning {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progressValue)
                        .progressViewStyle(.linear)

                    if !importManager.currentPlaylistName.isEmpty {
                        HStack {
                            Text(importManager.currentPlaylistName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Text("\(importManager.currentPlaylistIndex + 1)/\(importManager.totalPlaylists)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    if importManager.step == .loadingPlex {
                        Text("Loading Plex library (\(Int(importManager.plexLoadProgress * 100))%)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Error con botón de retry
            if let error = importManager.errorMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)

                    Button {
                        onImport()
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var progressValue: Double {
        if importManager.step == .loadingPlex || importManager.step == .buildingIndex {
            return importManager.plexLoadProgress * 0.3
        }
        return 0.3 + importManager.overallProgress * 0.7
    }

    @ViewBuilder
    private var stepIcon: some View {
        switch importManager.step {
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "stop.circle.fill").foregroundStyle(.orange)
        default:
            EmptyView()
        }
    }

    // MARK: - Log Section

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Results", systemImage: "list.bullet.clipboard")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    exportItem = CSVDocument(content: importManager.exportCSV())
                    showExporter = true
                } label: {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            // Summary row
            let total   = importManager.importLog.reduce(0) { $0 + $1.tracksTotal }
            let matched = importManager.importLog.reduce(0) { $0 + $1.tracksMatched }
            let failed  = importManager.importLog.reduce(0) { $0 + $1.tracksUnmatched }

            HStack(spacing: 12) {
                StatBadge(value: importManager.importLog.count, label: "playlists",    color: .accentColor)
                StatBadge(value: matched,                       label: "matched",      color: .green)
                if failed > 0 {
                    StatBadge(value: failed, label: "unmatched", color: .orange)
                }
                StatBadge(value: total,   label: "total tracks", color: .secondary)
            }

            VStack(spacing: 1) {
                ForEach(importManager.importLog) { entry in
                    LogEntryRow(
                        entry: entry,
                        playlist: loadedPlaylists[entry.playlistName],
                        matchResults: importManager.matchResults[entry.playlistName]
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - StatBadge

struct StatBadge: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 1) {
            Text("\(value)")
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - LogEntryRow

struct LogEntryRow: View {
    @Environment(AppSettings.self) private var settings
    let entry: ImportLogEntry
    let playlist: MusicPlaylist?
    let matchResults: [String: MatchResult]?

    @State private var showingReview = false

    private var plexWebURL: URL? {
        guard let playlistID = entry.plexPlaylistID,
              !settings.plexServerURL.isEmpty,
              !settings.plexMachineIdentifier.isEmpty else { return nil }
        let base = settings.plexServerURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(base)/web/index.html#!/server/\(settings.plexMachineIdentifier)/playlist?key=/playlists/\(playlistID)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Row 1: name + action badge
            HStack {
                Text(entry.playlistName)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                actionBadge
            }

            // Row 2: stats + action buttons
            HStack(spacing: 0) {
                // Stats
                HStack(spacing: 10) {
                    Label("\(entry.tracksMatched)", systemImage: "checkmark")
                        .foregroundStyle(.green)
                    if entry.tracksUnmatched > 0 {
                        Label("\(entry.tracksUnmatched)", systemImage: "xmark")
                            .foregroundStyle(.orange)
                    }
                    if entry.tracksSkipped > 0 {
                        Label("\(entry.tracksSkipped)", systemImage: "minus")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)

                Spacer()

                // Action buttons
                HStack(spacing: 12) {
                    if playlist != nil && matchResults != nil {
                        Button {
                            showingReview = true
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "magnifyingglass")
                                Text("Review")
                            }
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }

                    if let url = plexWebURL {
                        Link(destination: url) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up.right.square")
                                Text("Open in Plex")
                            }
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(.quaternary)
        .sheet(isPresented: $showingReview) {
            if let playlist, let matchResults {
                MatchReviewSheet(playlist: playlist, matchResults: matchResults)
            }
        }
    }

    @ViewBuilder
    private var actionBadge: some View {
        let isGood = entry.action.hasPrefix("Created")
                  || entry.action.hasPrefix("Replaced")
                  || entry.action.hasPrefix("Renamed")
                  || entry.action.hasPrefix("Appended")
                  || entry.action.hasPrefix("Up to date")
        Text(entry.action)
            .font(.caption.bold())
            .foregroundStyle(isGood ? Color.green : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background((isGood ? Color.green : Color.secondary).opacity(0.12), in: Capsule())
            .lineLimit(1)
    }
}

// MARK: - MatchReviewSheet

enum MatchFilter: String, CaseIterable {
    case all      = "All"
    case matched  = "Matched"
    case unmatched = "Unmatched"
    case skipped  = "Skipped"
}

struct MatchReviewSheet: View {
    let playlist: MusicPlaylist
    let matchResults: [String: MatchResult]

    @Environment(\.dismiss) private var dismiss
    @State private var filter: MatchFilter = .all

    private var filteredTracks: [MusicTrack] {
        playlist.tracks.filter { track in
            let result = matchResults[track.persistentID]
            switch filter {
            case .all:      return true
            case .matched:  return result?.matchedTrack != nil
            case .unmatched:
                if case .unmatched = result { return true }
                if case .ambiguous = result { return true }
                return false
            case .skipped:
                if case .skipped = result { return true }
                return false
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.name)
                        .font(.headline)
                    Text("\(filteredTracks.count) of \(playlist.trackCount) tracks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $filter) {
                    ForEach(MatchFilter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)

                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .padding(.leading, 12)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.bar)

            Divider()

            List(filteredTracks) { track in
                TrackRowView(
                    track: track,
                    result: matchResults[track.persistentID]
                )
            }
            .listStyle(.plain)
        }
        .frame(minWidth: 600, minHeight: 500)
    }
}

// MARK: - CSVDocument

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var content: String

    init(content: String) { self.content = content }

    init(configuration: ReadConfiguration) throws {
        content = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(content.utf8))
    }
}
