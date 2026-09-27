import AVFoundation
import AVKit
import SwiftUI

struct VideoDetailView: View {
    let video: VideoItem

    @AppStorage("preferredQuality") private var preferredQuality = "Auto"

    @State private var showPlayer = false
    @State private var playbackSource: PlaybackSource?
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
            if let playbackSource {
                NativePlayerView(source: playbackSource)
            }
        }
    }

    @MainActor
    private func preparePlayback() async {
        errorMessage = nil

        if let url = video.playbackURL {
            playbackSource = .direct(url)
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
            playbackSource = try await StreamResolver.resolveYouTubeVideo(
                videoID: videoID,
                preferredQuality: preferredQuality
            )
            showPlayer = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
final class NativePlayerModel: ObservableObject {
    @Published private(set) var player = AVPlayer()
    @Published private(set) var errorMessage: String?
    @Published private(set) var isPreparing = true

    private let source: PlaybackSource
    private var didPrepare = false

    init(source: PlaybackSource) {
        self.source = source
    }

    func prepareAndPlay() async {
        guard !didPrepare else {
            player.play()
            return
        }

        didPrepare = true
        isPreparing = true
        errorMessage = nil

        do {
            let item = try await makePlayerItem(from: source)
            player.replaceCurrentItem(with: item)
            isPreparing = false
            player.play()
        } catch {
            if case let .adaptive(_, _, fallback?) = source {
                player.replaceCurrentItem(with: AVPlayerItem(url: fallback))
                isPreparing = false
                errorMessage = "Vyšší kvalita nešla spojit, přehrávám kompatibilní variantu."
                player.play()
            } else {
                isPreparing = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func pause() {
        player.pause()
    }

    private func makePlayerItem(from source: PlaybackSource) async throws -> AVPlayerItem {
        switch source {
        case .direct(let url):
            return AVPlayerItem(url: url)

        case .adaptive(let videoURL, let audioURL, _):
            let videoAsset = AVURLAsset(url: videoURL)
            let audioAsset = AVURLAsset(url: audioURL)

            async let loadedVideoTracks = videoAsset.loadTracks(withMediaType: .video)
            async let loadedAudioTracks = audioAsset.loadTracks(withMediaType: .audio)
            async let loadedVideoDuration = videoAsset.load(.duration)
            async let loadedAudioDuration = audioAsset.load(.duration)

            let videoTracks = try await loadedVideoTracks
            let audioTracks = try await loadedAudioTracks
            let videoDuration = try await loadedVideoDuration
            let audioDuration = try await loadedAudioDuration

            guard let sourceVideoTrack = videoTracks.first,
                  let sourceAudioTrack = audioTracks.first else {
                throw StreamResolverError.noPlayableStream
            }

            let duration = CMTimeCompare(videoDuration, audioDuration) <= 0
                ? videoDuration
                : audioDuration

            let composition = AVMutableComposition()

            guard let videoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ),
            let audioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw StreamResolverError.noPlayableStream
            }

            let range = CMTimeRange(start: .zero, duration: duration)
            try videoTrack.insertTimeRange(range, of: sourceVideoTrack, at: .zero)
            try audioTrack.insertTimeRange(range, of: sourceAudioTrack, at: .zero)

            return AVPlayerItem(asset: composition)
        }
    }
}

struct NativePlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: NativePlayerModel

    init(source: PlaybackSource) {
        _model = StateObject(wrappedValue: NativePlayerModel(source: source))
    }

    var body: some View {
        ZStack {
            VideoPlayer(player: model.player)
                .ignoresSafeArea()

            if model.isPreparing {
                ProgressView("Připravuji video…")
                    .font(.title3)
            }

            if let errorMessage = model.errorMessage {
                VStack {
                    Spacer()

                    Text(errorMessage)
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(.black.opacity(0.75))
                        .clipShape(Capsule())
                        .padding(.bottom, 54)
                }
            }
        }
        .task {
            await model.prepareAndPlay()
        }
        .onDisappear {
            model.pause()
        }
        .onExitCommand {
            dismiss()
        }
    }
}
