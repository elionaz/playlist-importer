import SwiftUI
import AppKit

struct MainView: View {
    @Environment(AppSettings.self)         private var settings
    @Environment(MusicLibraryService.self) private var musicLibrary
    @Environment(ImportManager.self)       private var importManager
    @Environment(PlexAPIService.self)      private var plexAPI

    @State private var playlistNames: [String] = []
    @State private var loadedPlaylists: [String: MusicPlaylist] = [:]
    @State private var selectedNames: Set<String> = []
    @State private var inspectedName: String? = nil
    @State private var duplicateAction: DuplicateAction = .skip
    @State private var showSetup = false
    @State private var showOnboarding = false
    @State private var loadError: String? = nil

    // Progreso de carga por playlist: name → (loaded, total)
    @State private var trackLoadProgress: [String: (Int, Int)] = [:]
    // Error de carga por playlist
    @State private var trackLoadErrors: [String: String] = [:]

    // MARK: - Body

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            contentPanel
        } detail: {
            ImportProgressView(
                selectedNames: $selectedNames,
                duplicateAction: $duplicateAction,
                loadedPlaylists: loadedPlaylists,
                onImport: startImport
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        }
        .toolbar { toolbarItems }
        .onChange(of: importManager.step) { _, newStep in
            if newStep == .done { playSound("Glass") }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(onGetStarted: { showOnboarding = false }, ctaLabel: "Close")
                .frame(width: 960, height: 620)
        }
        .sheet(isPresented: $showSetup) {
            PlexServerSetupView(isSheet: true) { showSetup = false }
                .environment(settings)
                .environment(plexAPI)
                .frame(width: 500)
        }
        .task { await loadPlaylistNames() }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        Group {
            if musicLibrary.isLoading && playlistNames.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading playlists…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") { Task { await loadPlaylistNames() } }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PlaylistPickerView(
                    selectedNames: $selectedNames,
                    inspectedName: $inspectedName,
                    playlistNames: playlistNames,
                    loadedPlaylists: loadedPlaylists
                )
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        .navigationTitle("Playlists")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await loadPlaylistNames() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload playlists from Music")
                .disabled(musicLibrary.isLoading)
            }
        }
    }

    // MARK: - Content Panel

    @ViewBuilder
    private var contentPanel: some View {
        if let name = inspectedName {
            if let playlist = loadedPlaylists[name] {
                TrackListView(
                    playlist: playlist,
                    matchResults: importManager.matchResults[name]
                )
                .navigationTitle(name)
            } else if let error = trackLoadErrors[name] {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                    Button("Retry") {
                        trackLoadErrors.removeValue(forKey: name)
                        Task { await loadTracks(for: name) }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Cargando — muestra barra de progreso si ya sabemos el total
                trackLoadingView(for: name)
                    .task(id: name) { await loadTracks(for: name) }
            }
        } else {
            ContentUnavailableView(
                "Select a Playlist",
                systemImage: "music.note.list",
                description: Text("Choose a playlist from the sidebar to see its tracks.")
            )
        }
    }

    @ViewBuilder
    private func trackLoadingView(for name: String) -> some View {
        VStack(spacing: 16) {
            if let (loaded, total) = trackLoadProgress[name], total > 0 {
                VStack(spacing: 8) {
                    ProgressView(value: Double(loaded), total: Double(total))
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 300)

                    Text("\(loaded) / \(total) tracks")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Text("Loading \(name)…")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    if total > 1_000 {
                        Text("Large playlists may take a while. Please wait…")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 4)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading tracks…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 4) {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text(settings.plexServerURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button { showSetup = true } label: {
                Image(systemName: "gear")
            }
            .help("Plex Settings")
        }
        ToolbarItem(placement: .primaryAction) {
            Button { showOnboarding = true } label: {
                Image(systemName: "questionmark.circle")
            }
            .help("Getting Started")
        }
    }

    // MARK: - Data Loading

    private func loadPlaylistNames() async {
        loadError = nil
        do {
            playlistNames = try await musicLibrary.fetchPlaylistNames()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func loadTracks(for name: String) async {
        guard loadedPlaylists[name] == nil else { return }
        trackLoadProgress[name] = nil
        trackLoadErrors.removeValue(forKey: name)
        do {
            let playlist = try await musicLibrary.fetchPlaylist(named: name) { loaded, total in
                self.trackLoadProgress[name] = (loaded, total)
            }
            loadedPlaylists[name] = playlist
            trackLoadProgress.removeValue(forKey: name)
            playSound("Tink")
        } catch is CancellationError {
            // Tarea cancelada (usuario seleccionó otra playlist) — no hacer nada
            trackLoadProgress.removeValue(forKey: name)
        } catch {
            trackLoadProgress.removeValue(forKey: name)
            trackLoadErrors[name] = error.localizedDescription
        }
    }

    // MARK: - Sound

    private func playSound(_ name: String) {
        guard settings.soundEnabled else { return }
        NSSound(named: name)?.play()
    }

    // MARK: - Import

    private func startImport() {
        let playlists = selectedNames.compactMap { loadedPlaylists[$0] }
        importManager.startImport(playlists: playlists, duplicateAction: duplicateAction)
    }
}
