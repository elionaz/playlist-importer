# PlaylistImporter

A macOS app that imports playlists from Apple Music (iTunes) into Plex, using a two-level track matching strategy: exact file path matching first, then fuzzy metadata matching.

![macOS](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift](https://img.shields.io/badge/Swift-6.0-orange)

## Features

- Reads playlists directly from Music.app via AppleScript
- Authenticates with Plex via OAuth (no manual token copying)
- Two-level track matching:
  - **L1** — exact file path match (fast, 100% confidence)
  - **L2** — fuzzy metadata match using weighted similarity (title, artist, album, duration, year)
- Handles duplicates: skip, replace, append, or auto-rename
- Path prefix mapping for libraries mounted at different paths
- Live progress tracking with per-playlist and per-track status
- CSV export of the full import log
- 70 unit tests covering core matching logic

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 16+
- Music.app with at least one playlist
- A running Plex Media Server with a Music library

## Installation

### 1. Clone the repository

```bash
git clone git@github.com:elionaz/playlist-importer.git
cd playlist-importer
```

### 2. Open in Xcode

```bash
open PlaylistImporter.xcodeproj
```

Or open it directly from Finder.

### 3. Configure signing

In Xcode, select the **PlaylistImporter** target → **Signing & Capabilities** → set your Team and Bundle Identifier.

### 4. Run

Press **⌘R**. The first time you load a playlist, macOS will ask for permission to control Music.app — click **Allow**.

---

## First-time setup

1. Click the **gear icon** (top right) to open Plex settings.
2. Enter your Plex server URL (e.g. `http://192.168.1.10:32400`).
3. Click **Sign in with Plex** — your browser will open for authentication.
4. Select your Music library from the dropdown.
5. **(Optional)** If your local music folder path differs from the path Plex sees on the server, configure the path prefix mapping. This improves matching accuracy significantly.

## Usage

1. Select one or more playlists from the sidebar.
2. Click a playlist to preview its tracks and match status.
3. Choose what to do if the playlist already exists in Plex (Skip / Replace / Append / Rename).
4. Click **Start Import**.
5. When done, use **Export CSV** to save the full import log.

## Track matching

| Icon | Meaning |
|------|---------|
| ✓ | Matched with high confidence |
| ? | Ambiguous — multiple candidates found |
| ✗ | No match found in Plex library |
| — | Streaming-only track (no local file) |

## Running tests

```bash
swift test
```

## Project structure

```
Sources/PlaylistImporter/
├── Helpers/          # StringSimilarity, DurationCompare, KeychainHelper
├── Managers/         # AppSettings, ImportManager
├── Models/           # MusicTrack, PlexTrack, MatchResult, …
├── Services/         # MusicLibraryService, PlexAPIService, PlexAuthService, TrackMatchingService
└── Views/            # SwiftUI views

Tests/PlaylistImporterTests/
├── StringSimilarityTests.swift
├── DurationCompareTests.swift
└── TrackMatchingTests.swift
```
