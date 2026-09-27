import Foundation

struct YouTubeTrackingContext: Hashable {
    let videoID: String
    let cpn: String
    let eventID: String
    let visitorMonitoringData: String
    let ofParam: String
    let visitorData: String?
}

enum YouTubeTrackingError: LocalizedError {
    case invalidPlayerResponse
    case trackingDataUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidPlayerResponse:
            return "YouTube nevrátil platná player data pro historii."
        case .trackingDataUnavailable:
            return "YouTube nevrátil tracking parametry pro historii."
        }
    }
}

actor YouTubeTrackingService {
    static let shared = YouTubeTrackingService()

    private var lastPositions: [String: (position: Double, timestamp: Date)] = [:]

    func makeContext(videoID: String) async throws -> YouTubeTrackingContext {
        let cpn = Self.generateCPN()
        let bootstrap = try await SmartTubeAuthService.shared.bootstrap()
        let authorization = try await SmartTubeAuthService.shared.authorizationHeader()
        let offsetMinutes = TimeZone.current.secondsFromGMT() / 60

        var client: [String: Any] = [
            "clientName": SmartTubeAuthService.tvClientName,
            "clientVersion": SmartTubeAuthService.tvClientVersion,
            "clientScreen": "WATCH",
            "userAgent": SmartTubeAuthService.tvUserAgent,
            "acceptLanguage": "cs",
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
            "contentCheckOk": true
        ]

        var request = URLRequest(
            url: URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false")!
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

        if let pageID = await SmartTubeAuthService.shared.selectedPageID(),
           !pageID.isEmpty {
            request.setValue(
                pageID,
                forHTTPHeaderField: "X-Goog-Pageid"
            )
        }

        request.setValue("7", forHTTPHeaderField: "X-Youtube-Client-Name")
        request.setValue(
            SmartTubeAuthService.tvClientVersion,
            forHTTPHeaderField: "X-Youtube-Client-Version"
        )

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
            throw YouTubeTrackingError.invalidPlayerResponse
        }

        guard let playbackTracking = root["playbackTracking"] as? [String: Any],
              let watchTime = playbackTracking["videostatsWatchtimeUrl"] as? [String: Any],
              let baseURL = watchTime["baseUrl"] as? String,
              let components = URLComponents(string: baseURL) else {
            throw YouTubeTrackingError.trackingDataUnavailable
        }

        var query: [String: String] = [:]

        for item in components.queryItems ?? [] {
            if let value = item.value {
                query[item.name] = value
            }
        }

        guard let eventID = query["ei"],
              let vm = query["vm"],
              let of = query["of"],
              !eventID.isEmpty,
              !vm.isEmpty,
              !of.isEmpty else {
            throw YouTubeTrackingError.trackingDataUnavailable
        }

        return YouTubeTrackingContext(
            videoID: videoID,
            cpn: cpn,
            eventID: eventID,
            visitorMonitoringData: vm,
            ofParam: of,
            visitorData: bootstrap.visitorData
        )
    }

    func update(
        context: YouTubeTrackingContext,
        position: Double,
        duration: Double,
        final: Bool = false
    ) async {
        guard position.isFinite,
              duration.isFinite,
              duration > 0,
              position >= 0 else {
            return
        }

        do {
            let authorization = try await SmartTubeAuthService.shared.authorizationHeader()

            let previous = lastPositions[context.videoID]
            let oldPosition: Double

            if let previous,
               Date().timeIntervalSince(previous.timestamp) < 30 * 60 {
                oldPosition = previous.position
            } else {
                oldPosition = position < 180 ? 0 : position
                try await createRecord(
                    context: context,
                    position: oldPosition,
                    duration: duration,
                    authorization: authorization,
                    final: final
                )
            }

            let almostFinished = duration - position < duration * 0.05
            let shouldFinish = final || almostFinished

            if shouldFinish {
                try await createRecord(
                    context: context,
                    position: duration,
                    duration: duration,
                    authorization: authorization,
                    final: true
                )
            }

            try await updateWatchTime(
                context: context,
                oldPosition: shouldFinish ? duration : oldPosition,
                position: shouldFinish ? duration : position,
                duration: duration,
                authorization: authorization,
                final: shouldFinish
            )

            lastPositions[context.videoID] = (
                shouldFinish ? duration : position,
                Date()
            )
        } catch {
            // History tracking must never interrupt playback.
        }
    }

    func reset(videoID: String) {
        lastPositions.removeValue(forKey: videoID)
    }

    private func createRecord(
        context: YouTubeTrackingContext,
        position: Double,
        duration: Double,
        authorization: String,
        final: Bool
    ) async throws {
        var components = URLComponents(
            string: "https://www.youtube.com/api/stats/playback"
        )!

        var items = [
            URLQueryItem(name: "ns", value: "yt"),
            URLQueryItem(name: "ver", value: "2"),
            URLQueryItem(name: "docid", value: context.videoID),
            URLQueryItem(name: "len", value: Self.number(duration)),
            URLQueryItem(name: "cmt", value: Self.number(position)),
            URLQueryItem(name: "cpn", value: context.cpn),
            URLQueryItem(name: "ei", value: context.eventID),
            URLQueryItem(name: "vm", value: context.visitorMonitoringData),
            URLQueryItem(name: "of", value: context.ofParam)
        ]

        if final {
            items.append(URLQueryItem(name: "final", value: "1"))
        }

        components.queryItems = items
        try await performTrackingRequest(
            url: components.url!,
            authorization: authorization,
            visitorData: context.visitorData
        )
    }

    private func updateWatchTime(
        context: YouTubeTrackingContext,
        oldPosition: Double,
        position: Double,
        duration: Double,
        authorization: String,
        final: Bool
    ) async throws {
        var components = URLComponents(
            string: "https://www.youtube.com/api/stats/watchtime"
        )!

        var items = [
            URLQueryItem(name: "ns", value: "yt"),
            URLQueryItem(name: "ver", value: "2"),
            URLQueryItem(name: "docid", value: context.videoID),
            URLQueryItem(name: "len", value: Self.number(duration)),
            URLQueryItem(name: "st", value: Self.number(oldPosition)),
            URLQueryItem(name: "et", value: Self.number(position)),
            URLQueryItem(name: "cmt", value: Self.number(position)),
            URLQueryItem(name: "cpn", value: context.cpn),
            URLQueryItem(name: "ei", value: context.eventID),
            URLQueryItem(name: "vm", value: context.visitorMonitoringData),
            URLQueryItem(name: "of", value: context.ofParam)
        ]

        if final {
            items.append(URLQueryItem(name: "final", value: "1"))
        }

        components.queryItems = items
        try await performTrackingRequest(
            url: components.url!,
            authorization: authorization,
            visitorData: context.visitorData
        )
    }

    private func performTrackingRequest(
        url: URL,
        authorization: String,
        visitorData: String?
    ) async throws {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
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

        if let pageID = await SmartTubeAuthService.shared.selectedPageID(),
           !pageID.isEmpty {
            request.setValue(
                pageID,
                forHTTPHeaderField: "X-Goog-Pageid"
            )
        }

        if let visitorData, !visitorData.isEmpty {
            request.setValue(
                visitorData,
                forHTTPHeaderField: "X-Goog-Visitor-Id"
            )
        }

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200..<400).contains(http.statusCode) else {
            throw YouTubeTrackingError.invalidPlayerResponse
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

    private static func number(_ value: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
