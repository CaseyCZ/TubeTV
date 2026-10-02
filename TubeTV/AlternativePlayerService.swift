import AVFoundation
import Foundation
import OSLog
import VideoToolbox

private struct AlternativePlayerClient {
    let profile: String
    let name: String
    let version: String
    let innerTubeName: String
    let userAgent: String
    let referer: String?
    let origin: String?
    let apiKey: String?
    let clientScreen: String
    let supportXhr: Bool
    let seedWebSession: Bool
    let extraClientFields: [String: Any]
    let thirdParty: [String: Any]?
}

private struct AlternativeFormat {
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

    var isNativeVideo: Bool {
        guard isVideo else { return false }

        if mimeType.contains("avc1") {
            return VTIsHardwareDecodeSupported(
                kCMVideoCodecType_H264
            )
        }

        if mimeType.contains("hvc1")
            || mimeType.contains("hev1")
            || mimeType.contains("dvh1")
            || mimeType.contains("dvhe") {
            return VTIsHardwareDecodeSupported(
                kCMVideoCodecType_HEVC
            )
        }

        if mimeType.contains("av01") {
            return VTIsHardwareDecodeSupported(
                kCMVideoCodecType_AV1
            )
        }

        return false
    }

    var isNativeAudio: Bool {
        isAudio && (
            mimeType.contains("mp4a")
            || mimeType.contains("ac-3")
            || mimeType.contains("ec-3")
            || mimeType.hasPrefix("audio/mp4")
        )
    }

