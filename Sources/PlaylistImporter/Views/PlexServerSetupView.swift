import SwiftUI

struct PlexServerSetupView: View {
    @Environment(AppSettings.self)    private var settings
    @Environment(PlexAPIService.self) private var plexAPI
    @State private var authService = PlexAuthService()
    @State private var serverURLInput = ""
    @State private var localPrefixInput = ""
    @State private var plexPrefixInput = ""

    // Library section picker
    @State private var musicSections: [PlexLibrarySection] = []
    @State private var isFetchingSections = false
    @State private var sectionFetchError: String?

    // Path debug
    @State private var samplePlexPath: String?
    @State private var isFetchingPath = false
    @State private var pathFetchError: String?

    /// When `true`, used as a sheet (shows a title + dismiss button).
    /// When `false`, used as the Settings pane (no dismiss needed).
    let isSheet: Bool
    var onDismiss: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isSheet {
                sheetHeader
            }

            Form {
                serverSection
                authSection
                librarySectionSection
                pathMappingSection
                pathDebugSection
            }
            .formStyle(.grouped)

            if isSheet {
                sheetFooter
            }
        }
        .onAppear {
            populateFromSettings()
            if settings.isAuthenticated && musicSections.isEmpty {
                Task { await fetchSections() }
            }
        }
    }

    // MARK: - Sections

    private var serverSection: some View {
        Section {
            TextField("http://192.168.1.100:32400", text: $serverURLInput)
                .textFieldStyle(.plain)
                .onSubmit { saveServerURL() }
                .onChange(of: serverURLInput) { saveServerURL() }
        } header: {
            Text("Plex Server URL")
        } footer: {
            Text("The local address of your Plex Media Server. Include port 32400.")
                .foregroundStyle(.secondary)
        }
    }

    private var authSection: some View {
        Section {
            if settings.isAuthenticated {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Authenticated with Plex")
                    Spacer()
                    Button("Sign Out", role: .destructive) {
                        settings.clearAuth()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
            } else if authService.isAuthenticating {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Waiting for browser authorization…")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") {
                        authService.cancelAuth()
                    }
                    .buttonStyle(.plain)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        saveServerURL()
                        authService.startAuthFlow { token in
                            settings.plexToken = token
                        }
                    } label: {
                        Label("Sign in with Plex", systemImage: "person.badge.key")
                    }
                    .disabled(serverURLInput.isEmpty)

                    if let error = authService.authError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
        } header: {
            Text("Plex Account")
        }
    }

    private var pathMappingSection: some View {
        Section {
            LabeledContent("iTunes / Mac prefix") {
                TextField("/Volumes/music", text: $localPrefixInput)
                    .textFieldStyle(.plain)
                    .onSubmit { savePathMapping() }
                    .onChange(of: localPrefixInput) { savePathMapping() }
            }
            LabeledContent("Plex server prefix") {
                TextField("/data/music", text: $plexPrefixInput)
                    .textFieldStyle(.plain)
                    .onSubmit { savePathMapping() }
                    .onChange(of: plexPrefixInput) { savePathMapping() }
            }
        } header: {
            Text("Path Mapping")
        } footer: {
            Text("If your music files are mounted differently on the Plex server, map the path prefix here. Leave Plex prefix empty if the paths are identical.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Sheet chrome

    private var sheetHeader: some View {
        HStack {
            Text("Connect to Plex")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
        }
        .padding([.horizontal, .top], 20)
        .padding(.bottom, 8)
    }

    private var sheetFooter: some View {
        HStack {
            Spacer()
            Button("Done") {
                saveAll()
                onDismiss?()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!settings.isAuthenticated)
        }
        .padding(20)
    }

    // MARK: - Library Section Section

    private var librarySectionSection: some View {
        Section {
            if isFetchingSections {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("Detecting libraries…")
                        .foregroundStyle(.secondary)
                }
            } else if musicSections.isEmpty {
                Button("Detect Music Libraries") {
                    Task { await fetchSections() }
                }
                .disabled(!settings.isAuthenticated)
            } else {
                Picker("Music library", selection: Binding(
                    get: { settings.plexLibrarySectionID },
                    set: { settings.plexLibrarySectionID = $0 }
                )) {
                    ForEach(musicSections) { section in
                        Text(section.title).tag(section.key)
                    }
                }
                .pickerStyle(.menu)

                Button("Refresh") { Task { await fetchSections() } }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = sectionFetchError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        } header: {
            Text("Music Library")
        } footer: {
            if settings.plexLibrarySectionID.isEmpty {
                Text("Detect your Plex music libraries to select which one to use for matching and playlist creation.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Tracks will be matched against this library. Playlists will be created here.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Path Debug Section

    private var pathDebugSection: some View {
        Section {
            Button(isFetchingPath ? "Loading…" : "Show sample Plex file path") {
                Task { await fetchSamplePath() }
            }
            .disabled(!settings.isAuthenticated || settings.plexLibrarySectionID.isEmpty || isFetchingPath)

            if let path = samplePlexPath {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Plex sees this path:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let error = pathFetchError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        } header: {
            Text("Path Mapping Debug")
        } footer: {
            Text("Fetches the file path of a random track from Plex. Compare it against the iTunes path in Finder to set the correct prefixes above.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Async helpers

    private func fetchSections() async {
        isFetchingSections = true
        sectionFetchError = nil
        do {
            let all = try await plexAPI.fetchLibrarySections()
            musicSections = all.filter { $0.isMusic }
            // Auto-select if nothing selected yet
            if settings.plexLibrarySectionID.isEmpty, let first = musicSections.first {
                settings.plexLibrarySectionID = first.key
            }
        } catch {
            sectionFetchError = error.localizedDescription
        }
        isFetchingSections = false
    }

    private func fetchSamplePath() async {
        isFetchingPath = true
        pathFetchError = nil
        samplePlexPath = nil
        do {
            samplePlexPath = try await plexAPI.fetchSampleTrackPath()
            if samplePlexPath == nil {
                pathFetchError = "No tracks found in this library section."
            }
        } catch {
            pathFetchError = error.localizedDescription
        }
        isFetchingPath = false
    }

    // MARK: - Helpers

    private func populateFromSettings() {
        serverURLInput   = settings.plexServerURL
        localPrefixInput = settings.localPathPrefix
        plexPrefixInput  = settings.plexPathPrefix
    }

    private func saveServerURL() {
        settings.plexServerURL = serverURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func savePathMapping() {
        settings.localPathPrefix = localPrefixInput.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.plexPathPrefix  = plexPrefixInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveAll() {
        saveServerURL()
        savePathMapping()
    }
}

#Preview {
    PlexServerSetupView(isSheet: true)
        .environment(AppSettings())
        .frame(width: 500)
}
