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
        self.availableHeights = Array(Set(availableHeights.filter { $0 > 0 })).sorted(by: >)
        self.audioTracks = audioTracks
        self.isLive = isLive
        self.isLiveContent = isLiveContent
        self.advertisingMetadataDetected = advertisingMetadataDetected
    }

    var dictionary: [String: String] {
        var result = ["User-Agent": userAgent]
        if let referer, !referer.isEmpty { result["Referer"] = referer }
        if let origin, !origin.isEmpty { result["Origin"] = origin }
        return result
    }
}

enum PlaybackSource: Hashable {
    case direct(URL)
    case directWithHeaders(URL, PlaybackRequestHeaders)
    case adaptive(video: URL, audio: URL, fallback: URL?)
    case adaptiveWithHeaders(video: URL, audio: URL, fallback: URL?, headers: PlaybackRequestHeaders)

    var clientProfile: String? {
        switch self {
        case .directWithHeaders(_, let headers), .adaptiveWithHeaders(_, _, _, let headers):
            return headers.clientProfile
        case .direct, .adaptive:
            return nil
        }
    }

    var diagnosticSourceKind: String {
        switch self {
        case .direct(let url), .directWithHeaders(let url, _):
            let raw = url.absoluteString.lowercased()
            if url.pathExtension.lowercased() == "m3u8"
                || raw.contains("hls_playlist")
                || raw.contains("/manifest/") {
                return "HLS"
            }
            return "DIRECT"
        case .adaptive, .adaptiveWithHeaders:
            return "ADAPTIVE"
        }
    }

    var diagnosticIsLive: Bool? {
        switch self {
        case .directWithHeaders(_, let headers), .adaptiveWithHeaders(_, _, _, let headers):
            return headers.isLive
        case .direct, .adaptive:
            return nil
        }
    }

    var diagnosticIsLiveContent: Bool? {
        switch self {
        case .directWithHeaders(_, let headers), .adaptiveWithHeaders(_, _, _, let headers):
            return headers.isLiveContent
        case .direct, .adaptive:
            return nil
        }
    }

    var diagnosticAdvertisingMetadataDetected: Bool? {
        switch self {
        case .directWithHeaders(_, let headers), .adaptiveWithHeaders(_, _, _, let headers):
            return headers.advertisingMetadataDetected
        case .direct, .adaptive:
            return nil
        }
    }

    var availableQualityHeights: [Int] {
        switch self {
        case .directWithHeaders(_, let headers), .adaptiveWithHeaders(_, _, _, let headers):
            return headers.availableHeights
        case .direct, .adaptive:
            return []
        }
    }

    var availableAudioTracks: [PlaybackAudioTrack] {
        switch self {
        case .directWithHeaders(_, let headers), .adaptiveWithHeaders(_, _, _, let headers):
            return headers.audioTracks
        case .direct, .adaptive:
            return []
        }
    }

    var activeAudioTrackID: String? {
        switch self {
        case .adaptiveWithHeaders(_, let audioURL, _, let headers):
            return headers.audioTracks.first(where: { $0.url == audioURL })?.id
        case .direct, .directWithHeaders, .adaptive:
            return nil
        }
    }

    func replacingAudioTrack(id: String) -> PlaybackSource? {
        guard let track = availableAudioTracks.first(where: { $0.id == id }) else { return nil }
        switch self {
        case .adaptiveWithHeaders(let videoURL, _, let fallback, let headers):
            return .adaptiveWithHeaders(
                video: videoURL,
                audio: track.url,
                fallback: fallback,
                headers: headers
            )
        case .direct, .directWithHeaders, .adaptive:
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
        case .invalidVideoID: return L10n.text("invalid_video_id")
        case .noPlayableStream: return L10n.text("no_playable_stream")
        case .ipBlocked: return L10n.text("youtube_network_blocked")
        case .signInRequired: return L10n.text("youtube_sign_in_required")
        }
    }

    static func playabilityError(status: String, reason: String) -> StreamResolverError? {
        let lowerReason = reason.lowercased()
        let ipBlockKeywords = ["your ip", "ip address", "vpn", "proxy", "bot", "sign in to confirm"]
        if ipBlockKeywords.contains(where: { lowerReason.contains($0) }) {
            return .ipBlocked(reason)
        }

        let signInStatuses: Set<String> = ["LOGIN_REQUIRED", "AGE_VERIFICATION_REQUIRED", "AGE_CHECK_REQUIRED"]
        let signInKeywords = ["sign in", "age-restricted", "age restricted", "18+", "age verification"]
        if signInStatuses.contains(status) || signInKeywords.contains(where: { lowerReason.contains($0) }) {
            return .signInRequired
        }
        return nil
    }
}

