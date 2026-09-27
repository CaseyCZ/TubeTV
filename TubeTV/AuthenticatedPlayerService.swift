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
            return "YouTube účet není přihlášen."
        case .invalidResponse:
            return "YouTube player vrátil neplatnou odpověď."
        case .unplayable(let reason):
            return reason.isEmpty
                ? "Video není pro tento účet dostupné."
                : reason
        case .noPlayableStream:
            return "Přihlášený YouTube player nevrátil stream vhodný pro Apple TV."
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

        var client: [String: Any] = [
            "clientName": SmartTubeAuthService.tvClientName,
            "clientVersion": SmartTubeAuthService.tvClientVersion,
            "clientScreen": "WATCH",
            "userAgent": SmartTubeAuthService.tvUserAgent,
            "acceptLanguage": "cs",
            "acceptRegion": "CZ",
            "utcOffsetMinutes": offsetMinutes,
            "platform": "TV",
            "originalUrl": SmartTubeAuthService.tvReferer
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
            "contentCheckOk": true
        ]

        var request = URLRequest(
            url: URL(
                string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false"
            )!
        )
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            SmartTubeAuthService.tvUserAgent,
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(
            SmartTubeAuthService.tvReferer,
            forHTTPHeaderField: "Referer"
        )
        request.setValue(
            authorization,
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("7", forHTTPHeaderField: "X-Youtube-Client-Name")
        request.setValue(
            SmartTubeAuthService.tvClientVersion,
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

        if let playability = root["playabilityStatus"] as? [String: Any],
           let status = playability["status"] as? String,
           status != "OK" {
            let reason = playability["reason"] as? String ?? ""
            throw AuthenticatedPlayerError.unplayable(reason)
        }

        guard let streaming = root["streamingData"] as? [String: Any] else {
            throw AuthenticatedPlayerError.noPlayableStream
        }

        if preferredQuality == "Auto",
           let hls = streaming["hlsManifestUrl"] as? String,
           let hlsURL = URL(string: hls) {
            return .direct(hlsURL)
        }

        let combined = Self.formats(
            from: streaming["formats"]
        )
        .filter { $0.isVideo && $0.hasAudio }

        let adaptive = Self.formats(
            from: streaming["adaptiveFormats"]
        )

        let fallback = Self.bestCombined(
            combined,
            requestedHeight: Self.requestedHeight(for: preferredQuality)
        )?.url

        let videos = adaptive
            .filter { $0.isAppleFriendlyVideo }
            .sorted(by: Self.videoSort)

        let audios = adaptive
            .filter { $0.isAppleFriendlyAudio }
            .sorted {
                ($0.bitrate ?? 0) > ($1.bitrate ?? 0)
            }

        if let audio = audios.first {
            if let height = Self.requestedHeight(for: preferredQuality),
               let video = videos.first(where: { $0.height == height }) {
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

        if let hls = streaming["hlsManifestUrl"] as? String,
           let hlsURL = URL(string: hls) {
            return .direct(hlsURL)
        }

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

            return InnerTubeFormat(
                url: url,
                mimeType: mimeType,
                height: item["height"] as? Int,
                fps: item["fps"] as? Int,
                bitrate: item["bitrate"] as? Int,
                hasAudio: item["audioQuality"] != nil
                    || item["audioChannels"] != nil,
                isHDR: Self.isHDRFormat(item)
            )
        }
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
            .max(by: { ($0.bitrate ?? 0) < ($1.bitrate ?? 0) }) {
            return exact
        }

        return appleFormats.max {
            let leftHeight = $0.height ?? 0
            let rightHeight = $1.height ?? 0

            if leftHeight == rightHeight {
                return ($0.bitrate ?? 0) < ($1.bitrate ?? 0)
            }

            return leftHeight < rightHeight
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

    private static func generateCPN() -> String {
        let alphabet = Array(
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
        )
        var generator = SystemRandomNumberGenerator()

        return String(
            (0..<16).map { _ in
                alphabet.randomElement(using: &generator)!
            }
        )
    }
}
