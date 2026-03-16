import SwiftUI

struct ContentView: View {
    @Environment(AppSettings.self) private var settings
    @State private var showSetup = false

    var body: some View {
        Group {
            if settings.isAuthenticated {
                MainView()
            } else {
                welcomeView
            }
        }
        .sheet(isPresented: $showSetup) {
            PlexServerSetupView(isSheet: true) { showSetup = false }
                .environment(settings)
                .frame(width: 500)
        }
        .onAppear {
            if !settings.isAuthenticated { showSetup = true }
        }
    }

    // MARK: - Welcome

    private var welcomeView: some View {
        VStack(spacing: 24) {
            Image(systemName: "music.note.list")
                .font(.system(size: 64))
                .foregroundStyle(.purple)

            VStack(spacing: 8) {
                Text("Playlist Importer")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Transfer your iTunes playlists to Plex")
                    .foregroundStyle(.secondary)
            }

            Button {
                showSetup = true
            } label: {
                Label("Connect to Plex", systemImage: "person.badge.key")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
        .environment(AppSettings())
        .environment(MusicLibraryService())
        .environment({ let s = AppSettings(); return PlexAPIService(settings: s) }())
        .environment({ let s = AppSettings(); let a = PlexAPIService(settings: s); return ImportManager(settings: s, plexAPI: a) }())
        .frame(width: 960, height: 620)
}
