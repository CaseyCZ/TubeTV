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

    @State private var playbackSource: PlaybackSource?
    @State private var isResolving = false
    @State private var errorMessage: String?
    @State private var didStartResolving = false

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if let playbackSource {
                NativePlayerView(
                    source: playbackSource,
                    youtubeVideoID: video.youtubeVideoID,
                    videoTitle: video.title,
                    channelTitle: video.channel,
                    channelID: video.channelID,
                    initialQuality: preferredQuality,
                    captionsEnabled: autoEnableCaptions,
                    captionLanguage: preferredCaptionLanguage,
                    allowCaptionTranslation: autoTranslateCaptions
                )
            } else if let errorMessage {
                VStack(spacing: 24) {
                    Image(
                        systemName:
                            "exclamationmark.triangle.fill"
                    )
                    .font(.system(size: 54))

                    Text(errorMessage)
                        .font(.title3)
                        .multilineTextAlignment(.center)

                    Button {
                        Task {
                            await preparePlayback(
                                force: true
                            )
                        }
                    } label: {
                        Label(
                            L10n.text(
                                "play",
                                languageCode:
                                    appLanguage
                            ),
                            systemImage:
                                "arrow.clockwise"
                        )
                    }
                    .buttonStyle(
                        .borderedProminent
                    )
                }
                .padding(60)
            } else {
                VStack(spacing: 22) {
                    ProgressView()
                        .controlSize(.large)

                    Text(
                        L10n.text(
                            "preparing_video",
                            languageCode:
                                appLanguage
                        )
                    )
                    .font(.title3)

                    Text(video.title)
                        .font(.headline)
                        .foregroundStyle(
                            .secondary
                        )
                        .lineLimit(2)
                        .multilineTextAlignment(
                            .center
                        )
                }
                .padding(60)
            }
        }
        .task {
            await preparePlayback()
        }
        .onAppear {
            NotificationCenter.default.post(
                name:
                    .tubeTVPlayerVisibilityChanged,
                object: true
            )
        }
        .onDisappear {
            NotificationCenter.default.post(
                name:
                    .tubeTVPlayerVisibilityChanged,
                object: false
            )
        }
    }

    @MainActor
    private func preparePlayback(
        force: Bool = false
    ) async {
        guard force
                || !didStartResolving
        else {
            return
        }

        didStartResolving = true
        errorMessage = nil

        if let url = video.playbackURL {
            playbackSource = .direct(url)
            return
        }

        guard let videoID =
                video.youtubeVideoID
        else {
            errorMessage =
                L10n.text(
                    "no_playback_source",
                    languageCode:
                        appLanguage
                )
            return
        }

        isResolving = true
        defer {
            isResolving = false
        }

        do {
            playbackSource =
                try await StreamResolver
                    .resolveYouTubeVideo(
                        videoID: videoID,
                        preferredQuality:
                            preferredQuality
                    )
        } catch {
            errorMessage =
                error.localizedDescription
        }
    }
}

private struct PlaybackHistoryEntry {
    let videoID: String
    let title: String
    let channelTitle: String
    let channelID: String?

    var videoItem: VideoItem {
        VideoItem.youtube(
            videoID: videoID,
            title: title,
            channel: channelTitle,
            channelID: channelID
        )
    }
}

private enum PlaybackPositionStore {
    private static let prefix =
        "tubetv.playback.position."

    static func load(
        videoID: String
    ) -> Double? {
        let key = prefix + videoID

        guard UserDefaults.standard
                .object(forKey: key) != nil
        else {
            return nil
        }

        let value =
            UserDefaults.standard
                .double(forKey: key)

        return value > 0
            ? value
            : nil
    }

    static func save(
        videoID: String,
        position: Double,
        duration: Double?
    ) {
        let key = prefix + videoID

        guard position.isFinite,
              position >= 10
        else {
            UserDefaults.standard
                .removeObject(
                    forKey: key
                )
            return
        }

        if let duration,
           duration.isFinite,
           duration > 0,
           duration - position < 3 {
            UserDefaults.standard
                .removeObject(
                    forKey: key
                )
            return
        }

        UserDefaults.standard.set(
            position,
            forKey: key
        )
    }

    static func clear(
        videoID: String
    ) {
        UserDefaults.standard
            .removeObject(
                forKey:
                    prefix + videoID
            )
    }
}

@MainActor
private final class TubeTVPlayerEngine {
    static let shared = TubeTVPlayerEngine()

    let player: AVPlayer

    private init() {
        player = AVPlayer()

        // Prefer first-frame latency over building a large safety buffer.
        // TubeTV has its own buffering watchdog and client failover, so the
        // player can start aggressively and recover if the chosen source is
        // unhealthy.
        player.automaticallyWaitsToMinimizeStalling =
            false
    }
}

@MainActor
final class NativePlayerModel: ObservableObject {
    @Published private(set) var player: AVPlayer
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
    @Published private(set) var likeStatus: YouTubeLikeStatus?
    @Published private(set) var isUpdatingReaction = false
    @Published private(set) var playlistMemberships:
        [YouTubePlaylistMembership] = []
    @Published private(set) var isLoadingPlaylists = false
    @Published private(set) var updatingPlaylistID: String?
    @Published private(set) var isCreatingPlaylist = false
    @Published private(set) var suggestedVideos: [VideoItem] = []
    @Published private(set) var chapters: [YouTubeChapter] = []
    @Published private(set) var isSwitchingVideo = false
    @Published private(set) var currentVideoTitle: String
    @Published private(set) var currentChannelTitle: String
    @Published private(set) var currentChannelID: String?
    @Published private(set) var isSubscribed: Bool?
    @Published private(set) var isLoadingChannelState = false
    @Published private(set) var isUpdatingSubscription = false

    private var currentSource: PlaybackSource
    private var youtubeVideoID: String?
    private let preferredCaptionLanguage: String
    private let allowCaptionTranslation: Bool

