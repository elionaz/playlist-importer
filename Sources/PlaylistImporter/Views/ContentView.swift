import SwiftUI

struct ContentView: View {
    @Environment(AppSettings.self) private var settings
    @State private var showSetup = false

    var body: some View {
        Group {
            if settings.isAuthenticated {
                MainView()
            } else {
                OnboardingView { showSetup = true }
            }
        }
        .sheet(isPresented: $showSetup) {
            PlexServerSetupView(isSheet: true) { showSetup = false }
                .environment(settings)
                .frame(width: 500)
        }
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
