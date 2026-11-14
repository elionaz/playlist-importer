import SwiftUI

@main
struct PlaylistImporterApp: App {
    @State private var settings: AppSettings
    @State private var musicLibrary: MusicLibraryService
    @State private var plexAPI: PlexAPIService
    @State private var importManager: ImportManager
    @State private var entitlement: EntitlementManager

    init() {
        let s   = AppSettings()
        let m   = MusicLibraryService()
        let api = PlexAPIService(settings: s)
        let ent = EntitlementManager()
        let imp = ImportManager(settings: s, plexAPI: api, entitlement: ent)
        _settings      = State(initialValue: s)
        _musicLibrary  = State(initialValue: m)
        _plexAPI       = State(initialValue: api)
        _importManager = State(initialValue: imp)
        _entitlement   = State(initialValue: ent)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(musicLibrary)
                .environment(plexAPI)
                .environment(importManager)
                .environment(entitlement)
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
