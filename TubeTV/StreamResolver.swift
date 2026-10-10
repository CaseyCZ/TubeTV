import Foundation
import YouTubeKit

struct PlaybackAudioTrack: Hashable {
    let id: String
    let displayName: String
    let languageCode: String
    let isDefault: Bool
    let isOriginal: Bool
    let isAutoDubbed: Bool
    let url: URL
}

struct PlaybackRequestHeaders: Hashable {
    let userAgent: String
    let referer: String?
    let origin: String?
    let clientProfile: String?
    let availableHeights: [Int]
    let audioTracks: [PlaybackAudioTrack]
    let isLive: Bool
    let isLiveContent: Bool
    let advertisingMetadataDetected: Bool

    init(
        userAgent: String,
        referer: String? = nil,
        origin: String? = nil,
        clientProfile: String? = nil,
        availableHeights: [Int] = [],
        audioTracks: [PlaybackAudioTrack] = [],
        isLive: Bool = false,
        isLiveContent: Bool = false,
        advertisingMetadataDetected: Bool = false
    ) {
        self.userAgent = userAgent
        self.referer = referer
        self.origin = origin
        self.clientProfile = clientProfile
        self.availableHeights = Array(
            Set(availableHeights.filter { $0 > 0 })
        ).sorted(by: >)
        self.audioTracks = audioTracks
        self.isLive = isLive
        self.isLiveContent = isLiveContent
        self.advertisingMetadataDetected =
            advertisingMetadataDetected
    }

    var dictionary: [String: String] {
        var result = ["User-Agent": userAgent]

        if let referer, !referer.isEmpty {
            result["Referer"] = referer
        }

        if let origin, !origin.isEmpty {
            result["Origin"] = origin
        }

        return result
    }
}

enum PlaybackSource: Hashable {
    case direct(URL)
    case directWithHeaders(URL, PlaybackRequestHeaders)
    case adaptive(video: URL, audio: URL, fallback: URL?)
    case adaptiveWithHeaders(
        video: URL,
        audio: URL,
        fallback: URL?,
        headers: PlaybackRequestHeaders
    )

    var clientProfile: String? {
        switch self {
        case .directWithHeaders(_, let headers),
             .adaptiveWithHeaders(_, _, _, let headers):
            return headers.clientProfile

        case .direct, .adaptive:
            return nil
        }
    }

    var diagnosticSourceKind: String {
        switch self {
        case .direct(let url),
             .directWithHeaders(
                let url,
                _
             ):
            let raw =
                url.absoluteString
                    .lowercased()

            if url.pathExtension
                    .lowercased()
                    == "m3u8"
                || raw.contains(
                    "hls_playlist"
                )
                || raw.contains(
                    "/manifest/"
                ) {
                return "HLS"
            }

            return "DIRECT"

        case .adaptive,
             .adaptiveWithHeaders:
            return "ADAPTIVE"
        }
    }

    var diagnosticIsLive: Bool? {
        switch self {
        case .directWithHeaders(
            _,
            let headers
        ),
        .adaptiveWithHeaders(
            _,
            _,
            _,
            let headers
        ):
            return headers.isLive

        case .direct,
             .adaptive:
            return nil
        }
    }

    var diagnosticIsLiveContent: Bool? {
        switch self {
        case .directWithHeaders(
            _,
            let headers
        ),
        .adaptiveWithHeaders(
            _,
            _,
            _,
            let headers
        ):
            return headers.isLiveContent

        case .direct,
             .adaptive:
            return nil
        }
    }

    var diagnosticAdvertisingMetadataDetected: Bool? {
        switch self {
        case .directWithHeaders(
            _,
            let headers
        ),
        .adaptiveWithHeaders(
            _,
            _,
            _,
            let headers
        ):
            return headers
                .advertisingMetadataDetected

        case .direct,
             .adaptive:
            return nil
        }
    }

    var availableQualityHeights: [Int] {
        switch self {
        case .directWithHeaders(_, let headers),
             .adaptiveWithHeaders(_, _, _, let headers):
            return headers.availableHeights

        case .direct, .adaptive:
            return []
        }
    }