    private var didPrepare = false
    private var cues: [CaptionCue] = []
    private var captionLoadGeneration = UUID()
    private var timeObserver: Any?
    private var trackingObserver: Any?
    private var localPositionObserver: Any?
    private var trackingContext: YouTubeTrackingContext?
    private var restoredPositionVideoID: String?
    private var ciSmokeVerificationScheduled = false
    private var failedClientProfiles = Set<String>()
    private var bufferWatchdogTask: Task<Void, Never>?
    private var playerItemFailureObserver: NSObjectProtocol?
    private var bufferWindowStartedAt: Date?
    private var accumulatedBufferingSeconds: TimeInterval = 0
    private var isRecoveringFromBuffering = false
    private var playbackHistory: [PlaybackHistoryEntry] = []
    private var remoteSeekDirection = 0
    private var remoteSeekIncrementSeconds = 10.0
    private var pendingRemoteSeekSeconds: Double?
    private var remoteSeekAccelerationStartedAt: Date?
    private var remoteSeekLastEventAt: Date?

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
        videoTitle: String = "",
        channelTitle: String = "",
        channelID: String? = nil,
        initialQuality: String,
        captionsEnabled: Bool,
        captionLanguage: String,
        allowCaptionTranslation: Bool
    ) {
        player = TubeTVPlayerEngine.shared.player
        currentSource = source
        self.youtubeVideoID = youtubeVideoID
        currentVideoTitle = videoTitle
        currentChannelTitle = channelTitle
        currentChannelID = channelID
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

                if let confirmedProfile =
                        source.clientProfile {
                    await AlternativePlayerService
                        .shared
                        .markPlaybackSuccessful(
                            profile:
                                confirmedProfile
                        )
                }

                currentSource = source
                activeClientProfile =
                    source.clientProfile
                isPreparing = false
                errorMessage = nil

                let live =
                    source.diagnosticIsLive
                        .map(String.init)
                    ?? "unknown"
                let ads =
                    source
                        .diagnosticAdvertisingMetadataDetected
                        .map(String.init)
                    ?? "unknown"
                let sourceKind =
                    source.diagnosticSourceKind
                let videoID =
                    youtubeVideoID
                    ?? "none"

                playbackLogger.notice(
                    "PLAYBACK_DIAG videoID=\(videoID, privacy: .public) live=\(live, privacy: .public) source=\(sourceKind, privacy: .public) profile=\(profile, privacy: .public) ads=\(ads, privacy: .public)"
                )

                playbackLogger.notice(
                    "READY profile=\(profile, privacy: .public)"
                )

                startBufferWatchdog()
                startCaptionLoadingIfNeeded()
                startHistoryTrackingIfNeeded()
                loadCaptionOptions()
                scheduleCISmokeVerificationIfNeeded()

                Task {
                    await loadLikeStatusIfNeeded()
                }

                Task {
                    await loadWatchNextMetadataIfNeeded()
                }

                Task {
                    await loadChannelStateIfNeeded()
                }

                return
            } catch {
                lastError = error
                player.pause()

                if let failedProfile =
                        source.clientProfile {
                    await AlternativePlayerService
                        .shared
                        .markPlaybackFailed(
                            profile:
                                failedProfile
                        )
                }

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

        if let playerItemFailureObserver {
            NotificationCenter.default
                .removeObserver(
                    playerItemFailureObserver
                )
            self.playerItemFailureObserver =
                nil
        }

        item.preferredForwardBufferDuration =
            2

        player.replaceCurrentItem(
            with: item
        )
        play()

        try await waitUntilReadyToPlay(
            item
        )

        installPlayerItemFailureObserver(
            for: item
        )

        await restorePlaybackPositionIfNeeded(
            source: source,
            item: item
        )
        installLocalPositionObserverIfNeeded()

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

    var isCurrentLive: Bool {
        currentSource.diagnosticIsLive == true
    }

    func goToLiveEdge() async {
        guard isCurrentLive,
              let item = player.currentItem,
              let rangeValue =
                item.seekableTimeRanges.last
        else {
            return
        }

        let range =
            rangeValue.timeRangeValue
        let liveEdge =
            CMTimeRangeGetEnd(range)
        let target =
            CMTimeSubtract(
                liveEdge,
                CMTime(
                    seconds: 15,
                    preferredTimescale: 600
                )
            )

        await seek(
            to:
                CMTimeCompare(
                    target,
                    range.start
                ) >= 0
                ? target
                : liveEdge
        )

        play()

        playbackLogger.notice(
            "Seeked to live edge"
        )
    }

    var supportsVideoReactions: Bool {
        youtubeVideoID != nil
    }

    var supportsPlaylistActions: Bool {
        youtubeVideoID != nil
    }

    var canPlayNextVideo: Bool {
        suggestedVideos
            .contains {
                $0.youtubeVideoID != nil
            }
    }

    var canPlayPreviousVideo: Bool {
        !playbackHistory.isEmpty
    }

    var nextVideoTitle: String? {
        suggestedVideos
            .first(
                where: {
                    $0.youtubeVideoID != nil
                }
            )?
            .title
    }

    var supportsChannelActions: Bool {
        guard let currentChannelID else {
            return false
        }

        return currentChannelID
            .hasPrefix("UC")
    }

    func playNextVideo() async {
        guard let next =
                suggestedVideos.first(
                    where: {
                        $0.youtubeVideoID != nil
                    }
                )
        else {
            return
        }

        await switchToVideo(
            next,
            rememberCurrent: true
        )
    }

    func playPreviousVideo() async {
        guard let previous =
                playbackHistory.popLast()
        else {
            return
        }

        await switchToVideo(
            previous.videoItem,
            rememberCurrent: false
        )
    }

    func toggleCurrentChannelSubscription()
        async {
        guard !isUpdatingSubscription,
              let channelID =
                currentChannelID,
              channelID.hasPrefix("UC"),
              let current =
                isSubscribed
        else {
            return
        }

        guard await SmartTubeAuthService
                .shared
                .signedIn()
        else {
            errorMessage =
                L10n.text(
                    "sign_in_hint"
                )
            return
        }

        isUpdatingSubscription = true
        errorMessage = nil
        defer {
            isUpdatingSubscription = false
        }

        do {
            let next = !current

            try await InnerTubeService.shared
                .setChannelSubscription(
                    channelID: channelID,
                    subscribed: next
                )

            isSubscribed = next
        } catch {
            errorMessage =
                error.localizedDescription
        }
    }

    private func loadChannelStateIfNeeded()
        async {
        guard let channelID =
                currentChannelID,
              channelID.hasPrefix("UC")
        else {
            isSubscribed = nil
            return
        }

        guard await SmartTubeAuthService
                .shared
                .signedIn()
        else {
            isSubscribed = nil
            return
        }

        isLoadingChannelState = true
        defer {
            isLoadingChannelState = false
        }

        do {
            let result =
                try await InnerTubeService.shared
                    .channelPage(
                        channelID
                    )

            guard currentChannelID
                    == channelID
            else {
                return
            }

            if currentChannelTitle.isEmpty
                || currentChannelTitle
                    == "YouTube" {
                currentChannelTitle =
                    result.page.title
            }

            isSubscribed =
                result.isSubscribed
        } catch {
            guard currentChannelID
                    == channelID
            else {
                return
            }

            isSubscribed = nil

            playbackLogger.notice(
                "Channel state load failed channel=\(channelID, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func loadWatchNextMetadataIfNeeded()
        async {
        guard let youtubeVideoID else {
            suggestedVideos = []
            chapters = []
            return
        }

        do {
            let metadata =
                try await InnerTubeService
                    .shared
                    .watchNextMetadata(
                        youtubeVideoID
                    )

            guard self.youtubeVideoID
                    == youtubeVideoID
            else {
                return
            }

            suggestedVideos =
                metadata.videos
            chapters =
                metadata.chapters

            playbackLogger.notice(
                "WatchNext metadata loaded video=\(youtubeVideoID, privacy: .public) suggestions=\(metadata.videos.count, privacy: .public) chapters=\(metadata.chapters.count, privacy: .public)"
            )
        } catch {
            guard self.youtubeVideoID
                    == youtubeVideoID
            else {
                return
            }

            suggestedVideos = []
            chapters = []

            playbackLogger.notice(
                "WatchNext metadata failed video=\(youtubeVideoID, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func jumpToChapter(
        _ chapter: YouTubeChapter
    ) async {
        guard !isPreparing,
              !isSwitchingVideo
        else {
            return
        }

        let target =
            CMTime(
                seconds:
                    Double(
                        chapter.startTimeMs
                    ) / 1_000,
                preferredTimescale: 600
            )

        await seek(to: target)
        play()

        playbackLogger.notice(
            "Chapter seek title=\(chapter.title, privacy: .public) startMs=\(chapter.startTimeMs, privacy: .public)"
        )
    }

    private func switchToVideo(
        _ video: VideoItem,
        rememberCurrent: Bool
    ) async {
        guard let videoID =
                video.youtubeVideoID,
              !videoID.isEmpty,
              videoID != youtubeVideoID,
              !isSwitchingVideo
        else {
            return
        }

        let previousEntry =
            youtubeVideoID.map {
                PlaybackHistoryEntry(
                    videoID: $0,
                    title:
                        currentVideoTitle,
                    channelTitle:
                        currentChannelTitle,
                    channelID:
                        currentChannelID
                )
            }

        isSwitchingVideo = true
        isPreparing = true
        errorMessage = nil

        sendHistoryProgress()
        saveLocalPlaybackPosition()
        player.pause()

        bufferWatchdogTask?.cancel()
        bufferWatchdogTask = nil
        bufferWindowStartedAt = nil
        accumulatedBufferingSeconds = 0

        captionLoadGeneration = UUID()
        cues.removeAll()
        currentCaption = ""
        captionStatus = nil
        activeCaptionLanguageCode = nil
        captionOptions = []

        trackingContext = nil
        likeStatus = nil
        playlistMemberships = []
        suggestedVideos = []
        chapters = []
        failedClientProfiles.removeAll()
        isSubscribed = nil
        isLoadingChannelState = false

        if rememberCurrent,
           let previousEntry,
           previousEntry.videoID
                != videoID {
            playbackHistory.append(
                previousEntry
            )

            if playbackHistory.count > 50 {
                playbackHistory.removeFirst(
                    playbackHistory.count - 50
                )
            }
        }

        youtubeVideoID = videoID
        currentVideoTitle = video.title
        currentChannelTitle =
            video.channel
        currentChannelID =
            video.channelID
        restoredPositionVideoID = nil

        do {
            let source =
                try await StreamResolver
                    .resolveYouTubeVideo(
                        videoID: videoID,
                        preferredQuality:
                            activeQuality
                    )

            await prepareWithFailover(
                startingFrom: source
            )
        } catch {
            isPreparing = false
            errorMessage =
                error.localizedDescription

            playbackLogger.error(
                "Video switch failed video=\(videoID, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
        }

        isSwitchingVideo = false
    }

    func loadPlaylistMemberships() async {
        guard let youtubeVideoID,
              !isLoadingPlaylists else {
            return
        }

        guard await SmartTubeAuthService.shared
            .signedIn() else {
            errorMessage =
                L10n.text(
                    "sign_in_hint"
                )
            playlistMemberships = []
            return
        }

        isLoadingPlaylists = true
        errorMessage = nil
        defer {
            isLoadingPlaylists = false
        }

        do {
            playlistMemberships =
                try await InnerTubeService.shared
                    .playlistMemberships(
                        for: youtubeVideoID
                    )
        } catch {
            playlistMemberships = []
            errorMessage =
                error.localizedDescription
        }
    }

    func createPlaylist(
        named name: String
    ) async -> Bool {
        guard let youtubeVideoID,
              !isCreatingPlaylist else {
            return false
        }

        let trimmed =
            name.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !trimmed.isEmpty else {
            return false
        }

        guard await SmartTubeAuthService.shared
            .signedIn() else {
            errorMessage =
                L10n.text(
                    "sign_in_hint"
                )
            return false
        }

        isCreatingPlaylist = true
        errorMessage = nil
        defer {
            isCreatingPlaylist = false
        }

        do {
            try await InnerTubeService.shared
                .createPlaylist(
                    named: trimmed,
                    adding: youtubeVideoID
                )

            await loadPlaylistMemberships()
            return true
        } catch {
            errorMessage =
                error.localizedDescription
            return false
        }
    }

    func togglePlaylistMembership(
        _ membership: YouTubePlaylistMembership
    ) async {
        guard let youtubeVideoID,
              updatingPlaylistID == nil else {
            return
        }

        guard await SmartTubeAuthService.shared
            .signedIn() else {
            errorMessage =
                L10n.text(
                    "sign_in_hint"
                )
            return
        }

        updatingPlaylistID = membership.id
        errorMessage = nil
        defer {
            updatingPlaylistID = nil
        }

        let shouldAdd =
            !membership.isSelected

        do {
            try await InnerTubeService.shared
                .setPlaylistMembership(
                    videoID: youtubeVideoID,
                    playlistID: membership.id,
                    add: shouldAdd
                )

            if let index =
                    playlistMemberships
                        .firstIndex(
                            where: {
                                $0.id
                                    == membership.id
                            }
                        ) {
                playlistMemberships[index] =
                    YouTubePlaylistMembership(
                        id: membership.id,
                        title: membership.title,
                        isSelected: shouldAdd
                    )
            }
        } catch {
            errorMessage =
                error.localizedDescription
        }
    }

    func toggleLike() async {
        await updateReaction(
            requested: .like
        )
    }

    func toggleDislike() async {
        await updateReaction(
            requested: .dislike
        )
    }

    private func loadLikeStatusIfNeeded() async {
        guard let youtubeVideoID else {
            likeStatus = nil
            return
        }

        guard await SmartTubeAuthService.shared
            .signedIn() else {
            likeStatus = .indifferent
            return
        }

        do {
            likeStatus =
                try await InnerTubeService.shared
                    .videoLikeStatus(
                        youtubeVideoID
                    )
        } catch {
            playbackLogger.error(
                "Like status load failed video=\(youtubeVideoID, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func updateReaction(
        requested: YouTubeLikeStatus
    ) async {
        guard let youtubeVideoID,
              !isUpdatingReaction else {
            return
        }

        guard await SmartTubeAuthService.shared
            .signedIn() else {
            errorMessage =
                L10n.text(
                    "sign_in_hint"
                )
            return
        }

        let current =
            likeStatus ?? .indifferent
        let target: YouTubeLikeStatus =
            current == requested
                ? .indifferent
                : requested

        isUpdatingReaction = true
        errorMessage = nil
        defer {
            isUpdatingReaction = false
        }

        do {
            try await InnerTubeService.shared
                .setVideoReaction(
                    videoID:
                        youtubeVideoID,
                    current: current,
                    target: target
                )

            likeStatus = target
        } catch {
            errorMessage =
                error.localizedDescription
        }
    }

    func pause() {
        sendHistoryProgress()
        saveLocalPlaybackPosition()
        player.pause()
    }

    func cleanup() {
        sendHistoryProgress()
        saveLocalPlaybackPosition()
        player.pause()

        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }

        if let trackingObserver {
            player.removeTimeObserver(trackingObserver)
            self.trackingObserver = nil
        }

        if let localPositionObserver {
            player.removeTimeObserver(
                localPositionObserver
            )
            self.localPositionObserver = nil
        }

        if let playerItemFailureObserver {
            NotificationCenter.default
                .removeObserver(
                    playerItemFailureObserver
                )
            self.playerItemFailureObserver =
                nil
        }

        // Cancel results from caption work belonging to the old video and
        // release the current AVPlayerItem immediately. Without this, several
        // consecutive full-screen players can keep media resources alive
        // until SwiftUI finally deallocates their models.
        captionLoadGeneration = UUID()
        cues.removeAll()
        currentCaption = ""
        trackingContext = nil

        bufferWatchdogTask?.cancel()
        bufferWatchdogTask = nil
        bufferWindowStartedAt = nil
        accumulatedBufferingSeconds = 0
        isRecoveringFromBuffering = false

        player.replaceCurrentItem(with: nil)
    }

    func play() {
        player.playImmediately(atRate: playbackRate)
    }

    private func installPlayerItemFailureObserver(
        for item: AVPlayerItem
    ) {
        if let playerItemFailureObserver {
            NotificationCenter.default
                .removeObserver(
                    playerItemFailureObserver
                )
        }

        playerItemFailureObserver =
            NotificationCenter.default
                .addObserver(
                    forName:
                        .AVPlayerItemFailedToPlayToEndTime,
                    object: item,
                    queue: .main
                ) { [weak self, weak item]
                    notification in
                    guard let self else {
                        return
                    }

                    let notificationError =
                        notification.userInfo?[
                            AVPlayerItemFailedToPlayToEndTimeErrorKey
                        ] as? Error
                    let error =
                        notificationError
                        ?? item?.error
                        ?? StreamResolverError
                            .noPlayableStream

                    Task { @MainActor [weak self] in
                        await self?
                            .recoverFromRuntimePlaybackFailure(
                                error
                            )
                    }
                }
    }

    private func recoverFromRuntimePlaybackFailure(
        _ error: Error
    ) async {
        guard !isPreparing,
              !isSwitchingQuality,
              !isSwitchingAudio,
              !isSwitchingVideo,
              !isRecoveringFromBuffering
        else {
            return
        }

        playbackLogger.error(
            "Runtime playback failure profile=\(self.activeClientProfile ?? "UNTAGGED", privacy: .public) error=\(error.localizedDescription, privacy: .public)"
        )

        await recoverPlayback(
            reason:
                "runtime-error: \(error.localizedDescription)"
        )
    }

    private func startBufferWatchdog() {
        bufferWatchdogTask?.cancel()
        bufferWindowStartedAt = Date()
        accumulatedBufferingSeconds = 0

        bufferWatchdogTask =
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                var lastSample = Date()

                while !Task.isCancelled {
                    try? await Task.sleep(
                        nanoseconds:
                            500_000_000
                    )

                    guard !Task.isCancelled else {
                        break
                    }

                    let now = Date()
                    let elapsed =
                        min(
                            1.0,
                            max(
                                0,
                                now.timeIntervalSince(
                                    lastSample
                                )
                            )
                        )
                    lastSample = now

                    if let windowStart =
                            self
                                .bufferWindowStartedAt,
                       now.timeIntervalSince(
                            windowStart
                       ) >= 60 {
                        self
                            .bufferWindowStartedAt =
                            now
                        self
                            .accumulatedBufferingSeconds =
                            0
                    }

                    guard !self.isPreparing,
                          !self
                            .isSwitchingQuality,
                          !self
                            .isSwitchingAudio,
                          !self
                            .isRecoveringFromBuffering,
                          self.player
                            .currentItem != nil
                    else {
                        continue
                    }

                    guard self.player
                            .timeControlStatus
                            == .waitingToPlayAtSpecifiedRate
                    else {
                        continue
                    }

                    self
                        .accumulatedBufferingSeconds +=
                        elapsed

                    guard self
                            .accumulatedBufferingSeconds
                            >= 20
                    else {
                        continue
                    }

                    self
                        .accumulatedBufferingSeconds =
                        0
                    self
                        .bufferWindowStartedAt =
                        now

                    self.playbackLogger.warning(
                        "Long buffering detected profile=\(self.activeClientProfile ?? "UNTAGGED", privacy: .public)"
                    )

                    Task { @MainActor [weak self] in
                        await self?
                            .recoverFromLongBuffering()
                    }
                }
            }
    }

    private func recoverFromLongBuffering()
        async {
        await recoverPlayback(
            reason: "long-buffering"
        )
    }

    private func recoverPlayback(
        reason: String
    ) async {
        guard !isRecoveringFromBuffering,
              let youtubeVideoID
        else {
            return
        }

        isRecoveringFromBuffering = true
        isPreparing = true
        errorMessage = nil

        let savedTime =
            player.currentTime()
        let savedSeconds =
            savedTime.seconds
        let failedProfile =
            currentSource.clientProfile

        player.pause()
        sendHistoryProgress()

        if let failedProfile {
            failedClientProfiles.insert(
                failedProfile
            )

            await AlternativePlayerService
                .shared
                .markPlaybackFailed(
                    profile: failedProfile
                )
        }

        playbackLogger.warning(
            "Playback recovery start reason=\(reason, privacy: .public) video=\(youtubeVideoID, privacy: .public) failedProfile=\(failedProfile ?? "UNTAGGED", privacy: .public) position=\(savedSeconds, privacy: .public)"
        )

        // First try a muxed/direct fallback from the same player response.
        // This mirrors SmartTube's preference to change the usable format
        // before walking the remaining player clients.
        if let localFallback =
                fallbackSource(
                    from: currentSource
                ) {
            do {
                try await activateAndVerify(
                    localFallback
                )

                currentSource =
                    localFallback
                activeClientProfile =
                    localFallback
                        .clientProfile

                if localFallback
                        .diagnosticIsLive
                        == true {
                    await goToLiveEdge()
                } else if savedSeconds.isFinite,
                          savedSeconds > 0 {
                    await seek(
                        to: savedTime
                    )
                }

                isPreparing = false
                isRecoveringFromBuffering =
                    false
                startBufferWatchdog()
                play()

                playbackLogger.notice(
                    "Playback recovery succeeded with local fallback reason=\(reason, privacy: .public)"
                )
                return
            } catch {
                playbackLogger.warning(
                    "Local buffer fallback failed error=\(error.localizedDescription, privacy: .public)"
                )
            }
        }

        do {
            let resolved =
                try await StreamResolver
                    .resolveYouTubeVideo(
                        videoID:
                            youtubeVideoID,
                        preferredQuality:
                            activeQuality,
                        excludingProfiles:
                            failedClientProfiles
                    )

            let nextSource =
                activeAudioTrackID
                    .flatMap {
                        resolved
                            .replacingAudioTrack(
                                id: $0
                            )
                    }
                ?? resolved

            await prepareWithFailover(
                startingFrom:
                    nextSource
            )

            if errorMessage == nil {
                if currentSource
                    .diagnosticIsLive
                    == true {
                    await goToLiveEdge()
                } else if savedSeconds.isFinite,
                          savedSeconds > 0 {
                    await seek(
                        to: savedTime
                    )
                    play()
                }
            }

            playbackLogger.notice(
                "Playback recovery finished reason=\(reason, privacy: .public) profile=\(self.activeClientProfile ?? "UNTAGGED", privacy: .public)"
            )
        } catch {
            isPreparing = false
            errorMessage =
                error.localizedDescription

            playbackLogger.error(
                "Playback recovery failed reason=\(reason, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
        }

        isRecoveringFromBuffering =
            false
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

    func remoteSeekDelta(
        forward: Bool
    ) -> Double {
        let now = Date()
        let direction = forward ? 1 : -1
        let didRelease =
            remoteSeekLastEventAt.map {
                now.timeIntervalSince($0) > 0.5
            } ?? true

        if remoteSeekDirection != direction
            || didRelease {
            remoteSeekDirection = direction
            remoteSeekIncrementSeconds = 10
            remoteSeekAccelerationStartedAt =
                now
        } else if let startedAt =
                    remoteSeekAccelerationStartedAt,
                  now.timeIntervalSince(
                    startedAt
                  ) >= 1 {
            remoteSeekIncrementSeconds *= 1.5
            remoteSeekAccelerationStartedAt =
                now
        }

        remoteSeekLastEventAt = now

        return Double(direction)
            * remoteSeekIncrementSeconds
    }

    func seekFromRemote(
        seconds delta: Double
    ) async {
        guard !isPreparing,
              !isSwitchingQuality,
              !isSwitchingAudio,
              let item = player.currentItem else {
            return
        }

        let currentSeconds =
            player.currentTime().seconds

        guard currentSeconds.isFinite else {
            return
        }

        let baseSeconds =
            pendingRemoteSeekSeconds
            ?? currentSeconds

        var targetSeconds =
            max(
                0,
                baseSeconds + delta
            )

        let durationSeconds =
            item.duration.seconds

        if durationSeconds.isFinite,
           durationSeconds > 0 {
            targetSeconds =
                min(
                    targetSeconds,
                    max(
                        0,
                        durationSeconds - 0.25
                    )
                )
        }

        pendingRemoteSeekSeconds =
            targetSeconds

        let wasPlaying =
            player.rate > 0
            || player.timeControlStatus
                == .playing
            || player.timeControlStatus
                == .waitingToPlayAtSpecifiedRate

        let target = CMTime(
            seconds: targetSeconds,
            preferredTimescale: 600
        )

        await seek(
            to: target,
            toleranceSeconds: 2
        )

        pendingRemoteSeekSeconds = nil

        if wasPlaying {
            player.playImmediately(
                atRate: playbackRate
            )
        }

        playbackLogger.notice(
            "Remote seek delta=\(delta, privacy: .public) from=\(currentSeconds, privacy: .public) to=\(targetSeconds, privacy: .public) resume=\(wasPlaying, privacy: .public)"
        )
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

            if newSource
                    .diagnosticIsLive
                    == true {
                await goToLiveEdge()
            } else if savedSeconds.isFinite,
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

            if newSource
                    .diagnosticIsLive
                    == true {
                await goToLiveEdge()
            } else if savedSeconds.isFinite,
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
        captionLoadGeneration = UUID()
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
        let generation = UUID()
        captionLoadGeneration = generation

        Task {
            await loadCaptions(
                videoID: youtubeVideoID,
                languageCode: preferredCaptionLanguage,
                preferTranslation: false,
                preferredAutoGenerated: nil,
                generation: generation
            )
        }
    }

    func selectCaption(_ option: CaptionLanguageOption) {
        guard let youtubeVideoID else { return }

        captionsAreEnabled = true
        captionStatus = L10n.text("loading_captions")
        let generation = UUID()
        captionLoadGeneration = generation

        Task {
            await loadCaptions(
                videoID: youtubeVideoID,
                languageCode: option.languageCode,
                preferTranslation: !option.isNative,
                preferredAutoGenerated:
                    option.isNative
                        ? option.isAutoGenerated
                        : nil,
                generation: generation
            )
        }
    }

    private func loadCaptions(
        videoID: String,
        languageCode: String,
        preferTranslation: Bool,
        preferredAutoGenerated: Bool?,
        generation: UUID
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

            guard generation == captionLoadGeneration else {
                return
            }

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
            guard generation == captionLoadGeneration else {
                return
            }

            cues = []
            currentCaption = ""
            activeCaptionLanguageCode = nil
            captionStatus = error.localizedDescription
        }
    }

    private func installLocalPositionObserverIfNeeded() {
        guard localPositionObserver == nil else {
            return
        }

        let interval =
            CMTime(
                seconds: 15,
                preferredTimescale: 600
            )

        localPositionObserver =
            player.addPeriodicTimeObserver(
                forInterval: interval,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?
                        .saveLocalPlaybackPosition()
                }
            }
    }

    private func saveLocalPlaybackPosition() {
        guard let videoID =
                youtubeVideoID,
              currentSource
                .diagnosticIsLive != true
        else {
            return
        }

        let position =
            player.currentTime()
                .seconds
        let duration =
            player.currentItem?
                .duration.seconds

        PlaybackPositionStore.save(
            videoID: videoID,
            position: position,
            duration: duration
        )

        if position.isFinite {
            playbackLogger.notice(
                "Saved local position video=\(videoID, privacy: .public) position=\(position, privacy: .public)"
            )
        }
    }

    private func restorePlaybackPositionIfNeeded(
        source: PlaybackSource,
        item: AVPlayerItem
    ) async {
        guard let videoID =
                youtubeVideoID,
              restoredPositionVideoID
                != videoID,
              source.diagnosticIsLive
                != true
        else {
            return
        }

        restoredPositionVideoID =
            videoID

        guard let saved =
                PlaybackPositionStore
                    .load(
                        videoID:
                            videoID
                    ),
              saved >= 10
        else {
            return
        }

        let duration =
            item.duration.seconds

        if duration.isFinite,
           duration > 0,
           duration - saved < 3 {
            PlaybackPositionStore.clear(
                videoID: videoID
            )
            return
        }

        let targetSeconds =
            duration.isFinite
                && duration > 0
            ? min(
                saved,
                max(
                    0,
                    duration - 3
                )
            )
            : saved

        guard targetSeconds >= 10 else {
            return
        }

        let target =
            CMTime(
                seconds:
                    targetSeconds,
                preferredTimescale:
                    600
            )

        await seek(to: target)

        playbackLogger.notice(
            "Restored local position video=\(videoID, privacy: .public) position=\(targetSeconds, privacy: .public)"
        )
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
        let generation = UUID()
        captionLoadGeneration = generation

        Task {
            await loadCaptions(
                videoID: youtubeVideoID,
                languageCode: preferredCaptionLanguage,
                preferTranslation: false,
                preferredAutoGenerated: nil,
                generation: generation
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

    private func seek(
        to time: CMTime,
        toleranceSeconds: Double = 0.5
    ) async {
        let tolerance =
            CMTime(
                seconds:
                    max(
                        0,
                        toleranceSeconds
                    ),
                preferredTimescale: 600
            )

        // Rapid remote presses may otherwise queue multiple exact seeks.
        // Keep only the newest target and allow AVPlayer to land on a nearby
        // keyframe instead of waiting for an exact, not-yet-buffered sample.
        player.currentItem?
            .cancelPendingSeeks()

        await withCheckedContinuation { continuation in
            player.seek(
                to: time,
                toleranceBefore:
                    tolerance,
                toleranceAfter:
                    tolerance
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
    case playlists
    case chapters
}

private enum PlayerControlFocus: Hashable {
    case settings
}

private enum PlayerSettingsFocus: Hashable {
    case quality
}

struct NativePlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var appLanguage =
        AppLanguage.english.rawValue
    @StateObject private var model: NativePlayerModel

    @State private var showSettings = false
    @State private var settingsPage: PlayerSettingsPage = .root
    @FocusState private var playerControlFocus: PlayerControlFocus?

    init(
        source: PlaybackSource,
        youtubeVideoID: String?,
        videoTitle: String = "",
        channelTitle: String = "",
        channelID: String? = nil,
        initialQuality: String,
        captionsEnabled: Bool,
        captionLanguage: String,
        allowCaptionTranslation: Bool
    ) {
        _model = StateObject(
            wrappedValue: NativePlayerModel(
                source: source,
                youtubeVideoID: youtubeVideoID,
                videoTitle: videoTitle,
                channelTitle: channelTitle,
                channelID: channelID,
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

            if model.isPreparing
                || model.isSwitchingQuality
                || model.isSwitchingVideo {
                ProgressView(
                    model.isSwitchingQuality
                        ? L10n.text("switching_quality", languageCode: appLanguage)
                        : L10n.text("preparing_video", languageCode: appLanguage)
                )
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
        .onMoveCommand { direction in
            guard !showSettings else {
                return
            }

            switch direction {
            case .up:
                // VideoPlayer keeps tvOS focus, so the floating gear cannot
                // reliably be reached by the focus engine. Match TV-player
                // behaviour and make Up the direct path into settings.
                settingsPage = .root
                showSettings = true
                playerControlFocus = nil

            case .down:
                playerControlFocus = nil

            case .left:
                playerControlFocus = nil
                let delta =
                    model.remoteSeekDelta(
                        forward: false
                    )
                Task {
                    await model.seekFromRemote(
                        seconds: delta
                    )
                }

            case .right:
                playerControlFocus = nil
                let delta =
                    model.remoteSeekDelta(
                        forward: true
                    )
                Task {
                    await model.seekFromRemote(
                        seconds: delta
                    )
                }

            default:
                break
            }
        }
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
    @State private var newPlaylistName = ""
    @FocusState private var settingsFocus: PlayerSettingsFocus?

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
                case .playlists:
                    playlistsPage
                case .chapters:
                    chaptersPage
                }

                Spacer()
            }
            .padding(30)
            .frame(width: 620)
            .frame(maxHeight: .infinity)
            .background(.ultraThinMaterial)
        }
        .ignoresSafeArea()
        .task {
            await Task.yield()
            if page == .root {
                settingsFocus = .quality
            }
        }
        .onChange(of: page) { _, newPage in
            if newPage == .root {
                Task {
                    await Task.yield()
                    settingsFocus = .quality
                }
            } else {
                settingsFocus = nil
            }
        }
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
        case .playlists:
            return L10n.text(
                "save_to_playlist",
                languageCode: appLanguage
            )
        case .chapters:
            return L10n.text(
                "chapters",
                languageCode:
                    appLanguage
            )
        }
    }

    private var rootPage: some View {
        VStack(spacing: 14) {
            if model.canPlayPreviousVideo
                || model.canPlayNextVideo {
                HStack(spacing: 14) {
                    Button {
                        Task {
                            await model
                                .playPreviousVideo()
                        }
                    } label: {
                        Label(
                            L10n.text(
                                "previous_video",
                                languageCode:
                                    appLanguage
                            ),
                            systemImage:
                                "backward.end.fill"
                        )
                        .frame(
                            maxWidth:
                                .infinity
                        )
                    }
                    .disabled(
                        !model
                            .canPlayPreviousVideo
                    )

                    Button {
                        Task {
                            await model
                                .playNextVideo()
                        }
                    } label: {
                        VStack(
                            alignment:
                                .leading,
                            spacing: 3
                        ) {
                            Label(
                                L10n.text(
                                    "next_video",
                                    languageCode:
                                        appLanguage
                                ),
                                systemImage:
                                    "forward.end.fill"
                            )

                            if let title =
                                    model
                                        .nextVideoTitle {
                                Text(title)
                                    .font(
                                        .caption
                                    )
                                    .foregroundStyle(
                                        .secondary
                                    )
                                    .lineLimit(1)
                            }
                        }
                        .frame(
                            maxWidth:
                                .infinity,
                            alignment:
                                .leading
                        )
                    }
                    .disabled(
                        !model
                            .canPlayNextVideo
                    )
                }
            }

            if model.isCurrentLive {
                Button {
                    Task {
                        await model.goToLiveEdge()
                    }
                } label: {
                    HStack(spacing: 14) {
                        Image(
                            systemName:
                                "dot.radiowaves.left.and.right"
                        )

                        VStack(
                            alignment:
                                .leading,
                            spacing: 3
                        ) {
                            Text(
                                L10n.text(
                                    "go_live",
                                    languageCode:
                                        appLanguage
                                )
                            )
                            .font(.headline)

                            Text(
                                L10n.text(
                                    "go_live_hint",
                                    languageCode:
                                        appLanguage
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(
                                .secondary
                            )
                        }

                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
            }

            if model.supportsChannelActions,
               let channelID =
                    model.currentChannelID {
                HStack(spacing: 14) {
                    NavigationLink {
                        ChannelView(
                            channelID:
                                channelID,
                            fallbackTitle:
                                model
                                    .currentChannelTitle
                        )
                    } label: {
                        Label(
                            model
                                .currentChannelTitle
                                .isEmpty
                            ? L10n.text(
                                "channels",
                                languageCode:
                                    appLanguage
                              )
                            : model
                                .currentChannelTitle,
                            systemImage:
                                "person.crop.rectangle"
                        )
                        .lineLimit(1)
                        .frame(
                            maxWidth:
                                .infinity,
                            alignment:
                                .leading
                        )
                    }

                    if let isSubscribed =
                            model
                                .isSubscribed {
                        Button {
                            Task {
                                await model
                                    .toggleCurrentChannelSubscription()
                            }
                        } label: {
                            Label(
                                L10n.text(
                                    isSubscribed
                                    ? "unsubscribe_channel"
                                    : "subscribe_channel",
                                    languageCode:
                                        appLanguage
                                ),
                                systemImage:
                                    isSubscribed
                                    ? "checkmark.circle.fill"
                                    : "plus.circle.fill"
                            )
                            .frame(
                                maxWidth:
                                    .infinity
                            )
                        }
                        .disabled(
                            model
                                .isUpdatingSubscription
                        )
                    } else if model
                                .isLoadingChannelState {
                        ProgressView()
                            .frame(
                                maxWidth:
                                    .infinity
                            )
                    }
                }
            }

            if model.supportsVideoReactions {
                HStack(spacing: 14) {
                    reactionButton(
                        title: L10n.text(
                            "like",
                            languageCode:
                                appLanguage
                        ),
                        icon:
                            model.likeStatus == .like
                                ? "hand.thumbsup.fill"
                                : "hand.thumbsup",
                        selected:
                            model.likeStatus == .like
                    ) {
                        Task {
                            await model.toggleLike()
                        }
                    }

                    reactionButton(
                        title: L10n.text(
                            "dislike",
                            languageCode:
                                appLanguage
                        ),
                        icon:
                            model.likeStatus == .dislike
                                ? "hand.thumbsdown.fill"
                                : "hand.thumbsdown",
                        selected:
                            model.likeStatus == .dislike
                    ) {
                        Task {
                            await model.toggleDislike()
                        }
                    }
                }
            }

            if !model.chapters.isEmpty {
                settingsButton(
                    title: L10n.text(
                        "chapters",
                        languageCode:
                            appLanguage
                    ),
                    value:
                        "\(model.chapters.count)",
                    icon:
                        "list.bullet.rectangle"
                ) {
                    page = .chapters
                }
            }

            settingsButton(
                title: L10n.text("quality", languageCode: appLanguage),
                value: model.currentPlaybackDescription,
                icon: "4k.tv"
            ) {
                page = .quality
            }
            .focused(
                $settingsFocus,
                equals: .quality
            )

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

            if model.supportsPlaylistActions {
                settingsButton(
                    title: L10n.text(
                        "save_to_playlist",
                        languageCode:
                            appLanguage
                    ),
                    value: L10n.text(
                        "manage_playlists",
                        languageCode:
                            appLanguage
                    ),
                    icon: "text.badge.plus"
                ) {
                    page = .playlists

                    Task {
                        await model
                            .loadPlaylistMemberships()
                    }
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

    private var chaptersPage: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(model.chapters) {
                    chapter in
                    Button {
                        Task {
                            await model
                                .jumpToChapter(
                                    chapter
                                )
                            page = .root
                        }
                    } label: {
                        HStack(spacing: 14) {
                            if let thumbnailURL =
                                    chapter
                                        .thumbnailURL {
                                AsyncImage(
                                    url:
                                        thumbnailURL
                                ) { phase in
                                    switch phase {
                                    case .success(
                                        let image
                                    ):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    default:
                                        Rectangle()
                                            .fill(
                                                .white
                                                    .opacity(
                                                        0.08
                                                    )
                                            )
                                    }
                                }
                                .frame(
                                    width: 112,
                                    height: 63
                                )
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius:
                                            8
                                    )
                                )
                            }

                            VStack(
                                alignment:
                                    .leading,
                                spacing: 4
                            ) {
                                Text(
                                    chapter.title
                                )
                                .font(.headline)
                                .lineLimit(2)

                                Text(
                                    chapterTime(
                                        chapter
                                            .startTimeMs
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    .secondary
                                )
                            }

                            Spacer()
                        }
                        .padding(
                            .vertical,
                            6
                        )
                    }
                }
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

    private var playlistsPage: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    TextField(
                        L10n.text(
                            "new_playlist_name",
                            languageCode:
                                appLanguage
                        ),
                        text: $newPlaylistName
                    )

                    Button {
                        let name =
                            newPlaylistName

                        Task {
                            if await model
                                .createPlaylist(
                                    named: name
                                ) {
                                newPlaylistName = ""
                            }
                        }
                    } label: {
                        if model.isCreatingPlaylist {
                            ProgressView()
                        } else {
                            Label(
                                L10n.text(
                                    "create_playlist",
                                    languageCode:
                                        appLanguage
                                ),
                                systemImage:
                                    "plus"
                            )
                        }
                    }
                    .disabled(
                        newPlaylistName
                            .trimmingCharacters(
                                in:
                                    .whitespacesAndNewlines
                            )
                            .isEmpty
                        || model.isCreatingPlaylist
                    )
                }
                .padding(.bottom, 8)

                if model.isLoadingPlaylists {
                    ProgressView(
                        L10n.text(
                            "loading_playlists",
                            languageCode:
                                appLanguage
                        )
                    )
                    .padding(.vertical, 18)
                } else if model
                    .playlistMemberships
                    .isEmpty {
                    Text(
                        L10n.text(
                            "youtube_no_playlists",
                            languageCode:
                                appLanguage
                        )
                    )
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 18)
                } else {
                    ForEach(
                        model.playlistMemberships
                    ) { playlist in
                        Button {
                            Task {
                                await model
                                    .togglePlaylistMembership(
                                        playlist
                                    )
                            }
                        } label: {
                            optionRow(
                                playlist.title,
                                selected:
                                    playlist
                                        .isSelected
                            )
                        }
                        .disabled(
                            model.updatingPlaylistID
                                != nil
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

    private func reactionButton(
        title: String,
        icon: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)

                Text(title)
                    .font(.headline)

                if selected {
                    Image(
                        systemName:
                            "checkmark"
                    )
                }
            }
            .frame(
                maxWidth: .infinity
            )
            .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .disabled(
            model.isUpdatingReaction
        )
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

    private func chapterTime(
        _ milliseconds: Int64
    ) -> String {
        let totalSeconds =
            max(
                0,
                milliseconds / 1_000
            )
        let hours =
            totalSeconds / 3_600
        let minutes =
            (totalSeconds % 3_600)
                / 60
        let seconds =
            totalSeconds % 60

        if hours > 0 {
            return String(
                format:
                    "%lld:%02lld:%02lld",
                hours,
                minutes,
                seconds
            )
        }

        return String(
            format:
                "%lld:%02lld",
            minutes,
            seconds
        )
    }

    private func rateLabel(_ rate: Float) -> String {
        if abs(rate - 1.0) < 0.001 {
            return L10n.text("normal_speed", languageCode: appLanguage)
        }

        return String(format: "%.2gx", rate)
    }
}
