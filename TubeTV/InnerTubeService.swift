import Foundation
import OSLog

struct YouTubePlaylistItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let thumbnailURL: URL?
}

struct YouTubeSearchTile: Identifiable, Hashable {
    let id: String
    let title: String
    let query: String
    let thumbnailURL: URL?
}

struct YouTubeHomeSection: Identifiable, Hashable {
    let id: String
    let title: String
    let videos: [VideoItem]
    let searchTiles: [YouTubeSearchTile]
    let continuationToken: String?
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

    private static let webClientName = "WEB"
    private static let webClientVersion = "2.20260907.06.00"
    private static let webClientNameID = "1"
    private static let webAPIKey =
        "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8"

    private let logger = Logger(
        subsystem: "cz.caseycz.tubetv",
        category: "InnerTube"
    )

    private var browseVisitorData: String?

    func homePage() async throws -> (
        sections: [YouTubeHomeSection],
        continuationToken: String?
    ) {
        // SmartTube uses the TV Home browse id ("default") when signed in.
        // Anonymous Home stays on WEB + FEwhat_to_watch.
        let isSignedIn =
            await SmartTubeAuthService.shared
                .signedIn()
        let homeBrowseID =
            isSignedIn
            ? "default"
            : "FEwhat_to_watch"

        let root = try await browse(
            homeBrowseID,
            requireAuthentication: false,
            includeVisitorData: true
        )
        let diagnostics =
            Self.rendererDiagnostics(from: root)
        let sections =
            Self.extractHomeSections(from: root)
        let continuationToken =
            Self.homeSectionListContinuationToken(
                from: root
            )

        logger.notice(
            "Home renderer diagnostics=\(diagnostics, privacy: .public)"
        )
        logger.notice(
            "Home parsed sections=\(sections.count, privacy: .public) videos=\(sections.reduce(0) { $0 + $1.videos.count }, privacy: .public) hasNext=\(continuationToken != nil, privacy: .public)"
        )

        return (
            sections,
            continuationToken
        )
    }

    func homeSections() async throws -> [YouTubeHomeSection] {
        try await homePage().sections
    }

    func homeVideos() async throws -> [VideoItem] {
        let sections = try await homeSections()
        var seen = Set<String>()

        return sections
            .flatMap(\.videos)
            .filter {
                seen.insert($0.id).inserted
            }
    }

    func continueHomePage(
        _ continuationToken: String
    ) async throws -> (
        sections: [YouTubeHomeSection],
        continuationToken: String?
    ) {
        let root = try await browse(
            nil,
            continuation: continuationToken,
            requireAuthentication: false,
            includeVisitorData: true
        )

        return (
            Self.extractHomeSections(from: root),
            Self.homeSectionListContinuationToken(
                from: root
            )
        )
    }

    func continueHomeSection(
        _ continuationToken: String
    ) async throws -> (
        videos: [VideoItem],
        continuationToken: String?
    ) {
        let root = try await browse(
            nil,
            continuation: continuationToken,
            requireAuthentication: false,
            includeVisitorData: true
        )

        return (
            Self.extractVideos(from: root),
            Self.nextContinuationToken(from: root)
        )
    }

    func videos(for kind: AccountFeedKind) async throws -> [VideoItem] {
        let root = try await browse(kind.browseID)
        return Self.extractVideos(from: root)
    }

    func subscriptionsPage() async throws -> (
        videos: [VideoItem],
        continuationToken: String?
    ) {
        let root = try await browse(
            AccountFeedKind.subscriptions.browseID
        )

        return (
            Self.extractVideos(from: root),
            Self.nextContinuationToken(from: root)
        )
    }

    func continueSubscriptions(
        _ continuationToken: String
    ) async throws -> (
        videos: [VideoItem],
        continuationToken: String?
    ) {
        let root = try await browse(
            nil,
            continuation: continuationToken
        )

        return (
            Self.extractVideos(from: root),
            Self.nextContinuationToken(from: root)
        )
    }

    func historyPage() async throws -> (
        videos: [VideoItem],
        continuationToken: String?
    ) {
        let root = try await browse(
            AccountFeedKind.history.browseID
        )

        return (
            Self.extractVideos(from: root),
            Self.nextContinuationToken(from: root)
        )
    }

