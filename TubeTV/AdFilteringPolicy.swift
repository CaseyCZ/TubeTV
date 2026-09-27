import Foundation

struct YouTubeAdMetadata: Hashable {
    let hasAdPlacements: Bool
    let hasPlayerAds: Bool
    let hasAdSlots: Bool
    let hasAdBreakHeartbeat: Bool

    var containsAdvertisingMetadata: Bool {
        hasAdPlacements
            || hasPlayerAds
            || hasAdSlots
            || hasAdBreakHeartbeat
    }
}

enum AdFilteringPolicy {
    /// SmartTube-style approach:
    /// never turn YouTube ad metadata into playable media.
    /// TubeTV only resolves the video's own streamingData formats.
    static func inspectPlayerResponse(
        _ root: [String: Any]
    ) -> YouTubeAdMetadata {
        YouTubeAdMetadata(
            hasAdPlacements: nonEmpty(root["adPlacements"]),
            hasPlayerAds: nonEmpty(root["playerAds"]),
            hasAdSlots: nonEmpty(root["adSlots"]),
            hasAdBreakHeartbeat:
                (root["adBreakHeartbeatParams"] as? String)?.isEmpty == false
        )
    }

    static func contentStreamingData(
        from root: [String: Any]
    ) -> [String: Any]? {
        root["streamingData"] as? [String: Any]
    }

    /// HLS is deliberately a last-resort fallback. Direct content
    /// video/audio formats are preferred because they are independent
    /// from YouTube's ad placement objects.
    static func shouldUseHLSFallback(
        adMetadata: YouTubeAdMetadata,
        hasDirectContentFormats: Bool
    ) -> Bool {
        guard !hasDirectContentFormats else {
            return false
        }

        // If the player response explicitly contains ad metadata,
        // don't hand the YouTube HLS manifest directly to AVPlayer.
        return !adMetadata.containsAdvertisingMetadata
    }

    private static func nonEmpty(_ value: Any?) -> Bool {
        if let array = value as? [Any] {
            return !array.isEmpty
        }

        if let dictionary = value as? [String: Any] {
            return !dictionary.isEmpty
        }

        if let string = value as? String {
            return !string.isEmpty
        }

        return value != nil
    }
}