    var availableAudioTracks: [PlaybackAudioTrack] {
        switch self {
        case .directWithHeaders(_, let headers),
             .adaptiveWithHeaders(_, _, _, let headers):
            return headers.audioTracks

        case .direct, .adaptive:
            return []
        }
    }

    var activeAudioTrackID: String? {
        switch self {
        case .adaptiveWithHeaders(
            _,
            let audioURL,
            _,
            let headers
        ):
            return headers.audioTracks
                .first(where: {
                    $0.url == audioURL
                })?
                .id

        case .direct,
             .directWithHeaders,
             .adaptive:
            return nil
        }
    }

    func replacingAudioTrack(
        id: String
    ) -> PlaybackSource? {
        guard let track =
                availableAudioTracks
                    .first(where: {
                        $0.id == id
                    }) else {
            return nil
        }

        switch self {
        case .adaptiveWithHeaders(
            let videoURL,
            _,
            let fallback,
            let headers
        ):
            return .adaptiveWithHeaders(
                video: videoURL,
                audio: track.url,
                fallback: fallback,
                headers: headers
            )

        case .direct,
             .directWithHeaders,
             .adaptive:
            return nil
        }
    }
}

enum StreamResolverError: LocalizedError {
    case invalidVideoID
    case noPlayableStream
    case ipBlocked(String)
    case signInRequired

    var errorDescription: String? {
        switch self {
        case .invalidVideoID:
            return L10n.text("invalid_video_id")
        case .noPlayableStream:
            return L10n.text("no_playable_stream")
        case .ipBlocked:
            return L10n.text("youtube_network_blocked")
        case .signInRequired:
            return L10n.text("youtube_sign_in_required")
        }
    }

    static func playabilityError(
        status: String,
        reason: String
    ) -> StreamResolverError? {
        let lowerReason = reason.lowercased()

        // Match SmartTubeIOS IPBlockDetectionTests. This must run
        // before generic LOGIN_REQUIRED handling because YouTube uses
        // LOGIN_REQUIRED for "Sign in to confirm you're not a bot".
        let ipBlockKeywords = [
            "your ip",
            "ip address",
            "vpn",
            "proxy",
            "bot",
            "sign in to confirm"
        ]

        if ipBlockKeywords.contains(
            where: { lowerReason.contains($0) }
        ) {
            return .ipBlocked(reason)
        }

        let signInStatuses: Set<String> = [
            "LOGIN_REQUIRED",
            "AGE_VERIFICATION_REQUIRED",
            "AGE_CHECK_REQUIRED"
        ]

        let signInKeywords = [
            "sign in",
            "age-restricted",
            "age restricted",
            "18+",
            "age verification"
        ]

        if signInStatuses.contains(status)
            || signInKeywords.contains(
                where: { lowerReason.contains($0) }
            ) {
            return .signInRequired
        }

        return nil
    }
}

private enum PlaybackProfilePreferenceStore {
    private static let key =
        "tubetv.playback.lastWorkingProfile"

    static func load() -> String? {
        guard let value =
                UserDefaults.standard
                    .string(forKey: key),
              !value.isEmpty else {
            return nil
        }

        return value
    }

    static func save(_ profile: String) {
        guard !profile.isEmpty,
              profile != "TV_AUTH" else {
            return
        }

        UserDefaults.standard.set(
            profile,
            forKey: key
        )
    }

    static func clear() {
        UserDefaults.standard
            .removeObject(forKey: key)
    }
}

private actor StreamResolutionBudget {
    static let shared = StreamResolutionBudget()

    private struct Window {
        let startedAt: Date
        var attempts: Int
    }

    private var windows: [String: Window] = [:]
    private let maximumWindow: TimeInterval = 32
    private let maximumAttempts = 4
    private let staleWindowAge: TimeInterval = 120

    func beginAttempt(
        videoID: String,
        reset: Bool
    ) -> Bool {
        let now = Date()

        windows = windows.filter {
            now.timeIntervalSince(
                $0.value.startedAt
            ) < staleWindowAge
        }

        if reset || windows[videoID] == nil {
            windows[videoID] = Window(
                startedAt: now,
                attempts: 1
            )
            return true
        }

        guard var window = windows[videoID],
              now.timeIntervalSince(
                window.startedAt
              ) < maximumWindow,
              window.attempts < maximumAttempts else {
            return false
        }

        window.attempts += 1
        windows[videoID] = window
        return true
    }
}