private actor StreamResolutionBudget {
    static let shared = StreamResolutionBudget()

    private struct Window {
        let startedAt: Date
        var attempts: Int
    }

    private var windows: [String: Window] = [:]
    private let maximumWindow: TimeInterval = 20
    private let maximumAttempts = 4
    private let staleWindowAge: TimeInterval = 120

    func beginAttempt(videoID: String, reset: Bool) -> Bool {
        let now = Date()
        windows = windows.filter { now.timeIntervalSince($0.value.startedAt) < staleWindowAge }

        if reset || windows[videoID] == nil {
            windows[videoID] = Window(startedAt: now, attempts: 1)
            return true
        }

        guard var window = windows[videoID],
              now.timeIntervalSince(window.startedAt) < maximumWindow,
              window.attempts < maximumAttempts else {
            return false
        }

        window.attempts += 1
        windows[videoID] = window
        return true
    }
}

private enum ResolverAttemptResult: @unchecked Sendable {
    case source(PlaybackSource)
    case failure(StreamResolverError?)
    case timeout
}

enum StreamResolver {
    static func resolveYouTubeVideo(
        videoID: String,
        preferredQuality: String = "Auto",
        excludingProfiles: Set<String> = []
    ) async throws -> PlaybackSource {
        guard !videoID.isEmpty else { throw StreamResolverError.invalidVideoID }

        let isInitialAttempt = excludingProfiles.isEmpty
        let allowed = await StreamResolutionBudget.shared.beginAttempt(
            videoID: videoID,
            reset: isInitialAttempt
        )
        guard allowed else { throw StreamResolverError.noPlayableStream }

        return try await resolveCandidateRace(
            videoID: videoID,
            preferredQuality: preferredQuality,
            excludingProfiles: excludingProfiles,
            timeoutSeconds: isInitialAttempt ? 9.0 : 4.5
        )
    }

    private static func resolveCandidateRace(
        videoID: String,
        preferredQuality: String,
        excludingProfiles: Set<String>,
        timeoutSeconds: TimeInterval
    ) async throws -> PlaybackSource {
        let signedIn = await SmartTubeAuthService.shared.signedIn()
        let canUseAuthenticatedTV = !excludingProfiles.contains("TV_AUTH") && signedIn
        let retryDelay = min(2.7, max(1.2, timeoutSeconds * 0.30))
        let timeoutNanoseconds = UInt64(max(1.0, timeoutSeconds) * 1_000_000_000)
        let retryDelayNanoseconds = UInt64(retryDelay * 1_000_000_000)

        return try await withThrowingTaskGroup(of: ResolverAttemptResult.self) { group in
            var remainingCandidates = 3

            if canUseAuthenticatedTV {
                remainingCandidates += 1
                group.addTask {
                    await authenticatedCandidate(
                        videoID: videoID,
                        preferredQuality: preferredQuality
                    )
                }
            }

            group.addTask {
                await alternativeCandidate(
                    videoID: videoID,
                    preferredQuality: preferredQuality,
                    excludingProfiles: excludingProfiles
                )
            }

            group.addTask {
                await youtubeKitCandidate(
                    videoID: videoID,
                    preferredQuality: preferredQuality
                )
            }

            group.addTask {
                do {
                    try await Task.sleep(nanoseconds: retryDelayNanoseconds)
                    try Task.checkCancellation()
                } catch {
                    return .failure(nil)
                }
                return await alternativeCandidate(
                    videoID: videoID,
                    preferredQuality: preferredQuality,
                    excludingProfiles: excludingProfiles
                )
            }

            group.addTask {
                do {
                    try await Task.sleep(nanoseconds: timeoutNanoseconds)
                    try Task.checkCancellation()
                    return .timeout
                } catch {
                    return .failure(nil)
                }
            }

            var meaningfulError: StreamResolverError?
            var meaningfulPriority = -1

            while let outcome = try await group.next() {
                try Task.checkCancellation()

                switch outcome {
                case .source(let source):
                    group.cancelAll()
                    return source

                case .failure(let error):
                    remainingCandidates -= 1
                    if let error {
                        let priority = errorPriority(error)
                        if priority > meaningfulPriority {
                            meaningfulPriority = priority
                            meaningfulError = error
                        }
                    }

                case .timeout:
                    group.cancelAll()
                    throw meaningfulError ?? StreamResolverError.noPlayableStream
                }

                if remainingCandidates <= 0 {
                    group.cancelAll()
                    throw meaningfulError ?? StreamResolverError.noPlayableStream
                }
            }

            throw meaningfulError ?? StreamResolverError.noPlayableStream
        }
    }

