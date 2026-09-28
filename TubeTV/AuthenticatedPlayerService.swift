import AVFoundation
import Foundation
import VideoToolbox

enum AuthenticatedPlayerError: LocalizedError {
    case notSignedIn
    case invalidResponse
    case unplayable(String)
    case noPlayableStream

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return L10n.text("authenticated_player_not_signed_in")
        case .invalidResponse:
            return L10n.text("authenticated_player_invalid_response")
        case .unplayable(let reason):
            return reason.isEmpty
                ? L10n.text("authenticated_player_unavailable")
                : reason
        case .noPlayableStream:
            return L10n.text("authenticated_player_no_stream")
        }
    }
}

private struct InnerTubeFormat {
    let url: URL
    let mimeType: String
    let height: Int?
    let fps: Int?
    let bitrate: Int?
    let hasAudio: Bool
    let audioTrackID: String?
    let audioTrackDisplayName: String?
    let audioIsDefault: Bool
    let isAutoDubbed: Bool
    let isHDR: Bool

    var isVideo: Bool {
        mimeType.hasPrefix("video/")
    }

    var isAudio: Bool {
        mimeType.hasPrefix("audio/")
    }

    var isAppleFriendlyVideo: Bool {
        guard isVideo else { return false }

        if mimeType.contains("avc1") {
            return VTIsHardwareDecodeSupported(
                kCMVideoCodecType_H264
            )
        }

        if mimeType.contains("hvc1") || mimeType.contains("hev1") {
            return VTIsHardwareDecodeSupported(
                kCMVideoCodecType_HEVC
            )
        }

        if mimeType.contains("av01") {
            return VTIsHardwareDecodeSupported(
                kCMVideoCodecType_AV1
            )
        }

        // YouTube VP9 is intentionally not accepted by AVPlayer here.
        return false
    }

    var isAppleFriendlyAudio: Bool {
        isAudio && (
            mimeType.contains("mp4a")
            || mimeType.hasPrefix("audio/mp4")
        )
    }

    var codecPriority: Int {
        if mimeType.contains("hvc1") || mimeType.contains("hev1") {
            return 0
        }

        if mimeType.contains("avc1") {
            return 1
        }

        if mimeType.contains("av01") {
            return 2
        }

        return 9
    }
}

