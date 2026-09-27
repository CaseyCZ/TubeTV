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

    init(
        userAgent: String,
        referer: String? = nil,
        origin: String? = nil,
        clientProfile: String? = nil,
        availableHeights: [Int] = [],
        audioTracks: [PlaybackAudioTrack] = []
    ) {
        self.userAgent = userAgent
        self.referer = referer
        self.origin = origin
        self.clientProfile = clientProfile
        self.availableHeights = Array(
            Set(availableHeights.filter { $0 > 0 })
        ).sorted(by: >)
        self.audioTracks = audioTracks
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

enum StreamResolver {
    static func resolveYouTubeVideo(
        videoID: String,
        preferredQuality: String = "Auto",
        excludingProfiles: Set<String> = []
    ) async throws -> PlaybackSource {
        guard !videoID.isEmpty else {
            throw StreamResolverError.invalidVideoID
        }

        var meaningfulError: StreamResolverError?

        if !excludingProfiles.contains("TV_AUTH"),
           await SmartTubeAuthService.shared.signedIn() {
            do {
                return try await AuthenticatedPlayerService.shared.resolve(
                    videoID: videoID,
                    preferredQuality: preferredQuality
                )
            } catch let error as StreamResolverError {
                if case .ipBlocked = error {
                    // SmartTubeIOS short-circuits IP blocks because repeated
                    // /player requests can prolong the network block.
                    throw error
                }

                meaningfulError = error
            } catch {
                // Continue with the same unauthenticated fallbacks SmartTube uses.
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
                // Do not let YouTubeKit replace a useful sign-in/age-gate
                // diagnosis with a generic extraction error.
                throw error
            }

            meaningfulError = error
        } catch {
            // Final direct-stream fallback.
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
