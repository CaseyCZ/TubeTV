import Foundation

struct YouTubePlaylistItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let thumbnailURL: URL?
}

struct YouTubeChannelPage: Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let avatarURL: URL?
    let videos: [VideoItem]
}

enum AccountFeedKind: String, CaseIterable, Identifiable {
    case subscriptions
    case history

    var id: String { rawValue }

    var titleKey: String {
        rawValue
    }

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
            return "YouTube account returned an invalid response."
        case .notSignedIn:
            return "Sign in to YouTube to use this section."
        }
    }
}

actor InnerTubeService {
    static let shared = InnerTubeService()

    func homeVideos() async throws -> [VideoItem] {
        let root = try await browse(
            "default",
            requireAuthentication: false
        )
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

    func channel(_ channelID: String) async throws -> YouTubeChannelPage {
        let root = try await browse(
            channelID,
            params: "EgZ2aWRlb3PyBgQKAjoA"
        )

        let metadata = Self.channelMetadata(from: root)

        return YouTubeChannelPage(
            id: channelID,
            title: metadata.title ?? "YouTube channel",
            description: metadata.description ?? "",
            avatarURL: metadata.avatarURL,
            videos: Self.extractVideos(from: root)
        )
    }

    private func browse(
        _ browseID: String,
        params: String? = nil,
        requireAuthentication: Bool = true
    ) async throws -> Any {
        let isSignedIn = await SmartTubeAuthService.shared.signedIn()

        if requireAuthentication && !isSignedIn {
            throw InnerTubeError.notSignedIn
        }

        let bootstrap = try? await SmartTubeAuthService.shared.bootstrap()
        let authorization = isSignedIn
            ? try await SmartTubeAuthService.shared.authorizationHeader()
            : nil

        let offsetMinutes = TimeZone.current.secondsFromGMT() / 60

        var client: [String: Any] = [
            "clientName": SmartTubeAuthService.tvClientName,
            "clientVersion": SmartTubeAuthService.tvClientVersion,
            "clientScreen": "WATCH",
            "userAgent": SmartTubeAuthService.tvUserAgent,
            "acceptLanguage": L10n.currentLanguageCode,
            "acceptRegion": "CZ",
            "utcOffsetMinutes": offsetMinutes,
            "webpSupport": false,
            "animatedWebpSupport": true,
            "tvAppInfo": [
                "appQuality": "TV_APP_QUALITY_FULL_ANIMATION",
                "zylonLeftNav": true
            ]
        ]

        if let visitorData = bootstrap?.visitorData,
           !visitorData.isEmpty {
            client["visitorData"] = visitorData
        }

        var payload: [String: Any] = [
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

        if let params, !params.isEmpty {
            payload["params"] = params
        }

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
        if let authorization {
            request.setValue(
                authorization,
                forHTTPHeaderField: "Authorization"
            )
        }

        if isSignedIn,
           let pageID = await SmartTubeAuthService.shared.selectedPageID(),
           !pageID.isEmpty {
            request.setValue(
                pageID,
                forHTTPHeaderField: "X-Goog-Pageid"
            )
        }

        if let visitorData = bootstrap?.visitorData,
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

    private static func channelMetadata(
        from node: Any
    ) -> (title: String?, description: String?, avatarURL: URL?) {
        if let dictionary = node as? [String: Any] {
            if let renderer = dictionary["channelMetadataRenderer"] as? [String: Any] {
                let title = renderer["title"] as? String
                let description = renderer["description"] as? String
                let avatarURL = thumbnailURL(from: renderer["avatar"])
                return (title, description, avatarURL)
            }

            for value in dictionary.values {
                let result = channelMetadata(from: value)
                if result.title != nil || result.description != nil || result.avatarURL != nil {
                    return result
                }
            }
        } else if let array = node as? [Any] {
            for value in array {
                let result = channelMetadata(from: value)
                if result.title != nil || result.description != nil || result.avatarURL != nil {
                    return result
                }
            }
        }

        return (nil, nil, nil)
    }

    private static func extractVideos(from root: Any) -> [VideoItem] {
        var renderers: [[String: Any]] = []
        collectVideoRenderers(from: root, into: &renderers)

        var seen = Set<String>()
        var result: [VideoItem] = []

        for renderer in renderers {
            guard let videoID = videoID(from: renderer),
                  videoID.count == 11,
                  seen.insert(videoID).inserted else {
                continue
            }

            let title =
                firstText(
                    in: renderer,
                    keys: ["title", "headline", "primaryText"]
                )
                ?? text(
                    from: nested(
                        renderer,
                        path: [
                            "metadata",
                            "tileMetadataRenderer",
                            "title"
                        ]
                    )
                )
                ?? text(
                    from: nested(
                        renderer,
                        path: [
                            "metadata",
                            "lockupMetadataViewModel",
                            "title"
                        ]
                    )
                )
                ?? "YouTube video"

            let metadata = metadataTexts(from: renderer)
                .filter {
                    !$0.isEmpty
                        && $0 != title
                        && $0 != "•"
                }

            let channel =
                firstText(
                    in: renderer,
                    keys: [
                        "ownerText",
                        "longBylineText",
                        "shortBylineText",
                        "secondaryText",
                        "byline"
                    ]
                )
                ?? metadata.first
                ?? "YouTube"

            let channelID = findChannelID(in: renderer)

            let duration =
                firstText(
                    in: renderer,
                    keys: ["lengthText", "durationText"]
                )
                ?? firstBadgeText(in: renderer)

            let published = firstText(
                in: renderer,
                keys: ["publishedTimeText"]
            )

            let views = firstText(
                in: renderer,
                keys: ["viewCountText", "shortViewCountText"]
            )

            var subtitleParts = [views, published, duration]
                .compactMap { $0 }
                .filter { !$0.isEmpty }

            if subtitleParts.isEmpty {
                subtitleParts = metadata
                    .filter { $0 != channel }
                    .prefix(3)
                    .map { $0 }
            }

            let thumbnailURL =
                firstThumbnailURL(in: renderer)
                ?? URL(
                    string:
                        "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg"
                )

            result.append(
                VideoItem(
                    id: "youtube-\(videoID)",
                    title: title,
                    channel: channel,
                    subtitle: subtitleParts.joined(separator: " • "),
                    thumbnailURL: thumbnailURL,
                    youtubeVideoID: videoID,
                    channelID: channelID
                )
            )

            if result.count >= 100 {
                break
            }
        }

        return result
    }

    private static func collectVideoRenderers(
        from node: Any,
        into output: inout [[String: Any]]
    ) {
        if let dictionary = node as? [String: Any] {
            let rendererKeys = [
                "videoRenderer",
                "gridVideoRenderer",
                "pivotVideoRenderer",
                "compactVideoRenderer",
                "reelItemRenderer",
                "playlistVideoRenderer",
                "tileRenderer",
                "lockupViewModel"
            ]

            for key in rendererKeys {
                if let renderer = dictionary[key] as? [String: Any] {
                    if key != "tileRenderer"
                        || (renderer["contentType"] as? String)
                            == "TILE_CONTENT_TYPE_VIDEO" {
                        output.append(renderer)
                    }
                }
            }

            for value in dictionary.values {
                collectVideoRenderers(from: value, into: &output)
            }
        } else if let array = node as? [Any] {
            for value in array {
                collectVideoRenderers(from: value, into: &output)
            }
        }
    }

    private static func videoID(
        from renderer: [String: Any]
    ) -> String? {
        if let direct = renderer["videoId"] as? String,
           direct.count == 11 {
            return direct
        }

        if let contentID = renderer["contentId"] as? String,
           contentID.count == 11 {
            return contentID
        }

        let paths = [
            ["onSelectCommand", "watchEndpoint", "videoId"],
            ["navigationEndpoint", "watchEndpoint", "videoId"],
            [
                "rendererContext",
                "commandContext",
                "onTap",
                "innertubeCommand",
                "watchEndpoint",
                "videoId"
            ],
            [
                "rendererContext",
                "commandContext",
                "onTap",
                "innertubeCommand",
                "reelWatchEndpoint",
                "videoId"
            ]
        ]

        for path in paths {
            if let value = nested(renderer, path: path) as? String,
               value.count == 11 {
                return value
            }
        }

        return nil
    }

    private static func nested(
        _ dictionary: [String: Any],
        path: [String]
    ) -> Any? {
        var current: Any = dictionary

        for key in path {
            guard let object = current as? [String: Any],
                  let next = object[key] else {
                return nil
            }

            current = next
        }

        return current
    }

    private static func metadataTexts(
        from node: Any
    ) -> [String] {
        var values: [String] = []
        collectTextValues(from: node, into: &values)

        var seen = Set<String>()

        return values.filter {
            let trimmed = $0.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            guard !trimmed.isEmpty,
                  trimmed.count < 160,
                  seen.insert(trimmed).inserted else {
                return false
            }

            return true
        }
    }

    private static func collectTextValues(
        from node: Any,
        into output: inout [String]
    ) {
        if let dictionary = node as? [String: Any] {
            if let simpleText = dictionary["simpleText"] as? String {
                output.append(simpleText)
            }

            if let content = dictionary["content"] as? String {
                output.append(content)
            }

            if let runs = dictionary["runs"] as? [[String: Any]] {
                let joined = runs
                    .compactMap { $0["text"] as? String }
                    .joined()

                if !joined.isEmpty {
                    output.append(joined)
                }
            }

            for value in dictionary.values {
                collectTextValues(from: value, into: &output)
            }
        } else if let array = node as? [Any] {
            for value in array {
                collectTextValues(from: value, into: &output)
            }
        }
    }

    private static func firstBadgeText(
        in node: Any
    ) -> String? {
        if let dictionary = node as? [String: Any] {
            for key in ["text", "label"] {
                if let raw = dictionary[key] as? String,
                   raw.contains(":") {
                    return raw
                }
            }

            if let value = dictionary["thumbnailOverlayTimeStatusRenderer"],
               let text = text(from: value),
               !text.isEmpty {
                return text
            }

            for value in dictionary.values {
                if let found = firstBadgeText(in: value) {
                    return found
                }
            }
        } else if let array = node as? [Any] {
            for value in array {
                if let found = firstBadgeText(in: value) {
                    return found
                }
            }
        }

        return nil
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

    private static func findChannelID(in node: Any) -> String? {
        if let dictionary = node as? [String: Any] {
            if let browseID = dictionary["browseId"] as? String,
               browseID.hasPrefix("UC") {
                return browseID
            }

            if let channelID = dictionary["channelId"] as? String,
               channelID.hasPrefix("UC") {
                return channelID
            }

            for value in dictionary.values {
                if let found = findChannelID(in: value) {
                    return found
                }
            }
        } else if let array = node as? [Any] {
            for value in array {
                if let found = findChannelID(in: value) {
                    return found
                }
            }
        }

        return nil
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
