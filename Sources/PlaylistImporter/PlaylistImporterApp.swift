import SwiftUI

@main
struct PlaylistImporterApp: App {
    @State private var settings: AppSettings
    @State private var musicLibrary: MusicLibraryService
    @State private var plexAPI: PlexAPIService
    @State private var importManager: ImportManager

    init() {
        let s   = AppSettings()
        let m   = MusicLibraryService()
        let api = PlexAPIService(settings: s)
        let imp = ImportManager(settings: s, plexAPI: api)
        _settings      = State(initialValue: s)
        _musicLibrary  = State(initialValue: m)
        _plexAPI       = State(initialValue: api)
        _importManager = State(initialValue: imp)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(musicLibrary)
                .environment(plexAPI)
                .environment(importManager)
                .frame(minWidth: 960, minHeight: 620)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Playlist Importer") { }
            }
        }

        Settings {
            PlexServerSetupView(isSheet: false)
                .environment(settings)
                .environment(plexAPI)
                .frame(width: 500)
        }
    }
}
