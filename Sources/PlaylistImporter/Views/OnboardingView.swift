import SwiftUI

struct OnboardingView: View {
    let onGetStarted: () -> Void
    var ctaLabel: String = "Connect to Plex"

    var body: some View {
        HStack(spacing: 0) {
            // Left — branding
            VStack(spacing: 16) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(.purple)

                VStack(spacing: 6) {
                    Text("Music2PLX")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Transfer your Music playlists to Plex")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background.secondary)

            Divider()

            // Right — steps + CTA
            VStack(alignment: .leading, spacing: 0) {
                Text("Before you start")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(.bottom, 24)

                VStack(alignment: .leading, spacing: 20) {
                    OnboardingStep(
                        number: 1,
                        icon: "server.rack",
                        title: "Plex Media Server must be running",
                        description: "Make sure Plex is running on your local network and you can reach its web interface (usually http://192.168.x.x:32400/web)."
                    )
                    OnboardingStep(
                        number: 2,
                        icon: "music.note",
                        title: "Your music must be in Plex",
                        description: "The app matches tracks by title and artist. Your music files need to be already scanned into a Plex music library."
                    )
                    OnboardingStep(
                        number: 3,
                        icon: "list.bullet.rectangle",
                        title: "Playlists live in the Music app",
                        description: "The app reads playlists from Apple's Music app (formerly iTunes). Create or import your playlists there first."
                    )
                    OnboardingStep(
                        number: 4,
                        icon: "person.badge.key",
                        title: "Sign in with your Plex account",
                        description: "You'll be redirected to Plex's website to authorize the app. No password is stored — only a revocable access token."
                    )
                }

                Spacer()

                Button {
                    onGetStarted()
                } label: {
                    Text(ctaLabel)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 32)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Step row

private struct OnboardingStep: View {
    let number: Int
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(.purple.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.purple)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    OnboardingView { }
        .frame(width: 960, height: 620)
}
