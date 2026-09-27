import AVFoundation
import AVKit
import OSLog
import SwiftUI

private func localizedLanguageName(
    _ languageCode: String,
    localeCode: String
) -> String {
    Locale(identifier: localeCode)
        .localizedString(
            forLanguageCode: languageCode
        )?
        .capitalized
        ?? languageCode.uppercased()
}

struct PlayerAudioTrackInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let languageCode: String
    let isOriginal: Bool
}

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
                        ? "\(L10n.text("captions", languageCode: appLanguage)): \(localizedLanguageName(preferredCaptionLanguage, localeCode: appLanguage))"
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
    @Published private(set) var activeCaptionLanguageCode: String?
    @Published private(set) var captionOptions: [CaptionLanguageOption] = []
    @Published private(set) var activeQuality: String
    @Published private(set) var formatInfo: PlaybackFormatInfo?
    @Published private(set) var playbackRate: Float = 1.0
    @Published private(set) var captionsAreEnabled: Bool
    @Published private(set) var isSwitchingQuality = false
    @Published private(set) var isSwitchingAudio = false
    @Published private(set) var availableQualityHeights: [Int]
    @Published private(set) var activeClientProfile: String?
    @Published private(set) var availableAudioTracks: [PlayerAudioTrackInfo] = []
    @Published private(set) var activeAudioTrackID: String?

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
    private var failedClientProfiles = Set<String>()

    private let playbackLogger = Logger(
        subsystem: "cz.caseycz.tubetv",
        category: "PlaybackFailover"
    )

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
        availableQualityHeights =
            source.availableQualityHeights
        activeClientProfile =
            source.clientProfile
        activeAudioTrackID =
            source.activeAudioTrackID
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
        failedClientProfiles.removeAll()

        await prepareWithFailover(
            startingFrom: currentSource
        )
    }

    private func prepareWithFailover(
        startingFrom initialSource: PlaybackSource
    ) async {
        var nextSource: PlaybackSource? = initialSource
        var attemptedSources = Set<PlaybackSource>()
        var lastError: Error =
            StreamResolverError.noPlayableStream

        for attempt in 1...10 {
            guard let source = nextSource,
                  !attemptedSources.contains(source) else {
                break
            }

            attemptedSources.insert(source)
            let profile =
                source.clientProfile ?? "UNTAGGED"

            playbackLogger.notice(
                "Attempt=\(attempt, privacy: .public) profile=\(profile, privacy: .public)"
            )

            do {
                try await activateAndVerify(
                    source
                )

                currentSource = source
                activeClientProfile =
                    source.clientProfile
                isPreparing = false
                errorMessage = nil

                playbackLogger.notice(
                    "READY profile=\(profile, privacy: .public)"
                )

                startCaptionLoadingIfNeeded()
                startHistoryTrackingIfNeeded()
                loadCaptionOptions()
                scheduleCISmokeVerificationIfNeeded()
                return
            } catch {
                lastError = error
                player.pause()

                playbackLogger.error(
                    "FAILED profile=\(profile, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )

                if let localFallback =
                    fallbackSource(from: source),
                   !attemptedSources.contains(
                    localFallback
                   ) {
                    nextSource = localFallback
                    continue
                }

                guard let youtubeVideoID,
                      let failedProfile =
                        source.clientProfile else {
                    nextSource = nil
                    break
                }

                failedClientProfiles.insert(
                    failedProfile
                )

                do {
                    nextSource =
                        try await StreamResolver
                            .resolveYouTubeVideo(
                                videoID:
                                    youtubeVideoID,
                                preferredQuality:
                                    activeQuality,
                                excludingProfiles:
                                    failedClientProfiles
                            )
                } catch {
                    lastError = error
                    nextSource = nil
                }
            }
        }

        isPreparing = false
        errorMessage =
            lastError.localizedDescription
    }

    private func activateAndVerify(
        _ source: PlaybackSource
    ) async throws {
        let item =
            try await makePlayerItem(
                from: source
            )

        currentSource = source
        player.replaceCurrentItem(
            with: item
        )
        play()

        try await waitUntilReadyToPlay(
            item
        )

        await updateFormatInfo(
            from: item
        )
        await loadAudioTracks(
            from: item,
            source: source
        )
        refreshAvailableQualityHeights(
            for: source
        )
    }

    private func waitUntilReadyToPlay(
        _ item: AVPlayerItem
    ) async throws {
        for _ in 0..<100 {
            switch item.status {
            case .readyToPlay:
                return

            case .failed:
                throw item.error
                    ?? StreamResolverError
                        .noPlayableStream

            case .unknown:
                break

            @unknown default:
                break
            }

            try await Task.sleep(
                nanoseconds: 100_000_000
            )
        }

        throw StreamResolverError
            .noPlayableStream
    }

    var preferredCaptionDisplayName: String {
        localizedLanguageName(
            preferredCaptionLanguage,
            localeCode: L10n.currentLanguageCode
        )
    }

    var isPreferredCaptionActive: Bool {
        guard captionsAreEnabled,
              let activeCaptionLanguageCode else {
            return false
        }

        if activeCaptionLanguageCode
            .caseInsensitiveCompare(
                preferredCaptionLanguage
            ) == .orderedSame {
            return true
        }

        let activeBase =
            activeCaptionLanguageCode
                .split(separator: "-")
                .first
                .map(String.init)
                ?? activeCaptionLanguageCode
        let preferredBase =
            preferredCaptionLanguage
                .split(separator: "-")
                .first
                .map(String.init)
                ?? preferredCaptionLanguage

        return activeBase
            .caseInsensitiveCompare(
                preferredBase
            ) == .orderedSame
    }

    var currentPlaybackDescription: String {
        let fallbackQuality =
            activeQuality == "Auto"
                ? L10n.text("automatic")
                : activeQuality

        return [
            formatInfo?.displayName
                ?? fallbackQuality,
            activeClientProfile
        ]
        .compactMap { value in
            guard let value,
                  !value.isEmpty else {
                return nil
            }

            return value
        }
        .joined(separator: " • ")
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
        let savedSeconds = oldTime.seconds
        let wasPlaying =
            player.timeControlStatus == .playing

        isSwitchingQuality = true
        errorMessage = nil
        player.pause()

        playbackLogger.notice(
            "Quality switch start from=\(self.activeQuality, privacy: .public) to=\(quality, privacy: .public) saved=\(savedSeconds, privacy: .public)"
        )

        do {
            let resolvedSource =
                try await StreamResolver
                    .resolveYouTubeVideo(
                        videoID: youtubeVideoID,
                        preferredQuality: quality
                    )

            let newSource =
                activeAudioTrackID.flatMap {
                    resolvedSource
                        .replacingAudioTrack(
                            id: $0
                        )
                }
                ?? resolvedSource

            let newItem =
                try await makePlayerItem(
                    from: newSource
                )

            currentSource = newSource
            player.replaceCurrentItem(
                with: newItem
            )

            // Match SmartTubeIOS: do not seek a newly replaced item
            // while it is still .unknown. AVPlayer can ignore that seek.
            // Wait until the new quality is actually ready first.
            try await waitUntilReadyToPlay(
                newItem
            )

            if savedSeconds.isFinite,
               savedSeconds > 0 {
                await seek(to: oldTime)
            }

            await updateFormatInfo(
                from: newItem
            )
            await loadAudioTracks(
                from: newItem,
                source: newSource
            )
            refreshAvailableQualityHeights(
                for: newSource
            )

            activeQuality = quality
            activeClientProfile =
                newSource.clientProfile

            let restoredSeconds =
                player.currentTime().seconds

            playbackLogger.notice(
                "Quality switch ready quality=\(quality, privacy: .public) saved=\(savedSeconds, privacy: .public) restored=\(restoredSeconds, privacy: .public)"
            )

            if wasPlaying {
                play()
            } else {
                player.pause()
            }
        } catch {
            errorMessage =
                "\(L10n.text("quality_change_error")): \(error.localizedDescription)"

            playbackLogger.error(
                "Quality switch failed quality=\(quality, privacy: .public) saved=\(savedSeconds, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )

            if wasPlaying {
                play()
            }
        }

        isSwitchingQuality = false
    }

    var canSwitchAudioTracks: Bool {
        if currentSource.activeAudioTrackID != nil {
            return currentSource
                .availableAudioTracks
                .count > 1
        }

        return activeAudioTrackID?
            .hasPrefix("native:") == true
            && availableAudioTracks.count > 1
    }

    func changeAudio(
        _ track: PlayerAudioTrackInfo
    ) async {
        guard !isSwitchingAudio,
              !isSwitchingQuality,
              track.id != activeAudioTrackID else {
            return
        }

        if track.id.hasPrefix("native:") {
            await changeNativeAudio(
                track
            )
            return
        }

        guard let newSource =
                currentSource
                    .replacingAudioTrack(
                        id: track.id
                    ) else {
            return
        }

        let oldTime = player.currentTime()
        let savedSeconds = oldTime.seconds
        let wasPlaying =
            player.timeControlStatus == .playing

        isSwitchingAudio = true
        errorMessage = nil
        player.pause()

        playbackLogger.notice(
            "Audio switch start from=\(self.activeAudioTrackID ?? "none", privacy: .public) to=\(track.id, privacy: .public) saved=\(savedSeconds, privacy: .public)"
        )

        defer {
            isSwitchingAudio = false
        }

        do {
            let newItem =
                try await makePlayerItem(
                    from: newSource
                )

            currentSource = newSource
            player.replaceCurrentItem(
                with: newItem
            )

            try await waitUntilReadyToPlay(
                newItem
            )

            if savedSeconds.isFinite,
               savedSeconds > 0 {
                await seek(to: oldTime)
            }

            await updateFormatInfo(
                from: newItem
            )
            await loadAudioTracks(
                from: newItem,
                source: newSource
            )

            activeAudioTrackID =
                newSource.activeAudioTrackID

            let restoredSeconds =
                player.currentTime().seconds

            playbackLogger.notice(
                "Audio switch ready track=\(track.id, privacy: .public) saved=\(savedSeconds, privacy: .public) restored=\(restoredSeconds, privacy: .public)"
            )

            if wasPlaying {
                play()
            } else {
                player.pause()
            }
        } catch {
            errorMessage =
                "\(L10n.text("audio")): \(error.localizedDescription)"

            playbackLogger.error(
                "Audio switch failed track=\(track.id, privacy: .public) saved=\(savedSeconds, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )

            if wasPlaying {
                play()
            }
        }
    }

    private func changeNativeAudio(
        _ track: PlayerAudioTrackInfo
    ) async {
        guard let item = player.currentItem,
              let group = try? await item.asset
                .loadMediaSelectionGroup(
                    for: .audible
                ),
              let rawIndex = track.id
                .split(separator: ":")
                .last,
              let index = Int(rawIndex),
              group.options.indices
                .contains(index) else {
            return
        }

        isSwitchingAudio = true
        errorMessage = nil

        let option = group.options[index]

        player.appliesMediaSelectionCriteriaAutomatically =
            false
        item.select(
            option,
            in: group
        )
        activeAudioTrackID = track.id

        playbackLogger.notice(
            "Native audio switch track=\(track.id, privacy: .public) language=\(track.languageCode, privacy: .public)"
        )

        isSwitchingAudio = false
    }

    func disableCaptions() {
        captionsAreEnabled = false
        cues = []
        currentCaption = ""
        activeCaptionLanguageCode = nil
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
                preferTranslation: false,
                preferredAutoGenerated: nil
            )
        }
    }

    func selectCaption(_ option: CaptionLanguageOption) {
        guard let youtubeVideoID else { return }

        captionsAreEnabled = true
        captionStatus = L10n.text("loading_captions")

        Task {
            await loadCaptions(
                videoID: youtubeVideoID,
                languageCode: option.languageCode,
                preferTranslation: !option.isNative,
                preferredAutoGenerated:
                    option.isNative
                        ? option.isAutoGenerated
                        : nil
            )
        }
    }

    private func loadCaptions(
        videoID: String,
        languageCode: String,
        preferTranslation: Bool,
        preferredAutoGenerated: Bool?
    ) async {
        do {
            let result = try await CaptionService.shared.captions(
                videoID: videoID,
                languageCode: languageCode,
                preferTranslation: preferTranslation,
                preferredAutoGenerated:
                    preferredAutoGenerated,
                allowTranslation: allowCaptionTranslation
            )

            guard let result else {
                cues = []
                currentCaption = ""
                activeCaptionLanguageCode = nil
                captionStatus = L10n.text("captions_unavailable")
                return
            }

            cues = result.cues
            activeCaptionLanguageCode =
                result.languageCode
            captionStatus = result.displayName
            installCaptionObserver()
        } catch {
            cues = []
            currentCaption = ""
            activeCaptionLanguageCode = nil
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

        captionStatus = L10n.text("loading_captions")

        Task {
            await loadCaptions(
                videoID: youtubeVideoID,
                languageCode: preferredCaptionLanguage,
                preferTranslation: false,
                preferredAutoGenerated: nil
            )
        }
    }

    private func loadCaptionOptions() {
        guard let youtubeVideoID else { return }

        Task {
            do {
                captionOptions =
                    try await CaptionService.shared.availableLanguages(
                        videoID: youtubeVideoID,
                        preferredLanguage:
                            preferredCaptionLanguage,
                        allowTranslation:
                            allowCaptionTranslation
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

    private func loadAudioTracks(
        from item: AVPlayerItem,
        source: PlaybackSource
    ) async {
        let youtubeTracks =
            source.availableAudioTracks

        if source.activeAudioTrackID != nil,
           !youtubeTracks.isEmpty {
            activeAudioTrackID =
                source.activeAudioTrackID

            availableAudioTracks =
                youtubeTracks.map {
                    PlayerAudioTrackInfo(
                        id: $0.id,
                        name: $0.displayName,
                        languageCode:
                            $0.languageCode,
                        isOriginal:
                            $0.isOriginal
                    )
                }

            playbackLogger.notice(
                "YouTube audio tracks loaded count=\(youtubeTracks.count, privacy: .public) original=\(youtubeTracks.first(where: { $0.isOriginal })?.languageCode ?? "none", privacy: .public)"
            )
            return
        }

        guard let group = try? await item.asset
            .loadMediaSelectionGroup(
                for: .audible
            ),
            !group.options.isEmpty else {
            availableAudioTracks = []
            return
        }

        let selectedOption =
            item.currentMediaSelection
                .selectedMediaOption(
                    in: group
                )

        let selectedIndex =
            selectedOption.flatMap {
                selected in
                group.options.firstIndex(
                    where: {
                        $0 === selected
                    }
                )
            }
            ?? group.defaultOption.flatMap {
                defaultOption in
                group.options.firstIndex(
                    where: {
                        $0 === defaultOption
                    }
                )
            }

        let mainOptions = group.options.filter {
            $0.hasMediaCharacteristic(
                .isMainProgramContent
            )
        }
        let mainDiscriminates =
            !mainOptions.isEmpty
            && mainOptions.count
                < group.options.count

        let initialTracks =
            group.options.enumerated().map {
                index,
                option in

                let languageCode =
                    option.locale?.identifier
                    ?? option.extendedLanguageTag
                    ?? "und"

                let localizedName =
                    Locale(
                        identifier:
                            L10n.currentLanguageCode
                    )
                    .localizedString(
                        forLanguageCode:
                            languageCode
                    )
                    ?? option.displayName

                let isDefault =
                    group.defaultOption.map {
                        defaultOption in
                        defaultOption === option
                            || (
                                defaultOption.locale
                                    != nil
                                && defaultOption.locale
                                    == option.locale
                            )
                            || (
                                defaultOption
                                    .extendedLanguageTag
                                    != nil
                                && defaultOption
                                    .extendedLanguageTag
                                    == option
                                        .extendedLanguageTag
                            )
                    } ?? false

                let isOriginal =
                    mainDiscriminates
                        ? option
                            .hasMediaCharacteristic(
                                .isMainProgramContent
                            )
                        : isDefault

                return PlayerAudioTrackInfo(
                    id:
                        "native:\(index)",
                    name: localizedName,
                    languageCode:
                        languageCode,
                    isOriginal:
                        isOriginal
                )
            }

        var tracks = initialTracks

        if tracks.count > 1,
           !tracks.contains(where: {
                $0.isOriginal
           }) {
            let nonAuxiliaryIndices =
                group.options.indices.filter {
                    !group.options[$0]
                        .hasMediaCharacteristic(
                            .isAuxiliaryContent
                        )
                }

            if nonAuxiliaryIndices.count == 1,
               let originalIndex =
                    nonAuxiliaryIndices.first {
                tracks = tracks.enumerated().map {
                    index,
                    track in
                    PlayerAudioTrackInfo(
                        id: track.id,
                        name: track.name,
                        languageCode:
                            track.languageCode,
                        isOriginal:
                            index
                                == originalIndex
                    )
                }
            }
        }

        if !tracks.isEmpty,
           !tracks.contains(where: {
                $0.isOriginal
           }),
           let lastID = tracks.last?.id {
            tracks = tracks.map {
                PlayerAudioTrackInfo(
                    id: $0.id,
                    name: $0.name,
                    languageCode:
                        $0.languageCode,
                    isOriginal:
                        $0.id == lastID
                )
            }
        }

        availableAudioTracks = tracks
        activeAudioTrackID =
            selectedIndex.map {
                "native:\($0)"
            }

        playbackLogger.notice(
            "Audio tracks loaded count=\(tracks.count, privacy: .public) selected=\(self.activeAudioTrackID ?? "none", privacy: .public) original=\(tracks.first(where: { $0.isOriginal })?.languageCode ?? "none", privacy: .public)"
        )
    }

    private func refreshAvailableQualityHeights(
        for source: PlaybackSource
    ) {
        var initial = Set(
            source.availableQualityHeights
        )

        if let height = formatInfo?.height,
           height > 0 {
            initial.insert(height)
        }

        availableQualityHeights =
            initial.sorted(by: >)

        guard let request =
                hlsManifestRequest(
                    for: source
                ) else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }

            let manifestHeights =
                await self.fetchHLSHeights(
                    request: request
                )

            guard !manifestHeights.isEmpty
            else {
                return
            }

            let responseHeights = Set(
                source.availableQualityHeights
            )
            var filtered: Set<Int>

            if responseHeights.isEmpty {
                filtered = manifestHeights
            } else {
                filtered = Set(
                    responseHeights.filter {
                        manifestHeights.contains($0)
                    }
                )
            }

            if let currentHeight =
                    self.formatInfo?.height,
               manifestHeights.contains(
                currentHeight
               ) {
                filtered.insert(
                    currentHeight
                )
            }

            self.availableQualityHeights =
                filtered.sorted(by: >)

            self.playbackLogger.notice(
                "Quality tiers profile=\(source.clientProfile ?? "UNTAGGED", privacy: .public) heights=\(self.availableQualityHeights.description, privacy: .public)"
            )
        }
    }

    private func hlsManifestRequest(
        for source: PlaybackSource
    ) -> URLRequest? {
        let url: URL
        let headers: PlaybackRequestHeaders?

        switch source {
        case .direct(let directURL):
            url = directURL
            headers = nil

        case .directWithHeaders(
            let directURL,
            let requestHeaders
        ):
            url = directURL
            headers = requestHeaders

        case .adaptive, .adaptiveWithHeaders:
            return nil
        }

        let raw = url.absoluteString.lowercased()

        guard url.pathExtension.lowercased()
                == "m3u8"
                || raw.contains("hls_playlist")
                || raw.contains("/manifest/")
        else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8

        if let headers {
            for (field, value)
                in headers.dictionary {
                request.setValue(
                    value,
                    forHTTPHeaderField: field
                )
            }
        }

        return request
    }

    private func fetchHLSHeights(
        request: URLRequest
    ) async -> Set<Int> {
        do {
            let (data, response) =
                try await URLSession.shared
                    .data(for: request)

            guard let http =
                    response as? HTTPURLResponse,
                  (200..<300).contains(
                    http.statusCode
                  ),
                  let text = String(
                    data: data,
                    encoding: .utf8
                  ) else {
                return []
            }

            return Self.parseHLSHeights(
                text
            )
        } catch {
            return []
        }
    }

    private static func parseHLSHeights(
        _ manifest: String
    ) -> Set<Int> {
        let pattern =
            #"RESOLUTION=\d+x(\d+)"#

        guard let regex =
                try? NSRegularExpression(
                    pattern: pattern,
                    options: [.caseInsensitive]
                ) else {
            return []
        }

        let range = NSRange(
            manifest.startIndex...,
            in: manifest
        )

        var heights = Set<Int>()

        for match in regex.matches(
            in: manifest,
            range: range
        ) {
            guard match.numberOfRanges > 1,
                  let heightRange =
                    Range(
                        match.range(at: 1),
                        in: manifest
                    ),
                  let height =
                    Int(
                        manifest[
                            heightRange
                        ]
                    ),
                  height > 0 else {
                continue
            }

            heights.insert(height)
        }

        return heights
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
    case audio
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
                case .audio:
                    audioPage
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
        case .audio:
            return L10n.text("audio", languageCode: appLanguage)
        case .speed:
            return L10n.text("speed", languageCode: appLanguage)
        }
    }

    private var rootPage: some View {
        VStack(spacing: 14) {
            settingsButton(
                title: L10n.text("quality", languageCode: appLanguage),
                value: model.currentPlaybackDescription,
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

            if !model.availableAudioTracks.isEmpty {
                settingsButton(
                    title: L10n.text(
                        "audio",
                        languageCode: appLanguage
                    ),
                    value: audioSummary,
                    icon: "speaker.wave.2.fill"
                ) {
                    page = .audio
                }
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
                qualityButton(
                    "Auto",
                    label: L10n.text(
                        "automatic",
                        languageCode: appLanguage
                    )
                )

                ForEach(
                    model.availableQualityHeights,
                    id: \.self
                ) { height in
                    qualityButton(
                        "\(height)p",
                        label: qualityLabel(
                            for: height
                        )
                    )
                }

                if let format = model.formatInfo {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.text("current_playback", languageCode: appLanguage))
                            .font(.headline)

                        Text(
                            model.currentPlaybackDescription
                        )
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
                        "\(model.preferredCaptionDisplayName) – \(L10n.text("automatic", languageCode: appLanguage))",
                        selected:
                            model.isPreferredCaptionActive
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

    private var audioPage: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(
                    model.availableAudioTracks
                ) { track in
                    Button {
                        Task {
                            await model.changeAudio(
                                track
                            )
                            page = .root
                        }
                    } label: {
                        HStack {
                            VStack(
                                alignment: .leading,
                                spacing: 4
                            ) {
                                Text(track.name)

                                Text(
                                    track.languageCode
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    .secondary
                                )
                            }

                            Spacer()

                            if track.isOriginal {
                                Text(
                                    L10n.text(
                                        "original_audio",
                                        languageCode:
                                            appLanguage
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    .secondary
                                )
                            }

                            if model.activeAudioTrackID
                                == track.id {
                                Image(
                                    systemName:
                                        "checkmark"
                                )
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .disabled(
                        !model.canSwitchAudioTracks
                        || model.isSwitchingAudio
                    )
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

    private func qualityLabel(
        for height: Int
    ) -> String {
        if height >= 4320 {
            return "8K / \(height)p"
        }

        if height >= 2160 {
            return "4K / \(height)p"
        }

        return "\(height)p"
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

    private var audioSummary: String {
        if let activeID =
                model.activeAudioTrackID,
           let active =
                model.availableAudioTracks
                    .first(where: {
                        $0.id == activeID
                    }) {
            return active.name
        }

        if let original =
                model.availableAudioTracks
                    .first(where: {
                        $0.isOriginal
                    }) {
            return original.name
        }

        return "\(model.availableAudioTracks.count)"
    }

    private func rateLabel(_ rate: Float) -> String {
        if abs(rate - 1.0) < 0.001 {
            return L10n.text("normal_speed", languageCode: appLanguage)
        }

        return String(format: "%.2gx", rate)
    }
}
