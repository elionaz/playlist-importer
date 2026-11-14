# Music2PLX

Import your iTunes and Apple Music playlists into Plex Media Server — automatically matched and ready in Plexamp.

![macOS](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift](https://img.shields.io/badge/Swift-6.0-orange)

---

## What it does

Music2PLX reads your playlists from Apple Music and finds each track in your Plex library using a two-level matching strategy: exact file path first, then smart fuzzy matching by title, artist, album, and duration. Matched tracks are assembled into a new playlist in Plex — no manual work, no CSV files.

## Features

- Reads playlists directly from Apple Music (no export needed)
- Plex OAuth sign-in — no manual token copying
- Two-level track matching:
  - **L1** — exact file path match (fast, 100% confidence)
  - **L2** — fuzzy metadata match (title, artist, album, duration, year)
- Preview match results before importing
- Handles duplicates: skip, replace, append, or auto-rename
- Path prefix mapping for libraries at a different path on the server
- Works alongside active VPN connections (Cloudflare Warp, etc.)
- Sound notifications when loading and importing finish (optional)
- CSV export of the full import log

## Requirements

- macOS 14 (Sonoma) or later
- Apple Music / iTunes library on the same Mac
- Plex Media Server with a Music library on your local network

---

## Installation

### Option A — Download the app (easiest)

1. Go to the [**Releases**](https://github.com/elionaz/playlist-importer/releases/latest) page and download `Music2PLX-<version>-macOS.zip`.
2. Double-click the zip to extract **Music2PLX.app** and move it to your **Applications** folder.
3. **First launch:** the release build is *ad-hoc signed* (not notarized by Apple), so macOS Gatekeeper will block it the first time. Use one of these:
   - **Right-click** (or Control-click) **Music2PLX.app → Open**, then click **Open** in the dialog. On macOS 15+, if there is no *Open* button, go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway**.
   - Or remove the quarantine flag from Terminal:
     ```bash
     xattr -dr com.apple.quarantine /Applications/Music2PLX.app
     ```
4. Grant the permissions the app asks for: **Media & Apple Music** and **Local Network**.

The build is Universal (Apple Silicon + Intel). You can check the download against the `SHA256SUMS.txt` attached to each release:

```bash
shasum -a 256 Music2PLX-*-macOS.zip
```

### Option B — Build from source

Requirements: macOS 14+, **Xcode 16+** (Swift 6).

```bash
git clone https://github.com/elionaz/playlist-importer.git
cd playlist-importer
open PlaylistImporter.xcodeproj
```

In Xcode select the **PlaylistImporter** scheme and press **⌘R**. If Xcode complains about signing, open the target's **Signing & Capabilities** tab and choose your own team (or *Sign to Run Locally*).

Command-line build (ad-hoc signed, no Apple account needed):

```bash
xcodebuild -project PlaylistImporter.xcodeproj -scheme PlaylistImporter \
  -configuration Release -derivedDataPath build \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
  build
open build/Build/Products/Release/Music2PLX.app
```

Run the tests:

```bash
swift test
```

---

## Setup

### 1. Connect to Plex

1. Open Music2PLX and click the **gear icon** (top right).
2. Enter your Plex server URL — e.g. `http://192.168.1.10:32400`.
3. Click **Sign in with Plex**. Your browser will open for authentication.
4. Back in the app, click **Detect Music Libraries** and select your music library.

### 2. Path mapping (optional but recommended)

If your music files are stored at a different path on the Plex server than on your Mac, configure the path prefix mapping in Settings:

- **iTunes / Mac prefix** — the path as your Mac sees it, e.g. `/Volumes/Music`
- **Plex server prefix** — the path as the Plex server sees it, e.g. `/data/music`

Use **Show sample Plex file path** to see exactly how Plex stores the path, then compare it to the file location in Finder.

---

## Usage

1. **Select a playlist** from the sidebar on the left.
2. **Review the tracks** — each one shows its match status before you import.
3. **Choose duplicate handling** — what to do if the playlist already exists in Plex.
4. Click **Start Import**.
5. When finished, use **Export CSV** to save the full import log.

### Match status icons

| Icon | Meaning |
|------|---------|
| ✓ | Matched with high confidence |
| ~ | Fuzzy match — close but not exact |
| ? | Ambiguous — multiple candidates found |
| ✗ | No match found in Plex library |
| — | Streaming-only track (no local file) |

---

## Troubleshooting

### Playlists don't load / Apple Music error

- Make sure **Music.app is open** before loading playlists.
- Check **System Settings → Privacy & Security → Media & Apple Music** — Music2PLX should be listed and enabled.

### Can't connect to Plex / "Detecting libraries" hangs

- Confirm your Plex server URL includes the port: `http://192.168.1.10:32400`.
- Check **System Settings → Privacy & Security → Local Network** — Music2PLX must be toggled on.
- If you are using a VPN (Cloudflare Warp, etc.), Music2PLX routes around it automatically using your physical network interface. No action needed.

### Tracks not matching

- Configure path prefix mapping in Settings (see Setup step 2 above).
- Use **Show sample Plex file path** to see the exact path format Plex uses.
- Tracks available only via Apple Music streaming (no local file) cannot be matched.

---

## Project structure

```
Sources/PlaylistImporter/
├── Helpers/          # StringSimilarity, DurationCompare, LocalNetworkPermission
├── Managers/         # AppSettings, ImportManager
├── Models/           # MusicTrack, PlexTrack, MatchResult, …
├── Services/         # MusicLibraryService, PlexAPIService, PlexAuthService, PlexHTTPClient, TrackMatchingService
└── Views/            # SwiftUI views
```

---

## Contributing

Contributions are welcome! Read [CONTRIBUTING.md](CONTRIBUTING.md) first. All PRs into `main` need the maintainer's review and approval.

## License

[MIT](LICENSE) © elionaz