actor AuthenticatedPlayerService {
    static let shared = AuthenticatedPlayerService()

    func resolve(
        videoID: String,
        preferredQuality: String
    ) async throws -> PlaybackSource {
        guard await SmartTubeAuthService.shared.signedIn() else {
            throw AuthenticatedPlayerError.notSignedIn
        }

        let bootstrap = try await SmartTubeAuthService.shared.bootstrap()
        let authorization = try await SmartTubeAuthService.shared.authorizationHeader()
        let cpn = Self.generateCPN()
        let offsetMinutes = TimeZone.current.secondsFromGMT() / 60

        let playerClientVersion = "5.20260901"
        let playerUserAgent =
            "Mozilla/5.0 (DirectFB; Linux x86_64) Cobalt/4.13031-qa (unlike Gecko) Starboard/1"
        var client: [String: Any] = [
            "clientName": "TVHTML5",
            "clientVersion": playerClientVersion,
            "clientScreen": "WATCH",
            "userAgent": playerUserAgent,
            "acceptLanguage": L10n.currentLanguageCode,
            "acceptRegion": "CZ",
            "utcOffsetMinutes": offsetMinutes
        ]

        if let visitorData = bootstrap.visitorData,
           !visitorData.isEmpty {
            client["visitorData"] = visitorData
        }

        let payload: [String: Any] = [
            "context": [
                "client": client,
                "user": [
                    "enableSafetyMode": false,
                    "lockedSafetyMode": false
                ]
            ],
            "videoId": videoID,
            "cpn": cpn,
            "racyCheckOk": true,
            "contentCheckOk": true,
            "playbackContext": [
                "contentPlaybackContext": [
                    "html5Preference": "HTML5_PREF_WANTS",
                    "lactMilliseconds": 60_000,
                    "isInlinePlaybackNoAd": true
                ],
                "devicePlaybackCapabilities": [
                    "supportsVp9Encoding": true,
                    "supportXhr": false
                ]
            ]
        ]

        guard let playerURL = URL(
            string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false"
        ) else {
            throw AuthenticatedPlayerError.invalidResponse
        }

        var request = URLRequest(
            url: playerURL
        )
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            playerUserAgent,
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(
            "https://www.youtube.com/tv",
            forHTTPHeaderField: "Referer"
        )
        request.setValue(
            authorization,
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("7", forHTTPHeaderField: "X-Youtube-Client-Name")
        request.setValue(
            playerClientVersion,
            forHTTPHeaderField: "X-Youtube-Client-Version"
        )

        if let pageID = await SmartTubeAuthService.shared.selectedPageID(),
           !pageID.isEmpty {
            request.setValue(pageID, forHTTPHeaderField: "X-Goog-Pageid")
        }

        if let visitorData = bootstrap.visitorData,
           !visitorData.isEmpty {
            request.setValue(
                visitorData,
                forHTTPHeaderField: "X-Goog-Visitor-Id"
            )
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthenticatedPlayerError.invalidResponse
        }

        let playability =
            root["playabilityStatus"] as? [String: Any]
        let status =
            playability?["status"] as? String
            ?? "UNKNOWN"
        let reason =
            playability?["reason"] as? String
            ?? ""

        let adMetadata = AdFilteringPolicy.inspectPlayerResponse(root)
        let videoDetails =
            root["videoDetails"] as? [String: Any]
        let isLive =
            videoDetails?["isLive"] as? Bool
            ?? false

        guard let streaming = AdFilteringPolicy.contentStreamingData(
            from: root
        ) else {
            if let playabilityError =
                StreamResolverError.playabilityError(
                    status: status,
                    reason: reason
                ) {
                throw playabilityError
            }

            if status != "OK" {
                throw AuthenticatedPlayerError.unplayable(reason)
            }

            throw AuthenticatedPlayerError.noPlayableStream
        }

        // SmartTubeIOS only treats non-OK playability as fatal when
        // YouTube did not return usable streamingData. If content is
        // present, continue and let the format checks decide.

        let combined = Self.formats(
            from: streaming["formats"]
        )
        .filter { $0.isVideo && $0.hasAudio }

        let adaptive = Self.formats(
            from: streaming["adaptiveFormats"]
        )

        let hlsURL =
            (streaming["hlsManifestUrl"] as? String)
                .flatMap(URL.init(string:))

        let fallback = Self.bestCombined(
            combined,
            requestedHeight: Self.requestedHeight(for: preferredQuality)
        )?.url

        let videos = adaptive
            .filter { $0.isAppleFriendlyVideo }
            .sorted(by: Self.videoSort)

        let combinedVideoHeights = combined
            .filter {
                $0.mimeType.hasPrefix("video/mp4")
            }
            .compactMap { $0.height }

        let availableHeights = Array(
            Set(
                combinedVideoHeights
                + videos.compactMap { $0.height }
            )
        ).sorted(by: >)

        let audios = adaptive
            .filter { $0.isAppleFriendlyAudio }
            .sorted {
                ($0.bitrate ?? 0) > ($1.bitrate ?? 0)
            }

        let audioTracks =
            Self.playbackAudioTracks(
                from: audios
            )

        let playbackHeaders = PlaybackRequestHeaders(
            userAgent: playerUserAgent,
            referer: "https://www.youtube.com/tv",
            clientProfile: "TV_AUTH",
            availableHeights: availableHeights,
            audioTracks: audioTracks,
            isLive: isLive,
            advertisingMetadataDetected:
                adMetadata
                    .containsAdvertisingMetadata
        )

        // tvOS fast-start path. The authenticated TV response used to
        // choose separate adaptive video+audio for Auto. Building an
        // AVMutableComposition requires loading tracks and durations from
        // both remote assets and becomes especially slow on long videos.
        // Prefer a clean HLS manifest because AVPlayer can start from the
        // first segments without inspecting the complete media files.
        if preferredQuality == "Auto",
           let hlsURL,
           !adMetadata.containsAdvertisingMetadata {
            return .directWithHeaders(
                hlsURL,
                playbackHeaders
            )
        }

        // If the authenticated response has no usable HLS, a muxed MP4 is
        // still faster to start than composing separate streams.
        if preferredQuality == "Auto",
           let fallback {
            return .directWithHeaders(
                fallback,
                playbackHeaders
            )
        }

        // Explicit quality choices may still need separate video and audio
        // to reach 1080p/4K.
        if let audio = audios.first,
           let height = Self.requestedHeight(
                for: preferredQuality
           ),
           let video = videos.first(
                where: { $0.height == height }
           ) {
            return .adaptiveWithHeaders(
                video: video.url,
                audio: audio.url,
                fallback: fallback,
                headers: playbackHeaders
            )
        }

        if let fallback {
            return .directWithHeaders(
                fallback,
                playbackHeaders
            )
        }

        if let hlsURL,
           !adMetadata.containsAdvertisingMetadata {
            return .directWithHeaders(
                hlsURL,
                playbackHeaders
            )
        }

        // Do not play ad placements or ad-bearing HLS fallbacks.
        // StreamResolver will try YouTubeKit next, similar to
        // SmartTube switching to another player client.
        throw AuthenticatedPlayerError.noPlayableStream
    }

    private static func formats(from value: Any?) -> [InnerTubeFormat] {
        guard let items = value as? [[String: Any]] else {
            return []
        }

        return items.compactMap { item in
            guard let rawURL = item["url"] as? String,
                  let url = URL(string: rawURL),
                  let mimeType = item["mimeType"] as? String else {
                return nil
            }

            let audioTrack =
                item["audioTrack"] as? [String: Any]

            return InnerTubeFormat(
                url: url,
                mimeType: mimeType,
                height: item["height"] as? Int,
                fps: item["fps"] as? Int,
                bitrate: item["bitrate"] as? Int,
                hasAudio: item["audioQuality"] != nil
                    || item["audioChannels"] != nil,
                audioTrackID:
                    audioTrack?["id"] as? String,
                audioTrackDisplayName:
                    audioTrack?["displayName"] as? String,
                audioIsDefault:
                    audioTrack?["audioIsDefault"] as? Bool
                    ?? false,
                isAutoDubbed:
                    audioTrack?["isAutoDubbed"] as? Bool
                    ?? false,
                isHDR: Self.isHDRFormat(item)
            )
        }
    }

    private static func playbackAudioTracks(
        from formats: [InnerTubeFormat]
    ) -> [PlaybackAudioTrack] {
        var seen = Set<String>()
        var tracks: [PlaybackAudioTrack] = []

        for format in formats {
            guard let trackID = format.audioTrackID,
                  !trackID.isEmpty,
                  seen.insert(trackID).inserted else {
                continue
            }

            let parts = trackID.split(
                separator: ".",
                omittingEmptySubsequences: false
            )
            let languageCode =
                parts.first.map(String.init)
                ?? trackID

            // Match SmartTube MediaServiceCore:
            // the ".4" audio track is the original track.
            let isOriginal =
                parts.count == 2
                    ? parts[1] == "4"
                    : format.audioIsDefault

            let displayName: String
            if let rawName =
                format.audioTrackDisplayName,
               !rawName.isEmpty {
                displayName = rawName
            } else {
                displayName =
                    Locale(
                        identifier:
                            L10n.currentLanguageCode
                    )
                    .localizedString(
                        forLanguageCode:
                            languageCode
                    )?
                    .capitalized
                    ?? languageCode
            }

            tracks.append(
                PlaybackAudioTrack(
                    id: trackID,
                    displayName: displayName,
                    languageCode: languageCode,
                    isDefault: format.audioIsDefault,
                    isOriginal: isOriginal,
                    isAutoDubbed: format.isAutoDubbed,
                    url: format.url
                )
            )
        }

        return tracks
    }

    private static func bestCombined(
        _ formats: [InnerTubeFormat],
        requestedHeight: Int?
    ) -> InnerTubeFormat? {
        let appleFormats = formats
            .filter {
                $0.mimeType.hasPrefix("video/mp4")
                && $0.mimeType.contains("mp4a")
            }

        if let requestedHeight,
           let exact = appleFormats
            .filter({ $0.height == requestedHeight })
            .max(by: {
                if ($0.fps ?? 0) != ($1.fps ?? 0) {
                    return ($0.fps ?? 0) < ($1.fps ?? 0)
                }

                return ($0.bitrate ?? 0) < ($1.bitrate ?? 0)
            }) {
            return exact
        }

        return appleFormats.max {
            let leftHeight = $0.height ?? 0
            let rightHeight = $1.height ?? 0

            if leftHeight != rightHeight {
                return leftHeight < rightHeight
            }

            let leftFPS = $0.fps ?? 0
            let rightFPS = $1.fps ?? 0

            if leftFPS != rightFPS {
                return leftFPS < rightFPS
            }

            return ($0.bitrate ?? 0) < ($1.bitrate ?? 0)
        }
    }

    private static func videoSort(
        _ lhs: InnerTubeFormat,
        _ rhs: InnerTubeFormat
    ) -> Bool {
        let leftHeight = lhs.height ?? 0
        let rightHeight = rhs.height ?? 0

        if leftHeight != rightHeight {
            return leftHeight > rightHeight
        }

        let leftFPS = lhs.fps ?? 0
        let rightFPS = rhs.fps ?? 0

        if leftFPS != rightFPS {
            return leftFPS > rightFPS
        }

        if lhs.isHDR != rhs.isHDR {
            if AVPlayer.eligibleForHDRPlayback {
                return lhs.isHDR
            }

            return !lhs.isHDR
        }

        if lhs.codecPriority != rhs.codecPriority {
            return lhs.codecPriority < rhs.codecPriority
        }

        return (lhs.bitrate ?? 0) > (rhs.bitrate ?? 0)
    }

    private static func isHDRFormat(
        _ item: [String: Any]
    ) -> Bool {
        if let colorInfo = item["colorInfo"] as? [String: Any] {
            let text = colorInfo.description.lowercased()

            if text.contains("2084")
                || text.contains("2100")
                || text.contains("hdr")
                || text.contains("hlg")
                || text.contains("pq") {
                return true
            }
        }

        if let mimeType = item["mimeType"] as? String {
            let lowered = mimeType.lowercased()

            if lowered.contains("dvh1")
                || lowered.contains("dvhe") {
                return true
            }
        }

        return false
    }

    private static func requestedHeight(for preference: String) -> Int? {
        guard preference.hasSuffix("p") else {
            return nil
        }

        return Int(preference.dropLast())
    }

    private static func generateCPN() -> String {
        let alphabet = Array(
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
        )
        var generator = SystemRandomNumberGenerator()

        return String(
            (0..<16).map { _ in
                alphabet.randomElement(using: &generator)
                    ?? "A"
            }
        )
    }
}
