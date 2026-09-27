import AVFoundation
import AVKit
import OSLog
import SwiftUI

struct VideoDetailView: View {
    let video: VideoItem

    @AppStorage("appLanguage") private var appLanguage =
        AppLanguage.english.rawValue
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

            if let channelID = video.channelID {
                NavigationLink {
                    ChannelView(
                        channelID: channelID,
                        fallbackTitle: video.channel
                    )
                } label: {
                    Label(video.channel, systemImage: "person.crop.circle")
                        .font(.title2)
                }
                .buttonStyle(.plain)
            } else {
                Text(video.channel)
                    .font(.title2)
            }

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
                            Text(L10n.text("loading_stream", languageCode: appLanguage))
                        }
                    } else {
                        Label(L10n.text("play", languageCode: appLanguage), systemImage: "play.fill")
                    }
                }
                .disabled(!canPlay || isResolving)

                Label(
                    autoEnableCaptions
                        ? "\(L10n.text("captions", languageCode: appLanguage)): Čeština"
                        : "\(L10n.text("captions", languageCode: appLanguage)): \(L10n.text("captions_off", languageCode: appLanguage))",
                    systemImage: "captions.bubble.fill"
                )
                .foregroundStyle(.secondary)
            }

            if video.youtubeVideoID != nil {
                Label(
                    preferredQuality == "Auto"
                        ? "\(L10n.text("quality", languageCode: appLanguage)): \(L10n.text("automatic", languageCode: appLanguage))"
                        : "\(L10n.text("preferred_quality", languageCode: appLanguage)): \(preferredQuality)",
                    systemImage: "4k.tv"
                )
                .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Label(
                    errorMessage,
                    systemImage: "exclamationmark.triangle.fill"
                )
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
                    initialQuality: preferredQuality,
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
            errorMessage = L10n.text(
                "no_playback_source",
                languageCode: appLanguage
            )
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
    @Published private(set) var captionOptions: [CaptionLanguageOption] = []
    @Published private(set) var activeQuality: String
    @Published private(set) var formatInfo: PlaybackFormatInfo?
    @Published private(set) var playbackRate: Float = 1.0
    @Published private(set) var captionsAreEnabled: Bool
    @Published private(set) var isSwitchingQuality = false

    private var currentSource: PlaybackSource
    private let youtubeVideoID: String?
    private let preferredCaptionLanguage: String
    private let allowCaptionTranslation: Bool

    private var didPrepare = false
    private var cues: [CaptionCue] = []
    private var timeObserver: Any?
    private var trackingObserver: Any?
    private var trackingContext: YouTubeTrackingContext?
    private var ciSmokeVerificationScheduled = false

    private let ciLogger = Logger(
        subsystem: "cz.caseycz.tubetv",
        category: "CI"
    )

    init(
        source: PlaybackSource,
        youtubeVideoID: String?,
        initialQuality: String,
        captionsEnabled: Bool,
        captionLanguage: String,
        allowCaptionTranslation: Bool
    ) {
        currentSource = source
        self.youtubeVideoID = youtubeVideoID
        activeQuality = initialQuality
        captionsAreEnabled = captionsEnabled
        preferredCaptionLanguage = captionLanguage
        self.allowCaptionTranslation = allowCaptionTranslation
    }

    func prepareAndPlay() async {
        guard !didPrepare else {
            play()
            return
        }

        didPrepare = true
        isPreparing = true
        errorMessage = nil

        do {
            let item = try await makePlayerItem(from: currentSource)
            player.replaceCurrentItem(with: item)
            await updateFormatInfo(from: item)
            isPreparing = false
            play()
            startCaptionLoadingIfNeeded()
            startHistoryTrackingIfNeeded()
            loadCaptionOptions()
            scheduleCISmokeVerificationIfNeeded()
        } catch {
            if let fallbackSource = fallbackSource(from: currentSource) {
                do {
                    let fallbackItem = try await makePlayerItem(
                        from: fallbackSource
                    )
                    player.replaceCurrentItem(with: fallbackItem)
                    currentSource = fallbackSource
                    await updateFormatInfo(from: fallbackItem)
                    isPreparing = false
                    errorMessage = L10n.text("adaptive_fallback")
                    play()
                    startCaptionLoadingIfNeeded()
                    startHistoryTrackingIfNeeded()
                    loadCaptionOptions()
                    scheduleCISmokeVerificationIfNeeded()
                } catch {
                    isPreparing = false
                    errorMessage = error.localizedDescription
                }
            } else {
                isPreparing = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func pause() {
        sendHistoryProgress()
        player.pause()
    }

    func cleanup() {
        sendHistoryProgress()
        player.pause()

        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }

        if let trackingObserver {
            player.removeTimeObserver(trackingObserver)
            self.trackingObserver = nil
        }
    }

    func play() {
        player.playImmediately(atRate: playbackRate)
    }

    private func scheduleCISmokeVerificationIfNeeded() {
        guard !ciSmokeVerificationScheduled,
              ProcessInfo.processInfo.environment[
                "TUBETV_CI_VIDEO_SMOKE"
              ] == "1" else {
            return
        }

        ciSmokeVerificationScheduled = true

        Task { @MainActor [weak self] in
            try? await Task.sleep(
                nanoseconds: 10_000_000_000
            )

            guard let self else { return }

            let seconds = self.player.currentTime().seconds
            let rate = self.player.rate
            let status = String(
                describing: self.player.timeControlStatus
            )

            self.ciLogger.notice(
                "TUBETV_VIDEO_PLAYBACK time=\(seconds, privacy: .public) rate=\(rate, privacy: .public) status=\(status, privacy: .public)"
            )

            if seconds.isFinite && seconds > 0.5 {
                self.ciLogger.notice(
                    "TUBETV_VIDEO_PLAYBACK_OK"
                )
            } else {
                self.ciLogger.error(
                    "TUBETV_VIDEO_PLAYBACK_FAILED"
                )
            }
        }
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate

        if player.timeControlStatus == .playing {
            player.playImmediately(atRate: rate)
        }
    }

    func changeQuality(_ quality: String) async {
        guard let youtubeVideoID,
              !isSwitchingQuality,
              quality != activeQuality else {
            return
        }

        let oldTime = player.currentTime()
        let wasPlaying = player.timeControlStatus == .playing

        isSwitchingQuality = true
        errorMessage = nil
        player.pause()

        do {
            let newSource = try await StreamResolver.resolveYouTubeVideo(
                videoID: youtubeVideoID,
                preferredQuality: quality
            )

            let newItem = try await makePlayerItem(from: newSource)
            currentSource = newSource
            player.replaceCurrentItem(with: newItem)
            await updateFormatInfo(from: newItem)

            await seek(to: oldTime)
            activeQuality = quality

            if wasPlaying {
                play()
            }
        } catch {
            errorMessage =
                "\(L10n.text("quality_change_error")): \(error.localizedDescription)"

            if wasPlaying {
                play()
            }
        }

        isSwitchingQuality = false
    }

    func disableCaptions() {
        captionsAreEnabled = false
        cues = []
        currentCaption = ""
        captionStatus = L10n.text("captions_off")
    }

    func enablePreferredCaptions() {
        guard let youtubeVideoID else { return }

        captionsAreEnabled = true
        captionStatus = L10n.text("loading_captions")

        Task {
            await loadCaptions(
                videoID: youtubeVideoID,
                languageCode: preferredCaptionLanguage,
                preferTranslation: false
            )
        }
    }

    func selectCaption(_ option: CaptionLanguageOption) {
        guard let youtubeVideoID else { return }

        captionsAreEnabled = true
        captionStatus = "Načítám \(option.displayName)…"

        Task {
            await loadCaptions(
                videoID: youtubeVideoID,
                languageCode: option.languageCode,
                preferTranslation: !option.isNative
            )
        }
    }

    private func loadCaptions(
        videoID: String,
        languageCode: String,
        preferTranslation: Bool
    ) async {
        do {
            let result = try await CaptionService.shared.captions(
                videoID: videoID,
                languageCode: languageCode,
                preferTranslation: preferTranslation,
                allowTranslation: allowCaptionTranslation
            )

            guard let result else {
                cues = []
                currentCaption = ""
                captionStatus = L10n.text("captions_unavailable")
                return
            }

            cues = result.cues
            captionStatus = result.displayName
            installCaptionObserver()
        } catch {
            cues = []
            currentCaption = ""
            captionStatus = error.localizedDescription
        }
    }

    private func startHistoryTrackingIfNeeded() {
        guard let youtubeVideoID else { return }

        Task {
            guard await SmartTubeAuthService.shared.signedIn() else {
                return
            }

            do {
                let context =
                    try await YouTubeTrackingService.shared.makeContext(
                        videoID: youtubeVideoID
                    )

                trackingContext = context
                installTrackingObserver()
            } catch {
                // History tracking must never block playback.
            }
        }
    }

    private func installTrackingObserver() {
        guard trackingObserver == nil,
              trackingContext != nil else {
            return
        }

        let interval = CMTime(seconds: 15, preferredTimescale: 600)

        trackingObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sendHistoryProgress()
            }
        }
    }

    private func sendHistoryProgress() {
        guard let context = trackingContext else { return }

        let position = player.currentTime().seconds
        let duration = player.currentItem?.duration.seconds ?? .nan

        guard position.isFinite,
              duration.isFinite,
              duration > 0 else {
            return
        }

        Task {
            await YouTubeTrackingService.shared.update(
                context: context,
                position: position,
                duration: duration
            )
        }
    }

    private func startCaptionLoadingIfNeeded() {
        guard captionsAreEnabled,
              let youtubeVideoID else {
            return
        }

        captionStatus = L10n.text("loading_czech_captions")

        Task {
            await loadCaptions(
                videoID: youtubeVideoID,
                languageCode: preferredCaptionLanguage,
                preferTranslation: false
            )
        }
    }

    private func loadCaptionOptions() {
        guard let youtubeVideoID else { return }

        Task {
            do {
                captionOptions =
                    try await CaptionService.shared.availableLanguages(
                        videoID: youtubeVideoID
                    )
            } catch {
                captionOptions = []
            }
        }
    }

    private func installCaptionObserver() {
        guard timeObserver == nil else { return }

        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            let seconds = time.seconds

            Task { @MainActor [weak self] in
                guard let self else { return }

                guard seconds.isFinite,
                      self.captionsAreEnabled else {
                    self.currentCaption = ""
                    return
                }

                self.currentCaption =
                    self.captionText(at: seconds) ?? ""
            }
        }
    }

    private func captionText(at time: TimeInterval) -> String? {
        guard !cues.isEmpty else { return nil }

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

    private func updateFormatInfo(
        from item: AVPlayerItem
    ) async {
        formatInfo = await PlaybackFormatInspector.inspect(
            asset: item.asset
        )
    }

    private func seek(to time: CMTime) async {
        await withCheckedContinuation { continuation in
            player.seek(
                to: time,
                toleranceBefore: .zero,
                toleranceAfter: .zero
            ) { _ in
                continuation.resume()
            }
        }
    }

    private func fallbackSource(
        from source: PlaybackSource
    ) -> PlaybackSource? {
        switch source {
        case .adaptive(_, _, let fallback):
            guard let fallback else {
                return nil
            }

            return .direct(fallback)

        case .adaptiveWithHeaders(
            _,
            _,
            let fallback,
            let headers
        ):
            guard let fallback else {
                return nil
            }

            return .directWithHeaders(
                fallback,
                headers
            )

        case .direct, .directWithHeaders:
            return nil
        }
    }

    private func makePlayerItem(
        from source: PlaybackSource
    ) async throws -> AVPlayerItem {
        switch source {
        case .direct(let url):
            return AVPlayerItem(url: url)

        case .directWithHeaders(
            let url,
            let headers
        ):
            return AVPlayerItem(
                asset: makeURLAsset(
                    url: url,
                    headers: headers
                )
            )

        case .adaptive(
            let videoURL,
            let audioURL,
            _
        ):
            return try await makeAdaptivePlayerItem(
                videoURL: videoURL,
                audioURL: audioURL,
                headers: nil
            )

        case .adaptiveWithHeaders(
            let videoURL,
            let audioURL,
            _,
            let headers
        ):
            return try await makeAdaptivePlayerItem(
                videoURL: videoURL,
                audioURL: audioURL,
                headers: headers
            )
        }
    }

    private func makeURLAsset(
        url: URL,
        headers: PlaybackRequestHeaders?
    ) -> AVURLAsset {
        guard let headers else {
            return AVURLAsset(url: url)
        }

        return AVURLAsset(
            url: url,
            options: [
                "AVURLAssetHTTPHeaderFieldsKey":
                    headers.dictionary
            ]
        )
    }

    private func makeAdaptivePlayerItem(
        videoURL: URL,
        audioURL: URL,
        headers: PlaybackRequestHeaders?
    ) async throws -> AVPlayerItem {
        let videoAsset = makeURLAsset(
            url: videoURL,
            headers: headers
        )
        let audioAsset = makeURLAsset(
            url: audioURL,
            headers: headers
        )

        async let loadedVideoTracks =
            videoAsset.loadTracks(withMediaType: .video)
        async let loadedAudioTracks =
            audioAsset.loadTracks(withMediaType: .audio)
        async let loadedVideoDuration =
            videoAsset.load(.duration)
        async let loadedAudioDuration =
            audioAsset.load(.duration)

        let videoTracks = try await loadedVideoTracks
        let audioTracks = try await loadedAudioTracks
        let videoDuration = try await loadedVideoDuration
        let audioDuration = try await loadedAudioDuration

        guard let sourceVideoTrack = videoTracks.first,
              let sourceAudioTrack = audioTracks.first else {
            throw StreamResolverError.noPlayableStream
        }

        let duration = CMTimeCompare(
            videoDuration,
            audioDuration
        ) <= 0 ? videoDuration : audioDuration

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

        let range = CMTimeRange(
            start: .zero,
            duration: duration
        )

        try videoTrack.insertTimeRange(
            range,
            of: sourceVideoTrack,
            at: .zero
        )
        try audioTrack.insertTimeRange(
            range,
            of: sourceAudioTrack,
            at: .zero
        )

        return AVPlayerItem(asset: composition)
    }

}

