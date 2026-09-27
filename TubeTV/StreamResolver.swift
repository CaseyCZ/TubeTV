import Foundation
import YouTubeKit

enum PlaybackSource: Hashable {
    case direct(URL)
    case adaptive(video: URL, audio: URL, fallback: URL?)
}

enum StreamResolverError: LocalizedError {
    case invalidVideoID
    case noPlayableStream

    var errorDescription: String? {
        switch self {
        case .invalidVideoID:
            return "Neplatné YouTube video ID."
        case .noPlayableStream:
            return "Pro toto video se nepodařilo najít stream přehratelný na Apple TV."
        }
    }
}

enum StreamResolver {
    static func resolveYouTubeVideo(
        videoID: String,
        preferredQuality: String = "Auto"
    ) async throws -> PlaybackSource {
        guard !videoID.isEmpty else {
            throw StreamResolverError.invalidVideoID
        }

        if await SmartTubeAuthService.shared.signedIn() {
            do {
                return try await AuthenticatedPlayerService.shared.resolve(
                    videoID: videoID,
                    preferredQuality: preferredQuality
                )
            } catch {
                // Keep SmartTube-style auth as the preferred path, but
                // fall back to YouTubeKit so normal videos still play.
            }
        }

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
            throw StreamResolverError.noPlayableStream
        }

        return .direct(fallbackURL)
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
        switch preference {
        case "1080p":
            return 1080
        case "1440p":
            return 1440
        case "2160p":
            return 2160
        default:
            return nil
        }
    }

    private static func isLikelyVideoID(_ value: String) -> Bool {
        guard value.count == 11 else { return false }

        let allowed = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
        )
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
