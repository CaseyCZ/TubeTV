import AVFoundation
import Foundation
import VideoToolbox

private struct AlternativePlayerClient {
    let name: String
    let version: String
    let userAgent: String
    let extraClientFields: [String: Any]
}

private struct AlternativeFormat {
    let url: URL
    let mimeType: String
    let height: Int?
    let fps: Int?
    let bitrate: Int?
    let hasAudio: Bool

    var isVideo: Bool {
        mimeType.hasPrefix("video/")
    }

    var isAudio: Bool {
        mimeType.hasPrefix("audio/")
    }

    var isNativeVideo: Bool {
        guard isVideo else { return false }

        if mimeType.contains("avc1") {
            return VTIsHardwareDecodeSupported(kCMVideoCodecType_H264)
        }

        if mimeType.contains("hvc1") || mimeType.contains("hev1") {
            return VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
        }

        if mimeType.contains("av01") {
            return VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)
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
}

actor AlternativePlayerService {
    static let shared = AlternativePlayerService()

    private let clients: [AlternativePlayerClient] = [
        AlternativePlayerClient(
            name: "VISIONOS",
            version: "1.02",
            userAgent:
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15",
            extraClientFields: [
                "deviceMake": "Apple",
                "deviceModel": "RealityDevice17,1",
                "osName": "visionOS",
                "osVersion": "26.5.23O471"
            ]
        ),
        AlternativePlayerClient(
            name: "ANDROID_VR",
            version: "1.65.10",
            userAgent:
                "com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip",
            extraClientFields: [
                "androidSdkVersion": 32,
                "osName": "Android",
                "osVersion": "12",
                "deviceMake": "Oculus",
                "deviceModel": "Quest 3"
            ]
        ),
        AlternativePlayerClient(
            name: "iOS",
            version: "21.26.4",
            userAgent:
                "com.google.ios.youtube/21.26.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)",
            extraClientFields: [
                "deviceMake": "Apple",
                "deviceModel": "iPhone16,2",
                "osName": "iPhone",
                "osVersion": "18.3.2.22D82"
            ]
        )
    ]

    func resolve(
        videoID: String,
        preferredQuality: String
    ) async throws -> PlaybackSource {
        var lastError: Error = StreamResolverError.noPlayableStream

        for client in clients {
            do {
                if let source = try await resolve(
                    videoID: videoID,
                    preferredQuality: preferredQuality,
                    client: client
                ) {
                    return source
                }
            } catch {
                lastError = error
            }
        }

        throw lastError
    }

    private func resolve(
        videoID: String,
        preferredQuality: String,
        client: AlternativePlayerClient
    ) async throws -> PlaybackSource? {
        var clientFields: [String: Any] = [
            "clientName": client.name,
            "clientVersion": client.version,
            "userAgent": client.userAgent,
            "acceptLanguage": "cs",
            "acceptRegion": "CZ",
            "utcOffsetMinutes": TimeZone.current.secondsFromGMT() / 60
        ]

        for (key, value) in client.extraClientFields {
            clientFields[key] = value
        }

        let payload: [String: Any] = [
            "context": [
                "client": clientFields,
                "user": [
                    "enableSafetyMode": false,
                    "lockedSafetyMode": false
                ]
            ],
            "videoId": videoID,
            "racyCheckOk": true,
            "contentCheckOk": true,
            "playbackContext": [
                "contentPlaybackContext": [
                    "html5Preference": "HTML5_PREF_WANTS"
                ]
            ]
        ]

        var request = URLRequest(
            url: URL(
                string:
                    "https://www.youtube.com/youtubei/v1/player?prettyPrint=false"
            )!
        )
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue(
            client.userAgent,
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(
            client.name,
            forHTTPHeaderField: "X-Youtube-Client-Name"
        )
        request.setValue(
            client.version,
            forHTTPHeaderField: "X-Youtube-Client-Version"
        )
        request.httpBody = try JSONSerialization.data(
            withJSONObject: payload
        )

        let (data, response) = try await URLSession.shared.data(
            for: request
        )

        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let root = try JSONSerialization.jsonObject(
                with: data
              ) as? [String: Any] else {
            return nil
        }

        if let playability = root["playabilityStatus"] as? [String: Any],
           let status = playability["status"] as? String,
           status != "OK" {
            return nil
        }

        let adMetadata =
            AdFilteringPolicy.inspectPlayerResponse(root)

        guard let streaming =
            AdFilteringPolicy.contentStreamingData(from: root) else {
            return nil
        }

        let combined = formats(
            from: streaming["formats"]
        )
        .filter { $0.isVideo && $0.hasAudio }

        let adaptive = formats(
            from: streaming["adaptiveFormats"]
        )

        let fallback = bestCombined(
            combined,
            requestedHeight: requestedHeight(
                for: preferredQuality
            )
        )?.url

        let videos = adaptive
            .filter { $0.isNativeVideo }
            .sorted(by: videoSort)

        let audios = adaptive
            .filter { $0.isNativeAudio }
            .sorted {
                ($0.bitrate ?? 0) > ($1.bitrate ?? 0)
            }

        if let audio = audios.first {
            if let height = requestedHeight(
                for: preferredQuality
            ),
            let video = videos.first(
                where: { $0.height == height }
            ) {
                return .adaptive(
                    video: video.url,
                    audio: audio.url,
                    fallback: fallback
                )
            }

            if preferredQuality == "Auto",
               let video = videos.first {
                return .adaptive(
                    video: video.url,
                    audio: audio.url,
                    fallback: fallback
                )
            }
        }

        if let fallback {
            return .direct(fallback)
        }

        let hasDirectContent =
            !combined.isEmpty || !adaptive.isEmpty

        if AdFilteringPolicy.shouldUseHLSFallback(
            adMetadata: adMetadata,
            hasDirectContentFormats: hasDirectContent
        ),
        let rawHLS = streaming["hlsManifestUrl"] as? String,
        let hls = URL(string: rawHLS) {
            return .direct(hls)
        }

        return nil
    }

    private func formats(
        from value: Any?
    ) -> [AlternativeFormat] {
        guard let list = value as? [[String: Any]] else {
            return []
        }

        return list.compactMap { item in
            guard let rawURL = item["url"] as? String,
                  let url = URL(string: rawURL),
                  let mime = item["mimeType"] as? String else {
                return nil
            }

            return AlternativeFormat(
                url: url,
                mimeType: mime,
                height: item["height"] as? Int,
                fps: item["fps"] as? Int,
                bitrate: item["bitrate"] as? Int,
                hasAudio:
                    item["audioQuality"] != nil
                    || item["audioChannels"] != nil
            )
        }
    }

    private func bestCombined(
        _ formats: [AlternativeFormat],
        requestedHeight: Int?
    ) -> AlternativeFormat? {
        let native = formats.filter {
            $0.mimeType.hasPrefix("video/mp4")
        }

        if let requestedHeight {
            return native
                .filter { $0.height == requestedHeight }
                .max {
                    ($0.bitrate ?? 0)
                        < ($1.bitrate ?? 0)
                }
        }

        return native.max {
            let leftHeight = $0.height ?? 0
            let rightHeight = $1.height ?? 0

            if leftHeight != rightHeight {
                return leftHeight < rightHeight
            }

            return ($0.bitrate ?? 0)
                < ($1.bitrate ?? 0)
        }
    }

    private func videoSort(
        _ lhs: AlternativeFormat,
        _ rhs: AlternativeFormat
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

        return ($0.bitrate ?? 0) > ($1.bitrate ?? 0)
    }

    private func requestedHeight(
        for preference: String
    ) -> Int? {
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
}