private enum PlayerSettingsPage {
    case root
    case quality
    case captions
    case speed
}

struct NativePlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var appLanguage =
        AppLanguage.english.rawValue
    @StateObject private var model: NativePlayerModel

    @State private var showSettings = false
    @State private var settingsPage: PlayerSettingsPage = .root

    init(
        source: PlaybackSource,
        youtubeVideoID: String?,
        initialQuality: String,
        captionsEnabled: Bool,
        captionLanguage: String,
        allowCaptionTranslation: Bool
    ) {
        _model = StateObject(
            wrappedValue: NativePlayerModel(
                source: source,
                youtubeVideoID: youtubeVideoID,
                initialQuality: initialQuality,
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

            if model.isPreparing || model.isSwitchingQuality {
                ProgressView(
                    model.isSwitchingQuality
                        ? L10n.text("switching_quality", languageCode: appLanguage)
                        : L10n.text("preparing_video", languageCode: appLanguage)
                )
                .font(.title3)
            }

            VStack {
                HStack {
                    Spacer()

                    Button {
                        settingsPage = .root
                        showSettings.toggle()
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                            .padding(10)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 38)
                    .padding(.trailing, 48)
                }

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

            if showSettings {
                PlayerSettingsOverlay(
                    model: model,
                    page: $settingsPage,
                    isPresented: $showSettings
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showSettings)
        .task {
            await model.prepareAndPlay()
        }
        .onDisappear {
            model.cleanup()
        }
        .onExitCommand {
            if showSettings {
                if settingsPage == .root {
                    showSettings = false
                } else {
                    settingsPage = .root
                }
            } else {
                dismiss()
            }
        }
    }
}

private struct PlayerSettingsOverlay: View {
    @AppStorage("appLanguage") private var appLanguage =
        AppLanguage.english.rawValue
    @ObservedObject var model: NativePlayerModel
    @Binding var page: PlayerSettingsPage
    @Binding var isPresented: Bool

    var body: some View {
        HStack {
            Spacer()

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    if page != .root {
                        Button {
                            page = .root
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                    }

                    Text(title)
                        .font(.title2.bold())

                    Spacer()

                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                }

                Divider()

                switch page {
                case .root:
                    rootPage
                case .quality:
                    qualityPage
                case .captions:
                    captionsPage
                case .speed:
                    speedPage
                }

                Spacer()
            }
            .padding(30)
            .frame(width: 620)
            .frame(maxHeight: .infinity)
            .background(.ultraThinMaterial)
        }
        .ignoresSafeArea()
    }

    private var title: String {
        switch page {
        case .root:
            return L10n.text("playing", languageCode: appLanguage)
        case .quality:
            return L10n.text("quality", languageCode: appLanguage)
        case .captions:
            return L10n.text("captions", languageCode: appLanguage)
        case .speed:
            return L10n.text("speed", languageCode: appLanguage)
        }
    }

    private var rootPage: some View {
        VStack(spacing: 14) {
            settingsButton(
                title: L10n.text("quality", languageCode: appLanguage),
                value: model.formatInfo?.displayName
                    ?? (
                        model.activeQuality == "Auto"
                            ? L10n.text("automatic", languageCode: appLanguage)
                            : model.activeQuality
                    ),
                icon: "4k.tv"
            ) {
                page = .quality
            }

            settingsButton(
                title: L10n.text("captions", languageCode: appLanguage),
                value: model.captionsAreEnabled
                    ? (model.captionStatus ?? L10n.text("captions_on", languageCode: appLanguage))
                     : L10n.text("captions_off", languageCode: appLanguage),
                icon: "captions.bubble.fill"
            ) {
                page = .captions
            }

            settingsButton(
                title: L10n.text("speed", languageCode: appLanguage),
                value: rateLabel(model.playbackRate),
                icon: "speedometer"
            ) {
                page = .speed
            }
        }
    }

    private var qualityPage: some View {
        ScrollView {
            VStack(spacing: 12) {
                qualityButton("Auto", label: L10n.text("automatic", languageCode: appLanguage))
                qualityButton("1080p", label: "1080p")
                qualityButton("1440p", label: "1440p")
                qualityButton("2160p", label: "4K / 2160p")

                if let format = model.formatInfo {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.text("current_playback", languageCode: appLanguage))
                            .font(.headline)

                        Text(format.displayName)
                            .foregroundStyle(.secondary)

                        if format.width > 0 && format.height > 0 {
                            Text("\(format.width) × \(format.height)")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 18)
                }
            }
        }
    }

    private var captionsPage: some View {
        ScrollView {
            VStack(spacing: 12) {
                Button {
                    model.disableCaptions()
                    page = .root
                } label: {
                    optionRow(
                        L10n.text("captions_off", languageCode: appLanguage),
                        selected: !model.captionsAreEnabled
                    )
                }

                Button {
                    model.enablePreferredCaptions()
                    page = .root
                } label: {
                    optionRow(
                        L10n.text("czech_automatic", languageCode: appLanguage),
                        selected:
                            model.captionsAreEnabled
                            && (model.captionStatus ?? "")
                                .localizedCaseInsensitiveContains("če")
                    )
                }

                if model.captionOptions.isEmpty {
                    Text(L10n.text("loading_languages", languageCode: appLanguage))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 18)
                } else {
                    ForEach(model.captionOptions) { option in
                        Button {
                            model.selectCaption(option)
                            page = .root
                        } label: {
                            optionRow(
                                option.displayName,
                                selected:
                                    model.captionsAreEnabled
                                    && model.captionStatus
                                        == option.displayName
                            )
                        }
                    }
                }
            }
        }
    }

    private var speedPage: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(
                    [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0],
                    id: \.self
                ) { value in
                    Button {
                        model.setPlaybackRate(Float(value))
                        page = .root
                    } label: {
                        optionRow(
                            rateLabel(Float(value)),
                            selected:
                                abs(model.playbackRate - Float(value))
                                < 0.001
                        )
                    }
                }
            }
        }
    }

    private func qualityButton(
        _ value: String,
        label: String
    ) -> some View {
        Button {
            Task {
                await model.changeQuality(value)
                page = .root
            }
        } label: {
            optionRow(
                label,
                selected: model.activeQuality == value
            )
        }
        .disabled(model.isSwitchingQuality)
    }

    private func settingsButton(
        title: String,
        value: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Image(systemName: icon)
                    .frame(width: 38)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)

                    Text(value)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
            }
            .padding(.vertical, 8)
        }
    }

    private func optionRow(
        _ title: String,
        selected: Bool
    ) -> some View {
        HStack {
            Text(title)
                .multilineTextAlignment(.leading)

            Spacer()

            if selected {
                Image(systemName: "checkmark")
            }
        }
        .padding(.vertical, 8)
    }

    private func rateLabel(_ rate: Float) -> String {
        if abs(rate - 1.0) < 0.001 {
            return L10n.text("normal_speed", languageCode: appLanguage)
        }

        return String(format: "%.2gx", rate)
    }
}
