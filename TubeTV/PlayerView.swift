import AVFoundation
import AVKit
import SwiftUI

struct VideoDetailView: View {
    let video: VideoItem

    @AppStorage("preferredQuality") private var preferredQuality = "Auto"
    @AppStorage("preferredCaptionLanguage") private var preferredCaptionLanguage = "cs"
    @AppStorage("autoEnableCaptions") private var autoEnableCaptions = true
    @AppStorage("autoTranslateCaptions") private var autoTranslateCaptions = true

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

                Label(
                    autoEnableCaptions ? "Titulky: Čeština" : "Titulky: vypnuto",
                    systemImage: "captions.bubble.fill"
                )
                .foregroundStyle(.secondary)
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
                NativePlayerView(
                    source: playbackSource,
                    youtubeVideoID: video.youtubeVideoID,
                    captionsEnabled: autoEnableCaptions,
                    captionLanguage: preferredCaptionLanguage,
                    allowCaptionTranslation: autoTranslateCaptions
                )
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
    @Published private(set) var currentCaption = ""
    @Published private(set) var captionStatus: String?

    private let source: PlaybackSource
    private let youtubeVideoID: String?
    private let captionsEnabled: Bool
    private let captionLanguage: String
    private let allowCaptionTranslation: Bool

    private var didPrepare = false
    private var cues: [CaptionCue] = []
    private var timeObserver: Any?

    init(
        source: PlaybackSource,
        youtubeVideoID: String?,
        captionsEnabled: Bool,
        captionLanguage: String,
        allowCaptionTranslation: Bool
    ) {
        self.source = source
        self.youtubeVideoID = youtubeVideoID
        self.captionsEnabled = captionsEnabled
        self.captionLanguage = captionLanguage
        self.allowCaptionTranslation = allowCaptionTranslation
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
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
            startCaptionLoadingIfNeeded()
        } catch {
            if case let .adaptive(_, _, fallback?) = source {
                player.replaceCurrentItem(with: AVPlayerItem(url: fallback))
                isPreparing = false
                errorMessage = "Vyšší kvalita nešla spojit, přehrávám kompatibilní variantu."
                player.play()
                startCaptionLoadingIfNeeded()
            } else {
                isPreparing = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func pause() {
        player.pause()
    }

    private func startCaptionLoadingIfNeeded() {
        guard captionsEnabled,
              let youtubeVideoID else {
            return
        }

        captionStatus = "Načítám české titulky…"

        Task {
            do {
                let result = try await CaptionService.shared.preferredCaptions(
                    videoID: youtubeVideoID,
                    preferredLanguage: captionLanguage,
                    allowTranslation: allowCaptionTranslation
                )

                guard let result else {
                    captionStatus = "České titulky nejsou dostupné"
                    return
                }

                cues = result.cues
                captionStatus = result.displayName
                installCaptionObserver()
            } catch {
                captionStatus = "Titulky: \(error.localizedDescription)"
            }
        }
    }

    private func installCaptionObserver() {
        guard timeObserver == nil, !cues.isEmpty else { return }

        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            let seconds = time.seconds

            guard seconds.isFinite else {
                self.currentCaption = ""
                return
            }

            self.currentCaption = self.captionText(at: seconds) ?? ""
        }
    }

    private func captionText(at time: TimeInterval) -> String? {
        var lower = 0
        var upper = cues.count - 1

        while lower <= upper {
            let middle = (lower + upper) / 2
            let cue = cues[middle]

            if time < cue.start {
                upper = middle - 1
            } else if time >= cue.end {
                lower = middle + 1
            } else {
                return cue.text
            }
        }

        return nil
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

    init(
        source: PlaybackSource,
        youtubeVideoID: String?,
        captionsEnabled: Bool,
        captionLanguage: String,
        allowCaptionTranslation: Bool
    ) {
        _model = StateObject(
            wrappedValue: NativePlayerModel(
                source: source,
                youtubeVideoID: youtubeVideoID,
                captionsEnabled: captionsEnabled,
                captionLanguage: captionLanguage,
                allowCaptionTranslation: allowCaptionTranslation
            )
        )
    }

    var body: some View {
        ZStack {
            VideoPlayer(player: model.player)
                .ignoresSafeArea()

            if model.isPreparing {
                ProgressView("Připravuji video…")
                    .font(.title3)
            }

            VStack {
                Spacer()

                if !model.currentCaption.isEmpty {
                    Text(model.currentCaption)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(.black.opacity(0.78))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .frame(maxWidth: 1300)
                        .padding(.bottom, 90)
                        .allowsHitTesting(false)
                }

                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(.black.opacity(0.75))
                        .clipShape(Capsule())
                        .padding(.bottom, 28)
                        .allowsHitTesting(false)
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