    var codecPriority: Int {
        if mimeType.contains("hvc1")
            || mimeType.contains("hev1")
            || mimeType.contains("dvh1")
            || mimeType.contains("dvhe") {
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

    // SmartTubeIOS skips these on AVPlayer unless a valid poToken is available.
    var requiresPoToken: Bool {
        url.absoluteString.contains("/rqh/1/")
    }
}

actor AlternativePlayerService {
    static let shared = AlternativePlayerService()

    private static let webAPIKey =
        "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8"
    private static let tvAPIKey =
        "AIzaSyDCU8mBbAkSfXX4txZFpEpPEBoAOUMCxkU"

    private let logger = Logger(
        subsystem: "cz.caseycz.tubetv",
        category: "PlayerResolver"
    )

    private let session: URLSession
    private var visitorData: String?
    private var signatureTimestamp: Int?
    private var signatureTimestampFetchedAt: Date?
    private var lastSuccessfulProfile: String?
    private var captionRendererCache: [String: Data] = [:]

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        configuration.httpShouldSetCookies = true
        session = URLSession(configuration: configuration)
    }

    // Keep this list in the same order as SmartTube MediaServiceCore
    // VIDEO_INFO_TYPE_LIST. Do not add extra profiles to the normal startup
    // path: SmartTube intentionally skips several clients that are known to
    // hang or require additional token/cipher handling.
    private var clients: [AlternativePlayerClient] {
        [
            AlternativePlayerClient(
                profile: "VISIONOS",
                name: "VISIONOS",
                version: "1.02",
                innerTubeName: "101",
                userAgent:
                    "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15",
                referer: nil,
                origin: "https://www.youtube.com",
                apiKey: Self.webAPIKey,
                clientScreen: "WATCH",
                supportXhr: true,
                seedWebSession: true,
                extraClientFields: [
                    "deviceMake": "Apple",
                    "deviceModel": "RealityDevice17,1",
                    "osName": "visionOS",
                    "osVersion": "26.5.23O471"
                ],
                thirdParty: nil
            ),
            AlternativePlayerClient(
                profile: "TV_DOWNGRADED",
                name: "TVHTML5",
                version: "5.20260901",
                innerTubeName: "7",
                userAgent:
                    "Mozilla/5.0 (DirectFB; Linux x86_64) Cobalt/4.13031-qa (unlike Gecko) Starboard/1",
                referer: "https://www.youtube.com/tv",
                origin: nil,
                apiKey: Self.webAPIKey,
                clientScreen: "WATCH",
                supportXhr: false,
                seedWebSession: false,
                extraClientFields: [:],
                thirdParty: nil
            ),
            AlternativePlayerClient(
                profile: "WEB",
                name: "WEB",
                version: "2.20260907.06.00",
                innerTubeName: "1",
                userAgent:
                    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/94.0.4606.81 Safari/537.36",
                referer: "https://www.youtube.com",
                origin: "https://www.youtube.com",
                apiKey: Self.webAPIKey,
                clientScreen: "WATCH",
                supportXhr: true,
                seedWebSession: false,
                extraClientFields: [
                    "browserName": "Chrome",
                    "browserVersion": "94.0.4606.81",
                    "timeZone": "UTC",
                    "utcOffsetMinutes": 0
                ],
                thirdParty: nil
            ),
            AlternativePlayerClient(
                profile: "WEB_EMBED",
                name: "WEB_EMBEDDED_PLAYER",
                version: "2.20260908.01.00",
                innerTubeName: "56",
                userAgent:
                    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.5 Safari/605.1.15,gzip(gfe)",
                referer: "https://www.youtube.com",
                origin: "https://www.youtube.com",
                apiKey: Self.webAPIKey,
                clientScreen: "EMBED",
                supportXhr: true,
                seedWebSession: false,
                extraClientFields: [
                    "browserName": "Safari",
                    "browserVersion": "15.5"
                ],
                thirdParty: [
                    "embedUrl": "https://www.reddit.com/"
                ]
            ),
            AlternativePlayerClient(
                profile: "WEB_SAFARI",
                name: "WEB",
                version: "2.20260907.06.00",
                innerTubeName: "1",
                userAgent:
                    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.5 Safari/605.1.15,gzip(gfe)",
                referer: "https://www.youtube.com",
                origin: "https://www.youtube.com",
                apiKey: Self.webAPIKey,
                clientScreen: "WATCH",
                supportXhr: true,
                seedWebSession: false,
                extraClientFields: [
                    "browserName": "Safari",
                    "browserVersion": "15.5",
                    "timeZone": "UTC",
                    "utcOffsetMinutes": 0
                ],
                thirdParty: nil
            ),
            AlternativePlayerClient(
                profile: "IOS",
                name: "iOS",
                version: "21.26.4",
                innerTubeName: "5",
                userAgent:
                    "com.google.ios.youtube/21.26.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)",
                referer: nil,
                origin: nil,
                apiKey: Self.webAPIKey,
                clientScreen: "WATCH",
                supportXhr: true,
                seedWebSession: false,
                extraClientFields: [
                    "deviceMake": "Apple",
                    "deviceModel": "iPhone16,2",
                    "osName": "iPhone",
                    "osVersion": "18.3.2.22D82"
                ],
                thirdParty: nil
            ),
            AlternativePlayerClient(
                profile: "GEO",
                name: "WEB",
                version: "2.20260907.06.00",
                innerTubeName: "1",
                userAgent:
                    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/94.0.4606.81 Safari/537.36",
                referer: "https://www.youtube.com",
                origin: "https://www.youtube.com",
                apiKey: Self.webAPIKey,
                clientScreen: "WATCH",
                supportXhr: true,
                seedWebSession: false,
                extraClientFields: [
                    "browserName": "Chrome",
                    "browserVersion": "94.0.4606.81",
                    "timeZone": "UTC",
                    "utcOffsetMinutes": 0
                ],
                thirdParty: nil
            ),
            AlternativePlayerClient(
                profile: "MWEB",
                name: "MWEB",
                version: "2.20260907.05.00",
                innerTubeName: "2",
                userAgent:
                    "Mozilla/5.0 (iPad; CPU OS 16_7_10 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1,gzip(gfe)",
                referer: "https://m.youtube.com",
                origin: "https://m.youtube.com",
                apiKey: Self.webAPIKey,
                clientScreen: "WATCH",
                supportXhr: true,
                seedWebSession: false,
                extraClientFields: [:],
                thirdParty: nil
            ),
            AlternativePlayerClient(
                profile: "ANDROID_VR",
                name: "ANDROID_VR",
                version: "1.65.10",
                innerTubeName: "28",
                userAgent:
                    "com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip",
                referer: nil,
                origin: "https://www.youtube.com",
                apiKey: Self.tvAPIKey,
                clientScreen: "WATCH",
                supportXhr: true,
                seedWebSession: true,
                extraClientFields: [
                    "androidSdkVersion": 32,
                    "osName": "Android",
                    "osVersion": "12",
                    "deviceMake": "Oculus",
                    "deviceModel": "Quest 3"
                ],
                thirdParty: nil
            )
,
        ]
    }

    func resolve(
        videoID: String,
        preferredQuality: String,
        excludingProfiles: Set<String> = []
    ) async throws -> PlaybackSource {
        var lastError: Error =
            StreamResolverError.noPlayableStream

        let availableClients =
            clients.filter {
                !excludingProfiles.contains(
                    $0.profile
                )
            }
        let orderedClients: [AlternativePlayerClient]

        // The auth/bootstrap layer already caches visitorData. Reuse it here
        // so the first video doesn't need an extra youtube.com/watch page
        // request just to seed the resolver.
        if visitorData == nil,
           let bootstrap =
                try? await SmartTubeAuthService
                    .shared.bootstrap(),
           let bootstrapVisitor =
                bootstrap.visitorData,
           !bootstrapVisitor.isEmpty {
            visitorData = bootstrapVisitor
        }

        if let lastSuccessfulProfile,
           let preferred =
                availableClients.first(
                    where: {
                        $0.profile
                            == lastSuccessfulProfile
                    }
                ) {
            orderedClients =
                [preferred]
                + availableClients.filter {
                    $0.profile
                        != lastSuccessfulProfile
                }
        } else {
            orderedClients = availableClients
        }

        let resolveStartedAt = Date()

        for client in orderedClients {
            let clientStartedAt = Date()

            do {
                // Seeding is useful for WEB/VISIONOS-style clients, but once
                // visitorData has been obtained repeating the extra page load
                // for every video only slows startup down.
                if client.seedWebSession,
                   visitorData == nil {
                    await seedWebSession(
                        videoID: videoID
                    )
                }

                if let source = try await resolve(
                    videoID: videoID,
                    preferredQuality: preferredQuality,
                    client: client
                ) {
                    let clientMs =
                        Int(
                            Date()
                                .timeIntervalSince(
                                    clientStartedAt
                                ) * 1_000
                        )
                    let totalMs =
                        Int(
                            Date()
                                .timeIntervalSince(
                                    resolveStartedAt
                                ) * 1_000
                        )

                    logger.notice(
                        "Resolved with client=\(client.profile, privacy: .public) version=\(client.version, privacy: .public) clientMs=\(clientMs, privacy: .public) totalMs=\(totalMs, privacy: .public)"
                    )
                    return source
                }
            } catch let error as StreamResolverError {
                if case .ipBlocked = error {
                    logger.error(
                        "IP blocked client=\(client.profile, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                    )
                    throw error
                }

                lastError = error
                logger.error(
                    "Client failed client=\(client.profile, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
            } catch {
                lastError = error
                logger.error(
                    "Client failed client=\(client.profile, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
            }
        }

        throw lastError
    }

    func markPlaybackSuccessful(
        profile: String
    ) {
        lastSuccessfulProfile = profile

        logger.notice(
            "Playback profile confirmed=\(profile, privacy: .public)"
        )
    }

    func markPlaybackFailed(
        profile: String
    ) {
        if lastSuccessfulProfile == profile {
            lastSuccessfulProfile = nil
        }

        logger.notice(
            "Playback profile rejected=\(profile, privacy: .public)"
        )
    }

    private func seedWebSession(
        videoID: String
    ) async {
        var components = URLComponents(
            string: "https://www.youtube.com/watch"
        )
        components?.queryItems = [
            URLQueryItem(name: "v", value: videoID),
            URLQueryItem(
                name: "bpctr",
                value: "9999999999"
            ),
            URLQueryItem(
                name: "has_verified",
                value: "1"
            )
        ]

        guard let url = components?.url else {
            return
        }

        if let cookie = HTTPCookie(
            properties: [
                .domain: ".youtube.com",
                .path: "/",
                .name: "SOCS",
                .value: "CAI",
                .secure: "TRUE",
                .expires: Date(
                    timeIntervalSinceNow:
                        365 * 24 * 60 * 60
                )
            ]
        ) {
            HTTPCookieStorage.shared.setCookie(cookie)
        }

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 8
        )
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.5 Safari/605.1.15,gzip(gfe)",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(
            L10n.acceptLanguageHeader,
            forHTTPHeaderField: "Accept-Language"
        )

        do {
            let (data, response) =
                try await session.data(for: request)

            guard let http =
                    response as? HTTPURLResponse,
                  (200..<300).contains(
                    http.statusCode
                  ),
                  let html = String(
                    data: data,
                    encoding: .utf8
                  ) else {
                logger.notice(
                    "Session seed failed status"
                )
                return
            }

            if let visitor =
                Self.extractVisitorData(
                    from: html
                ) {
                visitorData = visitor
                logger.notice(
                    "Session seeded visitorDataLen=\(visitor.count, privacy: .public)"
                )
            } else {
                logger.notice(
                    "Session seeded without visitorData"
                )
            }
        } catch {
            logger.notice(
                "Session seed request failed error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func resolve(
        videoID: String,
        preferredQuality: String,
        client: AlternativePlayerClient
    ) async throws -> PlaybackSource? {
        var clientFields =
            clientFields(for: client)

        let bootstrap =
            try? await SmartTubeAuthService
                .shared.bootstrap()
        let bootstrapVisitor =
            bootstrap?.visitorData

        let effectiveVisitor =
            visitorData ?? bootstrapVisitor

        if client.profile != "ANDROID",
           let effectiveVisitor,
           !effectiveVisitor.isEmpty {
            clientFields["visitorData"] =
                effectiveVisitor
        }

        var context: [String: Any] = [
            "client": clientFields,
            "user": [
                "enableSafetyMode": false,
                "lockedSafetyMode": false
            ]
        ]

        if let thirdParty =
            client.thirdParty {
            context["thirdParty"] =
                thirdParty
        }

        var contentPlaybackContext: [String: Any] = [
            "html5Preference": "HTML5_PREF_WANTS"
        ]

        if client.profile == "TV_DOWNGRADED" {
            contentPlaybackContext["lactMilliseconds"] =
                60_000
            contentPlaybackContext["isInlinePlaybackNoAd"] =
                true
        }

        if [
            "WEB",
            "WEB_SAFARI",
            "GEO",
            "MWEB",
            "ANDROID_VR"
        ].contains(client.profile) {
            if let sts =
                await fetchSignatureTimestampIfNeeded() {
                contentPlaybackContext[
                    "signatureTimestamp"
                ] = sts
            }
        }

        if client.profile == "WEB_EMBED" {
            contentPlaybackContext["referer"] =
                "https://www.youtube.com/watch?v=\(videoID)"
        }

        var playbackContext: [String: Any] = [
            "contentPlaybackContext":
                contentPlaybackContext
        ]

        if client.profile == "TV_DOWNGRADED" {
            playbackContext[
                "devicePlaybackCapabilities"
            ] = [
                "supportsVp9Encoding": true,
                "supportXhr": client.supportXhr
            ]
        }

        var payload: [String: Any] = [
            "context": context,
            "videoId": videoID,
            "racyCheckOk": true,
            "contentCheckOk": true
        ]

        if client.profile != "ANDROID" {
            payload["cpn"] = Self.generateCPN()
            payload["playbackContext"] = playbackContext
        }

        if client.profile == "GEO" {
            // Same geo fallback parameter used by SmartTube QueryBuilder.
            payload["params"] = "CgIQBg%3D%3D"
        }

        let playerEndpoint =
            client.profile == "ANDROID"
                ? "https://youtubei.googleapis.com/youtubei/v1/player"
                : "https://www.youtube.com/youtubei/v1/player"

        guard var components = URLComponents(
            string: playerEndpoint
        ) else {
            return nil
        }

        var queryItems = [
            URLQueryItem(
                name: "prettyPrint",
                value: "false"
            )
        ]

        if let apiKey = client.apiKey {
            queryItems.append(
                URLQueryItem(
                    name: "key",
                    value: apiKey
                )
            )
        }

        components.queryItems =
            queryItems

        guard let url = components.url else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue(
            "application/json",
            forHTTPHeaderField:
                "Content-Type"
        )
        request.setValue(
            client.userAgent,
            forHTTPHeaderField:
                "User-Agent"
        )
        request.setValue(
            client.innerTubeName,
            forHTTPHeaderField:
                "X-Youtube-Client-Name"
        )
        request.setValue(
            client.version,
            forHTTPHeaderField:
                "X-Youtube-Client-Version"
        )

        if let origin = client.origin {
            request.setValue(
                origin,
                forHTTPHeaderField:
                    "Origin"
            )
        }

        if let referer = client.referer {
            request.setValue(
                referer,
                forHTTPHeaderField:
                    "Referer"
            )
        }

        if client.profile != "ANDROID",
           let effectiveVisitor,
           !effectiveVisitor.isEmpty {
            request.setValue(
                effectiveVisitor,
                forHTTPHeaderField:
                    "X-Goog-Visitor-Id"
            )
        }

        request.httpBody =
            try JSONSerialization.data(
                withJSONObject: payload
            )

        let (data, response) =
            try await session.data(
                for: request
            )

        guard let http =
                response as? HTTPURLResponse,
              (200..<300).contains(
                http.statusCode
              ),
              let root =
                try JSONSerialization
                    .jsonObject(
                        with: data
                    ) as? [String: Any] else {
            logger.error(
                "Invalid player response client=\(client.profile, privacy: .public)"
            )
            return nil
        }

        cacheCaptionRenderer(
            from: root,
            videoID: videoID
        )

        let playability =
            root["playabilityStatus"]
                as? [String: Any]
        let status =
            playability?["status"]
                as? String
            ?? "UNKNOWN"
        let reason =
            playability?["reason"]
                as? String
            ?? ""

        let adMetadata =
            AdFilteringPolicy
                .inspectPlayerResponse(
                    root
                )
        let videoDetails =
            root["videoDetails"]
                as? [String: Any]
        let isLive =
            videoDetails?["isLive"]
                as? Bool
            ?? false
        let isLiveContent =
            videoDetails?["isLiveContent"]
                as? Bool
            ?? false

        guard let streaming =
            AdFilteringPolicy
                .contentStreamingData(
                    from: root
                ) else {
            logger.notice(
                "Unplayable client=\(client.profile, privacy: .public) status=\(status, privacy: .public) reason=\(reason, privacy: .public)"
            )

            if let playabilityError =
                StreamResolverError.playabilityError(
                    status: status,
                    reason: reason
                ) {
                throw playabilityError
            }

            return nil
        }

        let allCombined = formats(
            from: streaming["formats"]
        )
        .filter {
            $0.isVideo
                && $0.hasAudio
        }

        let combined = allCombined
            .filter { !$0.requiresPoToken }

        let adaptive = formats(
            from:
                streaming[
                    "adaptiveFormats"
                ]
        )
        .filter { !$0.requiresPoToken }

        let hlsRaw =
            streaming[
                "hlsManifestUrl"
            ] as? String

        let hasReturnedContent =
            !(client.profile == "ANDROID"
                ? allCombined
                : combined).isEmpty
            || !adaptive.isEmpty
            || hlsRaw != nil

        if status != "OK" {
            guard hasReturnedContent else {
                logger.notice(
                    "Unplayable client=\(client.profile, privacy: .public) status=\(status, privacy: .public) reason=\(reason, privacy: .public)"
                )

                if let playabilityError =
                    StreamResolverError.playabilityError(
                        status: status,
                        reason: reason
                    ) {
                    throw playabilityError
                }

                return nil
            }

            // SmartTube's firstPlayable() has a second pass that accepts
            // a response with regular formats even when it is marked
            // unplayable. Preserve that behavior for usable content.
            logger.notice(
                "Using returned content despite status client=\(client.profile, privacy: .public) status=\(status, privacy: .public)"
            )
        }

        let nativeCombined =
            combined.filter {
                $0.isNativeVideo
            }
        let nativeAdaptiveVideo =
            adaptive.filter {
                $0.isNativeVideo
            }

        let qualityFormats: [AlternativeFormat]
        if client.profile == "ANDROID" {
            qualityFormats =
                allCombined.filter {
                    $0.isNativeVideo
                }
        } else {
            qualityFormats =
                nativeCombined
                + nativeAdaptiveVideo
        }

        let availableHeights = Array(
            Set(
                qualityFormats.compactMap {
                    $0.height
                }
            )
        ).sorted(by: >)

        let audios = adaptive
            .filter { $0.isNativeAudio }
            .sorted {
                ($0.bitrate ?? 0)
                    > ($1.bitrate ?? 0)
            }

        let audioTracks =
            playbackAudioTracks(
                from: audios
            )

        let playbackHeaders = PlaybackRequestHeaders(
            userAgent: client.userAgent,
            referer: client.referer,
            origin: client.origin,
            clientProfile: client.profile,
            availableHeights: availableHeights,
            audioTracks: audioTracks,
            isLive: isLive,
            isLiveContent: isLiveContent,
            advertisingMetadataDetected:
                adMetadata
                    .containsAdvertisingMetadata
        )

        logger.notice(
            "Formats client=\(client.profile, privacy: .public) combined=\(combined.count, privacy: .public) combinedAll=\(allCombined.count, privacy: .public) adaptive=\(adaptive.count, privacy: .public) hls=\(hlsRaw != nil, privacy: .public) live=\(isLive, privacy: .public) liveContent=\(isLiveContent, privacy: .public) ads=\(adMetadata.containsAdvertisingMetadata, privacy: .public)"
        )

        // SmartTubeIOS uses standard Android only as the final muxed
        // direct-stream fallback. Do not try its adaptive rqh=1 URLs.
        if client.profile == "ANDROID" {
            guard let muxed = bestCombined(
                allCombined,
                requestedHeight:
                    requestedHeight(
                        for: preferredQuality
                    )
            )?.url else {
                return nil
            }

            return .directWithHeaders(
                muxed,
                playbackHeaders
            )
        }

        // SmartTube routes active live playback through a manifest path.
        // AVPlayer's native HLS implementation is the most reliable equivalent
        // on tvOS, so prefer HLS for any currently-live response before trying
        // separately muxed video/audio tracks.
        if isLive,
           let hlsRaw,
           let hls = URL(string: hlsRaw),
           !adMetadata.containsAdvertisingMetadata {
            logger.notice(
                "Using native HLS live path client=\(client.profile, privacy: .public)"
            )

            return .directWithHeaders(
                hls,
                playbackHeaders
            )
        }

        // On Apple platforms, VisionOS HLS is also the preferred native path
        // for ordinary/past-live content when YouTube returns it.
        if client.profile == "VISIONOS",
           let hlsRaw,
           let hls = URL(string: hlsRaw),
           !adMetadata.containsAdvertisingMetadata {
            return .directWithHeaders(
                hls,
                playbackHeaders
            )
        }

        let fallback = bestCombined(
            combined,
            requestedHeight:
                requestedHeight(
                    for: preferredQuality
                )
        )?.url

        // For normal Auto playback on tvOS prefer YouTube's clean HLS
        // manifest whenever it is available. Long progressive MP4 streams
        // can make AVPlayer inspect/buffer a large part of the file before
        // the first frame. HLS is segmented, so playback can begin after the
        // first few segments and seeking does not depend on already-buffered
        // file ranges.
        if let hlsRaw,
           let hls = URL(string: hlsRaw),
           !adMetadata.containsAdvertisingMetadata {
            logger.notice(
                "FAST_START HLS client=\(client.profile, privacy: .public)"
            )

            return .directWithHeaders(
                hls,
                playbackHeaders
            )
        }

        // Fast-start fallback for responses without a usable HLS manifest.
        // A muxed YouTube format can be handed to AVPlayer immediately.
        // AVPlayer immediately. Separate adaptive video/audio requires us to
        // load both remote assets, inspect their tracks and durations and
        // build an AVMutableComposition before AVPlayer can even start.
        //
        // ExoPlayer (SmartTube) can consume those separate streams directly;
        // AVPlayer cannot. For Auto, prefer the muxed stream and let playback
        // start right away. Explicit quality choices still use adaptive
        // video+audio when needed for 1080p/4K/etc.
        if let fallback {
            logger.notice(
                "FAST_START muxed client=\(client.profile, privacy: .public)"
            )

            return .directWithHeaders(
                fallback,
                playbackHeaders
            )
        }

        let videos =
            nativeAdaptiveVideo
                .sorted(by: videoSort)

        if let audio = audios.first,
           let height =
                requestedHeight(
                    for:
                        preferredQuality
                ),
           let video =
                videos.first(
                    where: {
                        $0.height
                            == height
                    }
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

        // A YouTube response may contain DASH/WebM formats that exist but
        // cannot actually be consumed by AVPlayer on this Apple TV. Treat
        // those as unavailable and allow HLS to rescue the video. Previously
        // the mere presence of any direct format blocked this fallback and
        // produced "No Apple TV-compatible stream" even when HLS existed.
        let hasPlayableDirectContent =
            !nativeCombined.isEmpty
            || (
                !nativeAdaptiveVideo.isEmpty
                && !audios.isEmpty
            )

        logger.notice(
            "Playable formats client=\(client.profile, privacy: .public) nativeCombined=\(nativeCombined.count, privacy: .public) nativeVideo=\(nativeAdaptiveVideo.count, privacy: .public) nativeAudio=\(audios.count, privacy: .public) hls=\(hlsRaw != nil, privacy: .public)"
        )

        if AdFilteringPolicy
            .shouldUseHLSFallback(
                adMetadata: adMetadata,
                hasDirectContentFormats:
                    hasPlayableDirectContent
            ),
           let hlsRaw,
           let hls =
                URL(string: hlsRaw) {
            logger.notice(
                "Using HLS compatibility fallback client=\(client.profile, privacy: .public)"
            )

            return .directWithHeaders(
                hls,
                playbackHeaders
            )
        }

        return nil
    }

    func cachedCaptionRendererData(
        for videoID: String
    ) -> Data? {
        captionRendererCache[videoID]
    }

    private func cacheCaptionRenderer(
        from root: [String: Any],
        videoID: String
    ) {
        guard let captions =
                root["captions"]
                    as? [String: Any],
              let renderer =
                captions[
                    "playerCaptionsTracklistRenderer"
                ] as? [String: Any],
              JSONSerialization
                .isValidJSONObject(renderer),
              let data =
                try? JSONSerialization.data(
                    withJSONObject: renderer
                )
        else {
            return
        }

        if captionRendererCache.count >= 16,
           captionRendererCache[videoID] == nil {
            captionRendererCache.removeAll(
                keepingCapacity: true
            )
        }

        captionRendererCache[videoID] = data

        let trackCount =
            (renderer["captionTracks"]
                as? [[String: Any]])?.count
            ?? 0
        let translationCount =
            (renderer["translationLanguages"]
                as? [[String: Any]])?.count
            ?? 0

        logger.notice(
            "Cached captions video=\(videoID, privacy: .public) tracks=\(trackCount, privacy: .public) translations=\(translationCount, privacy: .public)"
        )
    }

    private func clientFields(
        for client: AlternativePlayerClient
    ) -> [String: Any] {
        var fields: [String: Any]

        switch client.profile {
        case "VISIONOS":
            fields = [
                "clientName": client.name,
                "clientVersion": client.version,
                "deviceMake": "Apple",
                "deviceModel": "RealityDevice17,1",
                "userAgent": client.userAgent,
                "osName": "visionOS",
                "osVersion": "26.5.23O471"
            ]

        case "ANDROID_VR":
            fields = [
                "clientName": client.name,
                "clientVersion": client.version,
                "deviceMake": "Oculus",
                "deviceModel": "Quest 3",
                "androidSdkVersion": 32,
                "userAgent": client.userAgent,
                "osName": "Android",
                "osVersion": "12L"
            ]

        case "ANDROID":
            fields = [
                "hl": "en",
                "gl": "US",
                "clientName": client.name,
                "clientVersion": client.version,
                "androidSdkVersion": 30,
                "osName": "Android",
                "osVersion": "11"
            ]

        case "WEB", "WEB_SAFARI", "GEO":
            fields = [
                "hl": L10n.currentLanguageCode,
                "timeZone": "UTC",
                "utcOffsetMinutes": 0,
                "clientName": client.name,
                "clientVersion": client.version,
                "userAgent": client.userAgent
            ]

        case "MWEB":
            fields = [
                "hl": L10n.currentLanguageCode,
                "gl": "CZ",
                "clientName": client.name,
                "clientVersion": client.version,
                "clientScreen": "WATCH"
            ]

        case "WEB_EMBED":
            fields = [
                "hl": L10n.currentLanguageCode,
                "gl": "CZ",
                "clientName": client.name,
                "clientVersion": client.version,
                "clientScreen": "EMBED"
            ]

        default:
            fields = [
                "hl": L10n.currentLanguageCode,
                "gl": "CZ",
                "clientName": client.name,
                "clientVersion": client.version,
                "clientScreen": client.clientScreen,
                "userAgent": client.userAgent
            ]
        }

        for (key, value) in client.extraClientFields {
            if fields[key] == nil {
                fields[key] = value
            }
        }

        return fields
    }

    private func fetchSignatureTimestampIfNeeded()
        async -> Int? {
        if let signatureTimestamp,
           let signatureTimestampFetchedAt,
           Date().timeIntervalSince(
            signatureTimestampFetchedAt
           ) < 3600 {
            return signatureTimestamp
        }

        guard let url =
            URL(string: "https://www.youtube.com/")
        else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.5 Safari/605.1.15,gzip(gfe)",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, response) =
                try await session.data(for: request)

            guard let http =
                    response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let html =
                    String(
                        data: data,
                        encoding: .utf8
                    ) else {
                return nil
            }

            let pattern =
                #""STS"\s*:\s*(\d+)"#

            guard let regex =
                    try? NSRegularExpression(
                        pattern: pattern
                    ),
                  let match =
                    regex.firstMatch(
                        in: html,
                        range: NSRange(
                            html.startIndex...,
                            in: html
                        )
                    ),
                  let range =
                    Range(
                        match.range(at: 1),
                        in: html
                    ),
                  let value =
                    Int(html[range]) else {
                logger.notice(
                    "STS not found"
                )
                return nil
            }

            signatureTimestamp = value
            signatureTimestampFetchedAt =
                Date()

            logger.notice(
                "STS fetched value=\(value, privacy: .public)"
            )
            return value
        } catch {
            logger.notice(
                "STS request failed error=\(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    private static func extractVisitorData(
        from html: String
    ) -> String? {
        let patterns = [
            #""VISITOR_DATA"\s*:\s*"([^"]+)""#,
            #""visitorData"\s*:\s*"([^"]+)""#
        ]

        for pattern in patterns {
            guard let regex =
                    try? NSRegularExpression(
                        pattern: pattern
                    ),
                  let match =
                    regex.firstMatch(
                        in: html,
                        range: NSRange(
                            html.startIndex...,
                            in: html
                        )
                    ),
                  let range =
                    Range(
                        match.range(at: 1),
                        in: html
                    ) else {
                continue
            }

            let encoded =
                String(html[range])

            if let data =
                "\"\(encoded)\""
                    .data(
                        using: .utf8
                    ),
               let decoded =
                try? JSONDecoder()
                    .decode(
                        String.self,
                        from: data
                    ),
               !decoded.isEmpty {
                return decoded
            }

            return encoded
                .replacingOccurrences(
                    of: #"\u003d"#,
                    with: "="
                )
        }

        return nil
    }

    private func formats(
        from value: Any?
    ) -> [AlternativeFormat] {
        guard let list =
                value as? [[String: Any]]
        else {
            return []
        }

        return list.compactMap {
            item in
            guard let rawURL =
                    item["url"] as? String,
                  let url =
                    URL(string: rawURL),
                  let mime =
                    item["mimeType"]
                        as? String else {
                return nil
            }

            let audioTrack =
                item["audioTrack"]
                    as? [String: Any]

            return AlternativeFormat(
                url: url,
                mimeType: mime,
                height:
                    item["height"] as? Int,
                fps:
                    item["fps"] as? Int,
                bitrate:
                    item["bitrate"] as? Int,
                hasAudio:
                    item["audioQuality"]
                        != nil
                    || item["audioChannels"]
                        != nil,
                audioTrackID:
                    audioTrack?["id"]
                        as? String,
                audioTrackDisplayName:
                    audioTrack?["displayName"]
                        as? String,
                audioIsDefault:
                    audioTrack?["audioIsDefault"]
                        as? Bool
                    ?? false,
                isAutoDubbed:
                    audioTrack?["isAutoDubbed"]
                        as? Bool
                    ?? false,
                isHDR: Self.isHDRFormat(
                    item
                )
            )
        }
    }

    private func playbackAudioTracks(
        from formats: [AlternativeFormat]
    ) -> [PlaybackAudioTrack] {
        var seen = Set<String>()
        var tracks: [PlaybackAudioTrack] = []

        for format in formats {
            guard let trackID =
                    format.audioTrackID,
                  !trackID.isEmpty,
                  seen.insert(trackID)
                    .inserted else {
                continue
            }

            let parts = trackID.split(
                separator: ".",
                omittingEmptySubsequences:
                    false
            )
            let languageCode =
                parts.first.map(String.init)
                ?? trackID

            // SmartTube uses ".4" for the
            // original YouTube audio track.
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
                    languageCode:
                        languageCode,
                    isDefault:
                        format.audioIsDefault,
                    isOriginal:
                        isOriginal,
                    isAutoDubbed:
                        format.isAutoDubbed,
                    url: format.url
                )
            )
        }

        return tracks
    }

    private func bestCombined(
        _ formats: [AlternativeFormat],
        requestedHeight: Int?
    ) -> AlternativeFormat? {
        let native = formats.filter {
            $0.mimeType.hasPrefix(
                "video/mp4"
            )
        }

        if let requestedHeight {
            return native
                .filter {
                    $0.height
                        == requestedHeight
                }
                .max {
                    if ($0.fps ?? 0)
                        != ($1.fps ?? 0) {
                        return ($0.fps ?? 0)
                            < ($1.fps ?? 0)
                    }

                    if $0.isHDR != $1.isHDR {
                        if AVPlayer.eligibleForHDRPlayback {
                            return !$0.isHDR
                        }

                        return $0.isHDR
                    }

                    if $0.codecPriority
                        != $1.codecPriority {
                        return $0.codecPriority
                            > $1.codecPriority
                    }

                    return ($0.bitrate ?? 0)
                        < ($1.bitrate ?? 0)
                }
        }

        return native.max {
            let leftHeight =
                $0.height ?? 0
            let rightHeight =
                $1.height ?? 0

            if leftHeight
                != rightHeight {
                return leftHeight
                    < rightHeight
            }

            let leftFPS = $0.fps ?? 0
            let rightFPS = $1.fps ?? 0

            if leftFPS != rightFPS {
                return leftFPS < rightFPS
            }

            if $0.isHDR != $1.isHDR {
                if AVPlayer.eligibleForHDRPlayback {
                    return !$0.isHDR
                }

                return $0.isHDR
            }

            if $0.codecPriority
                != $1.codecPriority {
                return $0.codecPriority
                    > $1.codecPriority
            }

            return ($0.bitrate ?? 0)
                < ($1.bitrate ?? 0)
        }
    }

    private func videoSort(
        _ lhs: AlternativeFormat,
        _ rhs: AlternativeFormat
    ) -> Bool {
        let leftHeight =
            lhs.height ?? 0
        let rightHeight =
            rhs.height ?? 0

        if leftHeight != rightHeight {
            return leftHeight
                > rightHeight
        }

        let leftFPS = lhs.fps ?? 0
        let rightFPS = rhs.fps ?? 0

        if leftFPS != rightFPS {
            return leftFPS
                > rightFPS
        }

        if lhs.isHDR != rhs.isHDR {
            if AVPlayer.eligibleForHDRPlayback {
                return lhs.isHDR
            }

            return !lhs.isHDR
        }

        if lhs.codecPriority
            != rhs.codecPriority {
            return lhs.codecPriority
                < rhs.codecPriority
        }

        return (lhs.bitrate ?? 0)
            > (rhs.bitrate ?? 0)
    }

    private static func isHDRFormat(
        _ item: [String: Any]
    ) -> Bool {
        if let colorInfo =
                item["colorInfo"]
                    as? [String: Any] {
            let text =
                colorInfo.description
                    .lowercased()

            if text.contains("2084")
                || text.contains("2100")
                || text.contains("hdr")
                || text.contains("hlg")
                || text.contains("pq") {
                return true
            }
        }

        if let mime =
                item["mimeType"] as? String {
            let lowered =
                mime.lowercased()

            if lowered.contains("dvh1")
                || lowered.contains("dvhe") {
                return true
            }
        }

        return false
    }

    private func requestedHeight(
        for preference: String
    ) -> Int? {
        guard preference.hasSuffix("p") else {
            return nil
        }

        return Int(preference.dropLast())
    }

    private static func generateCPN()
        -> String {
        let alphabet = Array(
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
        )
        var generator =
            SystemRandomNumberGenerator()

        return String(
            (0..<16).map { _ in
                alphabet.randomElement(
                    using: &generator
                ) ?? "A"
            }
        )
    }
}