enum StreamResolver {
    static func resolveYouTubeVideo(
        videoID: String,
        preferredQuality: String = "Auto",
        excludingProfiles: Set<String> = []
    ) async throws -> PlaybackSource {
        guard !videoID.isEmpty else {
            throw StreamResolverError.invalidVideoID
        }

        let isInitialAttempt = excludingProfiles.isEmpty
        let storedProfile =
            PlaybackProfilePreferenceStore.load()

        if let storedProfile,
           excludingProfiles.contains(
            storedProfile
           ) {
            PlaybackProfilePreferenceStore.clear()
        } else if isInitialAttempt,
                  let storedProfile {
            // Rehydrate AlternativePlayerService's in-memory preference after
            // an app restart. If this profile fails AVPlayer verification,
            // PlayerView will exclude it on the next resolver pass and the
            // persisted preference is cleared above.
            await AlternativePlayerService.shared
                .markPlaybackSuccessful(
                    profile: storedProfile
                )
        }

        let allowed =
            await StreamResolutionBudget.shared.beginAttempt(
                videoID: videoID,
                reset: isInitialAttempt
            )

        guard allowed else {
            throw StreamResolverError.noPlayableStream
        }

        let resolved = try await resolveWithTimeout(
            videoID: videoID,
            preferredQuality: preferredQuality,
            excludingProfiles: excludingProfiles,
            timeoutSeconds: isInitialAttempt ? 15 : 10
        )

        if let profile = resolved.clientProfile {
            PlaybackProfilePreferenceStore.save(
                profile
            )
        } else if isInitialAttempt {
            // A direct YouTubeKit fallback means the previous Alternative
            // profile was not useful for this startup. Do not keep preferring
            // a stale profile on future launches.
            PlaybackProfilePreferenceStore.clear()
        }

        return resolved
    }

    private static func resolveWithTimeout(
        videoID: String,
        preferredQuality: String,
        excludingProfiles: Set<String>,
        timeoutSeconds: TimeInterval
    ) async throws -> PlaybackSource {
        let timeoutNanoseconds =
            UInt64(
                max(
                    1,
                    timeoutSeconds
                ) * 1_000_000_000
            )

        return try await withThrowingTaskGroup(
            of: PlaybackSource.self
        ) { group in
            group.addTask {
                try await resolveWithoutTimeout(
                    videoID: videoID,
                    preferredQuality: preferredQuality,
                    excludingProfiles: excludingProfiles
                )
            }

            group.addTask {
                try await Task.sleep(
                    nanoseconds: timeoutNanoseconds
                )
                try Task.checkCancellation()
                throw StreamResolverError.noPlayableStream
            }

            guard let first = try await group.next() else {
                group.cancelAll()
                throw StreamResolverError.noPlayableStream
            }

            group.cancelAll()
            return first
        }
    }

