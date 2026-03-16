import SwiftUI

struct TrackListView: View {
    let playlist: MusicPlaylist
    let matchResults: [String: MatchResult]?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.name)
                        .font(.headline)
                    Text("\(playlist.trackCount) tracks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let results = matchResults {
                    matchSummaryBadges(results)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.bar)

            Divider()

            // Track list
            List(playlist.tracks) { track in
                TrackRowView(
                    track: track,
                    result: matchResults?[track.persistentID]
                )
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private func matchSummaryBadges(_ results: [String: MatchResult]) -> some View {
        let matched   = results.values.filter { $0.matchedTrack != nil }.count
        let unmatched = results.values.filter { if case .unmatched = $0 { return true }; return false }.count
        let skipped   = results.values.filter { if case .skipped   = $0 { return true }; return false }.count

        HStack(spacing: 6) {
            SummaryBadge(count: matched,   color: .green,  icon: "checkmark.circle.fill")
            if unmatched > 0 {
                SummaryBadge(count: unmatched, color: .orange, icon: "exclamationmark.circle.fill")
            }
            if skipped > 0 {
                SummaryBadge(count: skipped,   color: .secondary, icon: "icloud.slash")
            }
        }
    }
}

// MARK: - TrackRowView

struct TrackRowView: View {
    let track: MusicTrack
    let result: MatchResult?

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(track.artist)
                        .foregroundStyle(.secondary)
                    if !track.album.isEmpty {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(track.album)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .lineLimit(1)
            }

            Spacer()

            if track.filePath == nil {
                Image(systemName: "icloud")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Streaming — no local file")
            }

            Text(formatDuration(track.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch result {
        case .matched(_, let confidence, let method):
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(confidence >= 0.85 ? .green : .yellow)
                .help(method.rawValue + " (\(Int(confidence * 100))%)")
        case .ambiguous:
            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(.orange)
                .help("Ambiguous match — review required")
        case .unmatched:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .help("No match found in Plex")
        case .skipped:
            Image(systemName: "minus.circle")
                .foregroundStyle(.secondary)
                .help("Streaming track — not in Plex library")
        case nil:
            Color.clear
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - SummaryBadge

struct SummaryBadge: View {
    let count: Int
    let color: Color
    let icon: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text("\(count)")
        }
        .font(.caption.bold())
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
    }
}
