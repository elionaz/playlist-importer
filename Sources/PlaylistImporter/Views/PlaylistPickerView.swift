import SwiftUI

struct PlaylistPickerView: View {
    @Environment(MusicLibraryService.self) private var musicLibrary

    @Binding var selectedNames: Set<String>
    @Binding var inspectedName: String?

    let playlistNames: [String]
    let loadedPlaylists: [String: MusicPlaylist]

    var body: some View {
        List(playlistNames, id: \.self, selection: $inspectedName) { name in
            HStack(spacing: 10) {
                // Checkbox
                Image(systemName: selectedNames.contains(name) ? "checkmark.square.fill" : "square")
                    .foregroundStyle(selectedNames.contains(name) ? Color.accentColor : .secondary)
                    .onTapGesture { toggle(name) }

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .lineLimit(1)
                    if let playlist = loadedPlaylists[name] {
                        Text("\(playlist.trackCount) tracks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { inspectedName = name }
            }
            .padding(.vertical, 2)
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { sidebarFooter }
    }

    private var sidebarFooter: some View {
        HStack {
            if !playlistNames.isEmpty {
                Button(selectedNames.count == playlistNames.count ? "Deselect All" : "Select All") {
                    if selectedNames.count == playlistNames.count {
                        selectedNames.removeAll()
                    } else {
                        selectedNames = Set(playlistNames)
                    }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if !selectedNames.isEmpty {
                Text("\(selectedNames.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func toggle(_ name: String) {
        if selectedNames.contains(name) {
            selectedNames.remove(name)
        } else {
            selectedNames.insert(name)
        }
    }
}