    private static func authenticatedCandidate(
        videoID: String,
        preferredQuality: String
    ) async -> ResolverAttemptResult {
        do {
            return .source(
                try await resolveAuthenticatedWithTimeout(
                    videoID: videoID,
                    preferredQuality: preferredQuality,
                    timeoutSeconds: 2.5
                )
            )
        } catch let error as StreamResolverError {
            return .failure(error)
        } catch is CancellationError {
            return .failure(nil)
        } catch {
            return .failure(nil)
        }
    }

    private static func alternativeCandidate(
        videoID: String,
        preferredQuality: String,
        excludingProfiles: Set<String>
    ) async -> ResolverAttemptResult {
        do {
            return .source(
                try await AlternativePlayerService.shared.resolve(
                    videoID: videoID,
                    preferredQuality: preferredQuality,
                    excludingProfiles: excludingProfiles
                )
            )
        } catch let error as StreamResolverError {
            return .failure(error)
        } catch is CancellationError {
            return .failure(nil)
        } catch {
            return .failure(nil)
        }
    }

    private static func youtubeKitCandidate(
        videoID: String,
        preferredQuality: String
    ) async -> ResolverAttemptResult {
        do {
            return .source(
                try await resolveWithYouTubeKit(
                    videoID: videoID,
                    preferredQuality: preferredQuality
                )
            )
        } catch let error as StreamResolverError {
            return .failure(error)
        } catch is CancellationError {
            return .failure(nil)
        } catch {
            return .failure(nil)
        }
    }

    private static func resolveAuthenticatedWithTimeout(
        videoID: String,
        preferredQuality: String,
        timeoutSeconds: TimeInterval
    ) async throws -> PlaybackSource {
        let timeoutNanoseconds = UInt64(max(1.0, timeoutSeconds) * 1_000_000_000)

        return try await withThrowingTaskGroup(of: PlaybackSource.self) { group in
            group.addTask {
                try await AuthenticatedPlayerService.shared.resolve(
                    videoID: videoID,
                    preferredQuality: preferredQuality
                )
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                try Task.checkCancellation()
                throw StreamResolverError.noPlayableStream
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw StreamResolverError.noPlayableStream
            }
            return first
        }
    }

    private static func resolveWithYouTubeKit(
        videoID: String,
        preferredQuality: String
    ) async throws -> PlaybackSource {
        try Task.checkCancellation()
        let streams = try await YouTube(videoID: videoID).streams
        try Task.checkCancellation()

        let combined = streams.filterVideoAndAudio().filter { $0.isNativelyPlayable }
        let fallbackURL = bestVideoStream(combined)?.url
        let videoOnly = streams.filterVideoOnly().filter { $0.isNativelyPlayable }
        let audioOnly = streams.filterAudioOnly().filter { $0.isNativelyPlayable }

        if let requestedHeight = requestedHeight(for: preferredQuality) {
            if let video = bestVideoStream(videoOnly, requestedHeight: requestedHeight),
               let audio = audioOnly.highestAudioBitrateStream() {
                return .adaptive(video: video.url, audio: audio.url, fallback: fallbackURL)
            }
            if let exactCombined = bestVideoStream(combined, requestedHeight: requestedHeight) {
                return .direct(exactCombined.url)
            }
        } else if preferredQuality == "Auto", let fallbackURL {
            return .direct(fallbackURL)
        } else if let video = bestVideoStream(videoOnly),
                  let audio = audioOnly.highestAudioBitrateStream() {
            return .adaptive(video: video.url, audio: audio.url, fallback: fallbackURL)
        }

        guard let fallbackURL else { throw StreamResolverError.noPlayableStream }
        return .direct(fallbackURL)
    }

    private static func errorPriority(_ error: StreamResolverError) -> Int {
        switch error {
        case .invalidVideoID: return 4
        case .ipBlocked: return 3
        case .signInRequired: return 2
        case .noPlayableStream: return 1
        }
    }

    private static func bestVideoStream(
        _ streams: [YouTubeKit.Stream],
        requestedHeight: Int? = nil
    ) -> YouTubeKit.Stream? {
        let candidates: [YouTubeKit.Stream]
        if let requestedHeight {
            candidates = streams.filter { $0.videoResolution == requestedHeight }
        } else {
            candidates = streams
        }

        return candidates.max { lhs, rhs in
            let leftHeight = lhs.videoResolution ?? 0
            let rightHeight = rhs.videoResolution ?? 0
            if leftHeight != rightHeight { return leftHeight < rightHeight }
            return (lhs.averageBitrate ?? lhs.bitrate ?? 0)
                < (rhs.averageBitrate ?? rhs.bitrate ?? 0)
        }
    }

    static func videoID(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if isLikelyVideoID(trimmed) { return trimmed }

        guard let url = URL(string: trimmed), let host = url.host?.lowercased() else {
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
        guard preference.hasSuffix("p") else { return nil }
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