    func continueHistory(
        _ continuationToken: String
    ) async throws -> (
        videos: [VideoItem],
        continuationToken: String?
    ) {
        let root = try await browse(
            nil,
            continuation: continuationToken
        )

        return (
            Self.extractVideos(from: root),
            Self.nextContinuationToken(from: root)
        )
    }

    func playlists() async throws -> [YouTubePlaylistItem] {
        let root = try await browse("FEplaylist_aggregation")
        return Self.extractPlaylists(from: root)
    }

    func playlistsPage() async throws -> (
        playlists: [YouTubePlaylistItem],
        continuationToken: String?
    ) {
        let root = try await browse(
            "FEplaylist_aggregation"
        )

        return (
            Self.extractPlaylists(from: root),
            Self.nextContinuationToken(from: root)
        )
    }

    func continuePlaylists(
        _ continuationToken: String
    ) async throws -> (
        playlists: [YouTubePlaylistItem],
        continuationToken: String?
    ) {
        let root = try await browse(
            nil,
            continuation: continuationToken
        )

        return (
            Self.extractPlaylists(from: root),
            Self.nextContinuationToken(from: root)
        )
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
        _ browseID: String?,
        params: String? = nil,
        continuation: String? = nil,
        requireAuthentication: Bool = true,
        includeVisitorData: Bool = false
    ) async throws -> Any {
        let isSignedIn = await SmartTubeAuthService.shared.signedIn()

        if requireAuthentication && !isSignedIn {
            throw InnerTubeError.notSignedIn
        }

        let useWebClient = !isSignedIn && !requireAuthentication
        let authorization = isSignedIn
            ? try await SmartTubeAuthService.shared.authorizationHeader()
            : nil

        let bootstrap = isSignedIn
            ? try? await SmartTubeAuthService.shared.bootstrap()
            : nil

        let client: [String: Any]

        if useWebClient {
            // Mirrors SmartTubeIOS webClientContext for anonymous Home.
            client = [
                "hl": "en",
                "gl": "US",
                "clientName": Self.webClientName,
                "clientVersion": Self.webClientVersion
            ]
        } else {
            // Authenticated browse is bound to the TV OAuth client.
            client = [
                "hl": L10n.currentLanguageCode,
                "gl": "CZ",
                "clientName": SmartTubeAuthService.tvClientName,
                "clientVersion": SmartTubeAuthService.tvClientVersion
            ]
        }

        var payload: [String: Any] = [
            "context": [
                "client": client
            ]
        ]

        if let continuation,
           !continuation.isEmpty {
            payload["continuation"] =
                continuation
        } else if let browseID,
                  !browseID.isEmpty {
            payload["browseId"] =
                browseID
        } else {
            throw InnerTubeError.invalidResponse
        }

        if let params, !params.isEmpty {
            payload["params"] = params
        }

        if includeVisitorData {
            let visitor =
                browseVisitorData
                ?? bootstrap?.visitorData

            if let visitor, !visitor.isEmpty {
                payload["visitorData"] = visitor
            }
        }

        let endpoint = useWebClient
            ? "https://www.youtube.com/youtubei/v1/browse"
            : "https://youtubei.googleapis.com/youtubei/v1/browse"

        var components = URLComponents(string: endpoint)!

        if useWebClient {
            components.queryItems = [
                URLQueryItem(
                    name: "key",
                    value: Self.webAPIKey
                )
            ]
        }

        guard let url = components.url else {
            throw InnerTubeError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )

        if useWebClient {
            request.setValue(
                "https://www.youtube.com",
                forHTTPHeaderField: "Origin"
            )
            request.setValue(
                Self.webClientNameID,
                forHTTPHeaderField: "X-YouTube-Client-Name"
            )
            request.setValue(
                Self.webClientVersion,
                forHTTPHeaderField: "X-YouTube-Client-Version"
            )
        } else {
            request.setValue(
                "7",
                forHTTPHeaderField: "X-YouTube-Client-Name"
            )
            request.setValue(
                SmartTubeAuthService.tvClientVersion,
                forHTTPHeaderField: "X-YouTube-Client-Version"
            )

            if let authorization {
                request.setValue(
                    authorization,
                    forHTTPHeaderField: "Authorization"
                )
            }

            if let pageID =
                await SmartTubeAuthService.shared.selectedPageID(),
               !pageID.isEmpty {
                request.setValue(
                    pageID,
                    forHTTPHeaderField: "X-Goog-Pageid"
                )
            }
        }

        request.httpBody =
            try JSONSerialization.data(withJSONObject: payload)

        let (data, response) =
            try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let root = try JSONSerialization.jsonObject(
                with: data
              ) as? [String: Any] else {
            throw InnerTubeError.invalidResponse
        }

        if let responseContext =
                root["responseContext"] as? [String: Any],
           let visitor =
                responseContext["visitorData"] as? String,
           !visitor.isEmpty {
            browseVisitorData = visitor
        }

        let requestID =
            browseID
            ?? (continuation == nil
                ? "unknown"
                : "continuation")

        logger.notice(
            "Browse client=\(useWebClient ? "WEB" : "TV", privacy: .public) id=\(requestID, privacy: .public) status=\(http.statusCode, privacy: .public)"
        )

        return root
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

    private static func extractHomeSections(
        from root: Any
    ) -> [YouTubeHomeSection] {
        var shelves: [[String: Any]] = []
        collectHomeShelfRenderers(
            from: root,
            into: &shelves
        )

        var sections: [YouTubeHomeSection] = []

        for (index, shelf) in shelves.enumerated() {
            let videos = extractVideos(from: shelf)
            let searchTiles =
                extractSearchTiles(from: shelf)

            guard !videos.isEmpty
                    || !searchTiles.isEmpty else {
                continue
            }

            let title =
                firstText(
                    in: shelf,
                    keys: [
                        "title",
                        "headline",
                        "header",
                        "primaryText"
                    ]
                )
                ?? ""

            let identity =
                videos.first?.id
                ?? searchTiles.first?.id
                ?? "section"

            sections.append(
                YouTubeHomeSection(
                    id:
                        "home-\(index)-\(identity)",
                    title: title,
                    videos: videos,
                    searchTiles: searchTiles,
                    continuationToken:
                        nextContinuationToken(
                            from: shelf
                        )
                )
            )
        }

        if !sections.isEmpty {
            return sections
        }

        let videos = extractVideos(from: root)

        guard !videos.isEmpty else {
            return []
        }

        return [
            YouTubeHomeSection(
                id: "home-feed",
                title: "",
                videos: videos,
                searchTiles: [],
                continuationToken:
                    nextContinuationToken(
                        from: root
                    )
            )
        ]
    }

    private static func extractSearchTiles(
        from root: Any
    ) -> [YouTubeSearchTile] {
        var dictionaries: [[String: Any]] = []
        collectDictionaries(
            from: root,
            into: &dictionaries
        )

        var seen = Set<String>()
        var result: [YouTubeSearchTile] = []

        for dictionary in dictionaries {
            guard let renderer =
                    dictionary["tileRenderer"]
                    as? [String: Any],
                  renderer["contentType"]
                    as? String
                    == "TILE_CONTENT_TYPE_EDU",
                  let query =
                    searchQuery(from: renderer),
                  !query.isEmpty,
                  seen.insert(query).inserted else {
                continue
            }

            let title =
                metadataTexts(from: renderer)
                    .first(where: {
                        !$0.isEmpty
                            && $0 != query
                    })
                ?? query

            result.append(
                YouTubeSearchTile(
                    id: "search-\(query)",
                    title: title,
                    query: query,
                    thumbnailURL:
                        firstThumbnailURL(
                            in: renderer
                        )
                )
            )
        }

        return result
    }

    private static func searchQuery(
        from node: Any
    ) -> String? {
        if let dictionary = node as? [String: Any] {
            if let endpoint =
                    dictionary["searchEndpoint"]
                    as? [String: Any],
               let query =
                    endpoint["query"] as? String,
               !query.isEmpty {
                return query
            }

            for value in dictionary.values {
                if let query =
                        searchQuery(from: value) {
                    return query
                }
            }
        } else if let array = node as? [Any] {
            for value in array {
                if let query =
                        searchQuery(from: value) {
                    return query
                }
            }
        }

        return nil
    }

    private static func collectHomeShelfRenderers(
        from node: Any,
        into output: inout [[String: Any]]
    ) {
        if let dictionary = node as? [String: Any] {
            for key in [
                "shelfRenderer",
                "richShelfRenderer"
            ] {
                if let renderer =
                        dictionary[key]
                        as? [String: Any] {
                    output.append(renderer)
                }
            }

            for value in dictionary.values {
                collectHomeShelfRenderers(
                    from: value,
                    into: &output
                )
            }
        } else if let array = node as? [Any] {
            for value in array {
                collectHomeShelfRenderers(
                    from: value,
                    into: &output
                )
            }
        }
    }

    private static func homeSectionListContinuationToken(
        from node: Any
    ) -> String? {
        if let dictionary = node as? [String: Any] {
            for key in [
                "sectionListRenderer",
                "sectionListContinuation"
            ] {
                if let renderer =
                        dictionary[key]
                        as? [String: Any],
                   let continuations =
                        renderer["continuations"],
                   let token =
                        nextContinuationToken(
                            from: continuations
                        ) {
                    return token
                }
            }

            for value in dictionary.values {
                if let token =
                        homeSectionListContinuationToken(
                            from: value
                        ) {
                    return token
                }
            }
        } else if let array = node as? [Any] {
            for value in array {
                if let token =
                        homeSectionListContinuationToken(
                            from: value
                        ) {
                    return token
                }
            }
        }

        return nil
    }

    private static func nextContinuationToken(
        from node: Any
    ) -> String? {
        if let dictionary = node as? [String: Any] {
            if let data =
                    dictionary[
                        "nextContinuationData"
                    ] as? [String: Any],
               let token =
                    data["continuation"] as? String,
               !token.isEmpty {
                return token
            }

            if let command =
                    dictionary[
                        "continuationCommand"
                    ] as? [String: Any],
               let token =
                    command["token"] as? String,
               !token.isEmpty {
                return token
            }

            for value in dictionary.values {
                if let token =
                        nextContinuationToken(
                            from: value
                        ) {
                    return token
                }
            }
        } else if let array = node as? [Any] {
            for value in array {
                if let token =
                        nextContinuationToken(
                            from: value
                        ) {
                    return token
                }
            }
        }

        return nil
    }

    private static func rendererDiagnostics(
        from root: Any
    ) -> String {
        let watched = Set([
            "videoRenderer",
            "gridVideoRenderer",
            "compactVideoRenderer",
            "playlistVideoRenderer",
            "reelItemRenderer",
            "tileRenderer",
            "lockupViewModel",
            "shortsLockupViewModel",
            "richItemRenderer",
            "richShelfRenderer",
            "richGridRenderer",
            "tvBrowseRenderer"
        ])

        var counts: [String: Int] = [:]

        func walk(_ node: Any) {
            if let dictionary = node as? [String: Any] {
                for (key, value) in dictionary {
                    if watched.contains(key) {
                        counts[key, default: 0] += 1
                    }
                    walk(value)
                }
            } else if let array = node as? [Any] {
                for value in array {
                    walk(value)
                }
            }
        }

        walk(root)

        if counts.isEmpty {
            return "none"
        }

        return counts
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
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
                "lockupViewModel",
                "shortsLockupViewModel"
            ]

            for key in rendererKeys {
                if let renderer = dictionary[key] as? [String: Any] {
                    if key != "tileRenderer" {
                        output.append(renderer)
                    } else {
                        let contentType =
                            renderer["contentType"] as? String

                        if contentType == "TILE_CONTENT_TYPE_VIDEO"
                            || contentType == "TILE_CONTENT_TYPE_REEL" {
                            output.append(renderer)
                        }
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
            ["onSelectCommand", "reelWatchEndpoint", "videoId"],
            [
                "onSelectCommand",
                "innertubeCommand",
                "watchEndpoint",
                "videoId"
            ],
            [
                "onSelectCommand",
                "innertubeCommand",
                "reelWatchEndpoint",
                "videoId"
            ],
            ["navigationEndpoint", "watchEndpoint", "videoId"],
            ["navigationEndpoint", "reelWatchEndpoint", "videoId"],
            [
                "navigationEndpoint",
                "innertubeCommand",
                "watchEndpoint",
                "videoId"
            ],
            [
                "navigationEndpoint",
                "innertubeCommand",
                "reelWatchEndpoint",
                "videoId"
            ],
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
            ],
            [
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
