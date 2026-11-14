# Contributing to Music2PLX

Thanks for your interest in improving Music2PLX! This document explains how to propose changes.

## Ground rules

- **`main` is protected.** Nobody pushes to it directly. Every change lands through a Pull Request.
- **Every PR needs approval from the maintainer ([@elionaz](https://github.com/elionaz))** before it can be merged (enforced via `CODEOWNERS` + branch protection).
- All review conversations must be resolved before merging, and new pushes after an approval require a fresh approval.
- History on `main` is linear: PRs are squash-merged.
- Be respectful — see the [Code of Conduct](CODE_OF_CONDUCT.md).

## Workflow

1. **Open an issue first** for anything non-trivial (new feature, behavior change, refactor) so we can agree on the approach before you invest time.
2. **Fork** the repo and create a branch from `main`:
   - `feat/<short-description>` — new features
   - `fix/<short-description>` — bug fixes
   - `docs/<short-description>` — documentation only
   - `chore/<short-description>` — tooling, cleanup
3. Make your changes in small, focused commits.
4. Make sure the project **builds** and the **tests pass** (see below).
5. Open a Pull Request against `main` and fill in the PR template.
6. Address review feedback. Once approved, the maintainer merges (squash merge by default).

## Development setup

Requirements: macOS 14+, Xcode 16+ (Swift 6).

```bash
git clone https://github.com/elionaz/playlist-importer.git
cd playlist-importer
open PlaylistImporter.xcodeproj
```

In Xcode, select the **PlaylistImporter** scheme and press **⌘R**. For local signing, set your own team under *Signing & Capabilities* (do **not** commit that change).

Run the tests:

```bash
swift test
```

or **⌘U** in Xcode.

## Coding guidelines

- Swift 6 with strict concurrency. Keep UI code on `@MainActor`; heavy work (matching, parsing) off the main actor.
- Follow the existing folder layout: `Helpers/`, `Managers/`, `Models/`, `Services/`, `Views/`.
- Prefer small, testable pure functions for matching/normalization logic and add tests in `Tests/PlaylistImporterTests/`.
- No new third-party dependencies without discussing it in an issue first.
- Never commit secrets, Plex tokens, personal paths, signing team changes, or build output (`build/`, `DerivedData/`).

## Commit messages

Use short, imperative messages, optionally with a [Conventional Commits](https://www.conventionalcommits.org/) prefix:

```
fix: avoid crash when a playlist has 4000+ tracks
feat: add path mapping preview
```

## Reporting bugs

Open an issue with the **Bug report** template and include: macOS version, app version, steps to reproduce, and what you expected vs. what happened. **Remove your Plex token and server URL** from any logs you paste.

## Security

Please do not report security issues in public issues — see [SECURITY.md](SECURITY.md).

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
