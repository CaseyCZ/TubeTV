import AVKit
import SwiftUI

struct VideoDetailView: View {
    let video: VideoItem

    @AppStorage("preferredQuality") private var preferredQuality = "Auto"

    @State private var showPlayer = false
    @State private var resolvedURL: URL?
    @State private var isResolving = false
    @State private var errorMessage: String?

    private var canPlay: Bool {
        video.playbackURL != nil || video.youtubeVideoID != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer()

            Text(video.title)
                .font(.largeTitle.bold())

            Text(video.channel)
                .font(.title2)

            Text(video.subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)

            HStack(spacing: 20) {
                Button {
                    Task {
                        await preparePlayback()
                    }
                } label: {
                    if isResolving {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Hledám stream…")
                        }
                    } else {
                        Label("Přehrát", systemImage: "play.fill")
                    }
                }
                .disabled(!canPlay || isResolving)

                Button {
                } label: {
                    Label("Titulky: Čeština", systemImage: "captions.bubble.fill")
                }
            }

            if video.youtubeVideoID != nil {
                Label(
                    preferredQuality == "Auto"
                        ? "Kvalita: automaticky – nejlepší nativně přehratelný stream"
                        : "Preferovaná kvalita: \(preferredQuality)",
                    systemImage: "4k.tv"
                )
                .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.headline)
            }

            Spacer()
        }
        .padding(64)
        .fullScreenCover(isPresented: $showPlayer) {
            if let resolvedURL {
                NativePlayerView(url: resolvedURL)
            }
        }
    }

    @MainActor
    private func preparePlayback() async {
        errorMessage = nil

        if let url = video.playbackURL {
            resolvedURL = url
            showPlayer = true
            return
        }

        guard let videoID = video.youtubeVideoID else {
            errorMessage = "Toto video zatím nemá zdroj pro přehrávání."
            return
        }

        isResolving = true
        defer { isResolving = false }

        do {
            let url = try await StreamResolver.resolveYouTubeVideo(
                videoID: videoID,
                preferredQuality: preferredQuality
            )
            resolvedURL = url
            showPlayer = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct NativePlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer

    init(url: URL) {
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        VideoPlayer(player: player)
            .ignoresSafeArea()
            .onAppear {
                player.play()
            }
            .onDisappear {
                player.pause()
            }
            .onExitCommand {
                dismiss()
            }
    }
}
