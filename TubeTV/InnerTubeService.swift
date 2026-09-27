import Foundation

struct YouTubePlaylistItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let thumbnailURL: URL?
}

enum AccountFeedKind: String, CaseIterable, Identifiable {
    case subscriptions = "Odběry"
    case history = "Historie"

    var id: String { rawValue }

    var browseID: String {
        switch self {
        case .subscriptions:
            return "FEsubscriptions"
        case .history:
            return "FEhistory"
        }
    }

    var icon: String {
        switch self {
        case .subscriptions:
            return "person.2.fill"
        case .history:
            return "clock.arrow.circlepath"
        }
    }
}

enum InnerTubeError: LocalizedError {
    case invalidResponse
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "YouTube účet vrátil neplatnou odpověď."
        case .notSignedIn:
            return "Pro tuto část se nejdřív přihlas k YouTube."
        }
    }
}

actor InnerTubeService {
    static let shared = InnerTubeService()

    func homeVideos() async throws -> [VideoItem] {
        let root = try await browse("default")
        return Self.extractVideos(from: root)
    }

    func videos(for kind: AccountFeedKind) async throws -> [VideoItem] {
        let root = try await browse(kind.browseID)
        return Self.extractVideos(from: root)
    }

    func playlists() async throws -> [YouTubePlaylistItem] {
        let root = try await browse("FEplaylist_aggregation")
        return Self.extractPlaylists(from: root)
    }

    func playlistVideos(_ playlistID: String) async throws -> [VideoItem] {
        let browseID = playlistID.hasPrefix("VL")
            ? playlistID
            : "VL\(playlistID)"

        let root = try await browse(browseID)
        return Self.extractVideos(from: root)
    }

    private func browse(_ browseID: String) async throws -> Any {
        guard await SmartTubeAuthService.shared.signedIn() else {
            throw InnerTubeError.notSignedIn
        }

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
            "utcOffsetMinutes": offsetMinutes,
            "webpSupport": false,
            "animatedWebpSupport": true,
            "tvAppInfo": [
                "appQuality": "TV_APP_QUALITY_FULL_ANIMATION",
                "zylonLeftNav": true
            ]
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
            "racyCheckOk": true,
            "contentCheckOk": true,
            "browseId": browseID
        ]

        var components = URLComponents(
            string: "https://www.youtube.com/youtubei/v1/browse"
        )!
        components.queryItems = [
            URLQueryItem(name: "prettyPrint", value: "false")
        ]

        var request = URLRequest(url: components.url!)
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
              (200..<300).contains(http.statusCode) else {
            throw InnerTubeError.invalidResponse
        }

        return try JSONSerialization.jsonObject(with: data)
    }

    private static func extractVideos(from root: Any) -> [VideoItem] {
        var candidates: [[String: Any]] = []
        collectDictionaries(from: root, into: &candidates)

        var seen = Set<String>()
        var result: [VideoItem] = []

        for dictionary in candidates {
            guard let videoID = firstString(
                in: dictionary,
                keys: ["videoId", "video_id"]
            ),
            videoID.count == 11,
            seen.insert(videoID).inserted else {
                continue
            }

            let title = firstText(
                in: dictionary,
                keys: ["title", "headline", "primaryText"]
            ) ?? "YouTube video"

            let channel = firstText(
                in: dictionary,
                keys: [
                    "ownerText",
                    "longBylineText",
                    "shortBylineText",
                    "secondaryText",
                    "byline"
                ]
            ) ?? "YouTube"

            let duration = firstText(
                in: dictionary,
                keys: ["lengthText", "durationText"]
            )

            let metadata = firstText(
                in: dictionary,
                keys: [
                    "publishedTimeText",
                    "viewCountText",
                    "metadataText",
                    "subtitle"
                ]
            )

            let subtitle = [metadata, duration]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " • ")

            let thumbnailURL =
                firstThumbnailURL(in: dictionary)
                ?? URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg")

            result.append(
                VideoItem(
                    id: "youtube-\(videoID)",
                    title: title,
                    channel: channel,
                    subtitle: subtitle,
                    thumbnailURL: thumbnailURL,
                    youtubeVideoID: videoID
                )
            )

            if result.count >= 100 {
                break
            }
        }

        return result
    }

    private static func extractPlaylists(
        from root: Any
    ) -> [YouTubePlaylistItem] {
        var candidates: [[String: Any]] = []
        collectDictionaries(from: root, into: &candidates)

        var seen = Set<String>()
        var result: [YouTubePlaylistItem] = []

        for dictionary in candidates {
            guard let playlistID = firstString(
                in: dictionary,
                keys: ["playlistId", "playlist_id"]
            ),
            !playlistID.isEmpty,
            seen.insert(playlistID).inserted else {
                continue
            }

            let title = firstText(
                in: dictionary,
                keys: ["title", "headline", "primaryText"]
            ) ?? "Playlist"

            let subtitle = firstText(
                in: dictionary,
                keys: [
                    "videoCountText",
                    "shortBylineText",
                    "secondaryText",
                    "subtitle"
                ]
            ) ?? ""

            result.append(
                YouTubePlaylistItem(
                    id: playlistID,
                    title: title,
                    subtitle: subtitle,
                    thumbnailURL: firstThumbnailURL(in: dictionary)
                )
            )

            if result.count >= 100 {
                break
            }
        }

        return result
    }

    private static func collectDictionaries(
        from node: Any,
        into output: inout [[String: Any]]
    ) {
        if let dictionary = node as? [String: Any] {
            output.append(dictionary)

            for value in dictionary.values {
                collectDictionaries(from: value, into: &output)
            }
        } else if let array = node as? [Any] {
            for value in array {
                collectDictionaries(from: value, into: &output)
            }
        }
    }

    private static func firstString(
        in dictionary: [String: Any],
        keys: [String]
    ) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String,
               !value.isEmpty {
                return value
            }
        }

        return nil
    }

    private static func firstText(
        in dictionary: [String: Any],
        keys: [String]
    ) -> String? {
        for key in keys {
            if let value = dictionary[key],
               let text = text(from: value),
               !text.isEmpty {
                return text
            }
        }

        return nil
    }

    private static func text(from value: Any) -> String? {
        if let string = value as? String {
            return string
        }

        if let dictionary = value as? [String: Any] {
            if let simpleText = dictionary["simpleText"] as? String {
                return simpleText
            }

            if let runs = dictionary["runs"] as? [[String: Any]] {
                let joined = runs
                    .compactMap { $0["text"] as? String }
                    .joined()

                if !joined.isEmpty {
                    return joined
                }
            }

            if let content = dictionary["content"] as? String {
                return content
            }

            for nestedKey in [
                "text",
                "title",
                "primaryText",
                "secondaryText",
                "headline",
                "subtitle"
            ] {
                if let nested = dictionary[nestedKey],
                   let nestedText = text(from: nested),
                   !nestedText.isEmpty {
                    return nestedText
                }
            }
        }

        return nil
    }

    private static func firstThumbnailURL(
        in dictionary: [String: Any]
    ) -> URL? {
        if let direct = thumbnailURL(from: dictionary["thumbnail"]) {
            return direct
        }

        for key in [
            "thumbnail",
            "thumbnails",
            "image",
            "contentImage",
            "avatar"
        ] {
            if let value = dictionary[key],
               let url = thumbnailURL(from: value) {
                return url
            }
        }

        return nil
    }

    private static func thumbnailURL(from value: Any?) -> URL? {
        guard let value else { return nil }

        if let string = value as? String {
            return URL(string: string)
        }

        if let dictionary = value as? [String: Any] {
            if let url = dictionary["url"] as? String,
               let parsed = URL(string: url) {
                return parsed
            }

            if let thumbnails = dictionary["thumbnails"] as? [[String: Any]] {
                for item in thumbnails.reversed() {
                    if let raw = item["url"] as? String,
                       let url = URL(string: raw) {
                        return url
                    }
                }
            }

            for nested in dictionary.values {
                if let url = thumbnailURL(from: nested) {
                    return url
                }
            }
        }

        if let array = value as? [Any] {
            for item in array.reversed() {
                if let url = thumbnailURL(from: item) {
                    return url
                }
            }
        }

        return nil
    }
}
