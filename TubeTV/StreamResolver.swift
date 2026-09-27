import Foundation
import YouTubeKit

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
    ) async throws -> URL {
        guard !videoID.isEmpty else {
            throw StreamResolverError.invalidVideoID
        }

        let streams = try await YouTube(videoID: videoID).streams
            .filterVideoAndAudio()
            .filter { $0.isNativelyPlayable }

        guard !streams.isEmpty else {
            throw StreamResolverError.noPlayableStream
        }

        if let requestedHeight = requestedHeight(for: preferredQuality),
           let exact = streams
            .streams(withExactResolution: requestedHeight)
            .highestResolutionStream() {
            return exact.url
        }

        guard let best = streams.highestResolutionStream() else {
            throw StreamResolverError.noPlayableStream
        }

        return best.url
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

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