    private static func resolveWithoutTimeout(
        videoID: String,
        preferredQuality: String,
        excludingProfiles: Set<String>
    ) async throws -> PlaybackSource {
        var meaningfulError: StreamResolverError?

        // Keep the reliable order used by the previous Apple TV build:
        // signed-in TV playback first, then the SmartTube-compatible client
        // chain, then YouTubeKit. The services themselves still use the
        // new HLS/muxed fast-start paths.
        if !excludingProfiles.contains("TV_AUTH"),
           await SmartTubeAuthService.shared.signedIn() {
            do {
                return try await AuthenticatedPlayerService.shared.resolve(
                    videoID: videoID,
                    preferredQuality: preferredQuality
                )
            } catch let error as StreamResolverError {
                if case .ipBlocked = error {
                    throw error
                }

                meaningfulError = error
            } catch {
                // Continue to the SmartTube-compatible fallback chain.
            }
        }

        do {
            return try await AlternativePlayerService.shared.resolve(
                videoID: videoID,
                preferredQuality: preferredQuality,
                excludingProfiles: excludingProfiles
            )
        } catch let error as StreamResolverError {
            if case .ipBlocked = error {
                throw error
            }

            if case .signInRequired = error {
                throw error
            }

            meaningfulError = error
        } catch {
            // Continue to the final direct-stream fallback.
        }

        do {
            let streams = try await YouTube(videoID: videoID).streams

            let combined = streams
                .filterVideoAndAudio()
                .filter { $0.isNativelyPlayable }

            let fallbackURL = bestVideoStream(combined)?.url

            let videoOnly = streams
                .filterVideoOnly()
                .filter { $0.isNativelyPlayable }

            let audioOnly = streams
                .filterAudioOnly()
                .filter { $0.isNativelyPlayable }

            if let requestedHeight = requestedHeight(for: preferredQuality) {
                if let video = bestVideoStream(
                    videoOnly,
                    requestedHeight: requestedHeight
                ),
                   let audio = audioOnly.highestAudioBitrateStream() {
                    return .adaptive(
                        video: video.url,
                        audio: audio.url,
                        fallback: fallbackURL
                    )
                }

                if let exactCombined = bestVideoStream(
                    combined,
                    requestedHeight: requestedHeight
                ) {
                    return .direct(exactCombined.url)
                }
            } else if preferredQuality == "Auto",
                      let fallbackURL {
                // Keep the final YouTubeKit fallback fast on tvOS too.
                // Separate video/audio makes AVFoundation inspect two remote
                // assets before playback can begin.
                return .direct(
                    fallbackURL
                )
            } else if let video = bestVideoStream(videoOnly),
                      let audio = audioOnly.highestAudioBitrateStream() {
                return .adaptive(
                    video: video.url,
                    audio: audio.url,
                    fallback: fallbackURL
                )
            }

            guard let fallbackURL else {
                throw meaningfulError
                    ?? StreamResolverError.noPlayableStream
            }

            return .direct(fallbackURL)
        } catch {
            if let meaningfulError {
                throw meaningfulError
            }

            throw error
        }
    }

    private static func bestVideoStream(
        _ streams: [YouTubeKit.Stream],
        requestedHeight: Int? = nil
    ) -> YouTubeKit.Stream? {
        let candidates: [YouTubeKit.Stream]

        if let requestedHeight {
            candidates = streams.filter {
                $0.videoResolution == requestedHeight
            }
        } else {
            candidates = streams
        }

        return candidates.max { lhs, rhs in
            let leftHeight = lhs.videoResolution ?? 0
            let rightHeight = rhs.videoResolution ?? 0

            if leftHeight != rightHeight {
                return leftHeight < rightHeight
            }

            let leftBitrate =
                lhs.averageBitrate
                ?? lhs.bitrate
                ?? 0
            let rightBitrate =
                rhs.averageBitrate
                ?? rhs.bitrate
                ?? 0

            return leftBitrate < rightBitrate
        }
    }

    static func videoID(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if isLikelyVideoID(trimmed) {
            return trimmed
        }

        guard let url = URL(string: trimmed),
              let host = url.host?.lowercased() else {
            return nil
        }

        if host == "youtu.be" || host.hasSuffix(".youtu.be") {
            let id = url.pathComponents.dropFirst().first ?? ""
            return isLikelyVideoID(id) ? id : nil
        }

        guard host == "youtube.com"
                || host == "www.youtube.com"
                || host == "m.youtube.com"
                || host.hasSuffix(".youtube.com") else {
            return nil
        }

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let id = components.queryItems?.first(where: { $0.name == "v" })?.value,
           isLikelyVideoID(id) {
            return id
        }

        let parts = url.pathComponents.filter { $0 != "/" }
        if let marker = parts.firstIndex(where: { $0 == "shorts" || $0 == "embed" || $0 == "live" }),
           parts.indices.contains(marker + 1) {
            let id = parts[marker + 1]
            return isLikelyVideoID(id) ? id : nil
        }

        return nil
    }

    private static func requestedHeight(for preference: String) -> Int? {
        guard preference.hasSuffix("p") else {
            return nil
        }

        return Int(preference.dropLast())
    }

    private static func isLikelyVideoID(_ value: String) -> Bool {
        guard value.count == 11 else { return false }

        let allowed = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
        )
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
