import Foundation
import OSLog

struct YouTubePlaylistItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let thumbnailURL: URL?
}

struct YouTubeSubscribedChannel: Identifiable, Hashable {
    let id: String
    let title: String
    let thumbnailURL: URL?
}

struct YouTubePlaylistMembership: Identifiable, Hashable {
    let id: String
    let title: String
    let isSelected: Bool
}

struct YouTubeSearchTile: Identifiable, Hashable {
    let id: String
    let title: String
    let query: String
    let thumbnailURL: URL?
}

enum YouTubeSearchResultItem: Identifiable, Hashable {
    case video(VideoItem)
    case channel(YouTubeSubscribedChannel)
    case playlist(YouTubePlaylistItem)

    var id: String {
        switch self {
        case .video(let video):
            return "video-\(video.id)"
        case .channel(let channel):
            return "channel-\(channel.id)"
        case .playlist(let playlist):
            return "playlist-\(playlist.id)"
        }
    }
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

enum YouTubeLikeStatus: String, Hashable {
    case like = "LIKE"
    case dislike = "DISLIKE"
    case indifferent = "INDIFFERENT"
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
            return L10n.text("innertube_invalid_response")
        case .notSignedIn:
            return L10n.text("innertube_not_signed_in")
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

    func searchPage(
        _ query: String
    ) async throws -> (
        items: [YouTubeSearchResultItem],
        continuationToken: String?
    ) {
        let trimmed =
            query.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !trimmed.isEmpty else {
            return ([], nil)
        }

        let root =
            try await search(
                query: trimmed,
                continuation: nil
            )

        return (
            Self.extractSearchResultItems(
                from: root
            ),
            Self.nextContinuationToken(
                from: root
            )
        )
    }

    func continueSearch(
        _ continuationToken: String
    ) async throws -> (
        items: [YouTubeSearchResultItem],
        continuationToken: String?
    ) {
        let root =
            try await search(
                query: nil,
                continuation:
                    continuationToken
            )

        return (
            Self.extractSearchResultItems(
                from: root
            ),
            Self.nextContinuationToken(
                from: root
            )
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

    func subscribedChannels() async throws -> [YouTubeSubscribedChannel] {
        let root = try await browse(
            AccountFeedKind.subscriptions.browseID
        )

        return Self.extractSubscribedChannels(
            from: root
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
        try await playlistVideosPage(
            playlistID
        ).videos
    }

    func playlistVideosPage(
        _ playlistID: String
    ) async throws -> (
        videos: [VideoItem],
        continuationToken: String?
    ) {
        let browseID = playlistID.hasPrefix("VL")
            ? playlistID
            : "VL\(playlistID)"

        let root = try await browse(browseID)

        return (
            Self.extractVideos(from: root),
            Self.nextContinuationToken(from: root)
        )
    }

    func continuePlaylistVideos(
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

    func channel(_ channelID: String) async throws -> YouTubeChannelPage {
        try await channelPage(
            channelID
        ).page
    }

    func channelPage(
        _ channelID: String
    ) async throws -> (
        page: YouTubeChannelPage,
        continuationToken: String?,
        isSubscribed: Bool?
    ) {
        let root = try await browse(
            channelID,
            params: "EgZ2aWRlb3PyBgQKAjoA"
        )

        let metadata = Self.channelMetadata(from: root)

        return (
            YouTubeChannelPage(
                id: channelID,
                title: metadata.title ?? "YouTube channel",
                description: metadata.description ?? "",
                avatarURL: metadata.avatarURL,
                videos: Self.extractVideos(from: root)
            ),
            Self.nextContinuationToken(from: root),
            Self.channelSubscriptionState(
                from: root
            )
        )
    }

    func playlistMemberships(
        for videoID: String
    ) async throws -> [YouTubePlaylistMembership] {
        guard !videoID.isEmpty else {
            throw InnerTubeError.invalidResponse
        }

        let authorization =
            try await SmartTubeAuthService.shared
                .authorizationHeader()
        let bootstrap =
            try await SmartTubeAuthService.shared
                .bootstrap()

        var client: [String: Any] = [
            "hl": L10n.currentLanguageCode,
            "gl": "CZ",
            "clientName":
                SmartTubeAuthService
                    .tvClientName,
            "clientVersion":
                SmartTubeAuthService
                    .tvClientVersion
        ]

        if let visitorData =
                bootstrap.visitorData,
           !visitorData.isEmpty {
            client["visitorData"] =
                visitorData
        }

        let payload: [String: Any] = [
            "context": [
                "client": client
            ],
            "videoIds": [videoID]
        ]

        let root =
            try await signedTVPost(
                path:
                    "playlist/get_add_to_playlist",
                payload: payload,
                authorization:
                    authorization,
                bootstrap:
                    bootstrap
            )

        return Self.extractPlaylistMemberships(
            from: root
        )
    }

    func setPlaylistMembership(
        videoID: String,
        playlistID: String,
        add: Bool
    ) async throws {
        guard !videoID.isEmpty,
              !playlistID.isEmpty else {
            throw InnerTubeError.invalidResponse
        }

        let authorization =
            try await SmartTubeAuthService.shared
                .authorizationHeader()
        let bootstrap =
            try await SmartTubeAuthService.shared
                .bootstrap()

        var client: [String: Any] = [
            "hl": L10n.currentLanguageCode,
            "gl": "CZ",
            "clientName":
                SmartTubeAuthService
                    .tvClientName,
            "clientVersion":
                SmartTubeAuthService
                    .tvClientVersion
        ]

        if let visitorData =
                bootstrap.visitorData,
           !visitorData.isEmpty {
            client["visitorData"] =
                visitorData
        }

        let action: [String: Any] =
            add
                ? [
                    "addedVideoId": videoID,
                    "action":
                        "ACTION_ADD_VIDEO"
                ]
                : [
                    "removedVideoId": videoID,
                    "action":
                        "ACTION_REMOVE_VIDEO_BY_VIDEO_ID"
                ]

        let payload: [String: Any] = [
            "context": [
                "client": client
            ],
            "playlistId": playlistID,
            "actions": [action]
        ]

        _ = try await signedTVPost(
            path: "browse/edit_playlist",
            payload: payload,
            authorization: authorization,
            bootstrap: bootstrap
        )

        NotificationCenter.default.post(
            name: .youtubePlaylistsDidChange,
            object: nil
        )

        logger.notice(
            "Playlist membership add=\(add, privacy: .public) playlist=\(playlistID, privacy: .public) video=\(videoID, privacy: .public)"
        )
    }

    func createPlaylist(
        named name: String,
        adding videoID: String
    ) async throws {
        let trimmedName =
            name.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !trimmedName.isEmpty,
              !videoID.isEmpty else {
            throw InnerTubeError.invalidResponse
        }

        let authorization =
            try await SmartTubeAuthService.shared
                .authorizationHeader()
        let bootstrap =
            try await SmartTubeAuthService.shared
                .bootstrap()

        var client: [String: Any] = [
            "hl": L10n.currentLanguageCode,
            "gl": "CZ",
            "clientName": Self.webClientName,
            "clientVersion":
                Self.webClientVersion
        ]

        if let visitorData =
                bootstrap.visitorData,
           !visitorData.isEmpty {
            client["visitorData"] =
                visitorData
        }

        let payload: [String: Any] = [
            "context": [
                "client": client
            ],
            "title": trimmedName,
            "videoIds": [videoID]
        ]

        _ = try await signedWebPost(
            path: "playlist/create",
            payload: payload,
            authorization: authorization,
            bootstrap: bootstrap
        )

        NotificationCenter.default.post(
            name: .youtubePlaylistsDidChange,
            object: nil
        )

        logger.notice(
            "Playlist created name=\(trimmedName, privacy: .public) video=\(videoID, privacy: .public)"
        )
    }

    func videoLikeStatus(
        _ videoID: String
    ) async throws -> YouTubeLikeStatus {
        guard !videoID.isEmpty else {
            throw InnerTubeError.invalidResponse
        }

        let authorization =
            try await SmartTubeAuthService.shared
                .authorizationHeader()
        let bootstrap =
            try await SmartTubeAuthService.shared
                .bootstrap()

        var client: [String: Any] = [
            "hl": L10n.currentLanguageCode,
            "gl": "CZ",
            "clientName":
                SmartTubeAuthService
                    .tvClientName,
            "clientVersion":
                SmartTubeAuthService
                    .tvClientVersion
        ]

        if let visitorData =
                bootstrap.visitorData,
           !visitorData.isEmpty {
            client["visitorData"] =
                visitorData
        }

        let payload: [String: Any] = [
            "context": [
                "client": client
            ],
            "videoId": videoID
        ]

        guard let url = URL(
            string:
                "https://www.youtube.com/youtubei/v1/next"
        ) else {
            throw InnerTubeError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue(
            "application/json",
            forHTTPHeaderField:
                "Content-Type"
        )
        request.setValue(
            SmartTubeAuthService.tvUserAgent,
            forHTTPHeaderField:
                "User-Agent"
        )
        request.setValue(
            SmartTubeAuthService.tvReferer,
            forHTTPHeaderField:
                "Referer"
        )
        request.setValue(
            authorization,
            forHTTPHeaderField:
                "Authorization"
        )
        request.setValue(
            "7",
            forHTTPHeaderField:
                "X-YouTube-Client-Name"
        )
        request.setValue(
            SmartTubeAuthService.tvClientVersion,
            forHTTPHeaderField:
                "X-YouTube-Client-Version"
        )

        if let visitorData =
                bootstrap.visitorData,
           !visitorData.isEmpty {
            request.setValue(
                visitorData,
                forHTTPHeaderField:
                    "X-Goog-Visitor-Id"
            )
        }

        if let pageID =
                await SmartTubeAuthService
                    .shared
                    .selectedPageID(),
           !pageID.isEmpty {
            request.setValue(
                pageID,
                forHTTPHeaderField:
                    "X-Goog-Pageid"
            )
        }

        request.httpBody =
            try JSONSerialization.data(
                withJSONObject: payload
            )

        let (data, response) =
            try await URLSession.shared
                .data(for: request)

        guard let http =
                response as? HTTPURLResponse,
              (200..<300).contains(
                http.statusCode
              ),
              let root =
                try JSONSerialization
                    .jsonObject(
                        with: data
                    ) as? [String: Any]
        else {
            throw InnerTubeError.invalidResponse
        }

        return Self.findVideoLikeStatus(
            in: root
        ) ?? .indifferent
    }

    func setVideoReaction(
        videoID: String,
        current: YouTubeLikeStatus,
        target: YouTubeLikeStatus
    ) async throws {
        guard !videoID.isEmpty else {
            throw InnerTubeError.invalidResponse
        }

        let action: String

        switch target {
        case .like:
            action = "like"
        case .dislike:
            action = "dislike"
        case .indifferent:
            switch current {
            case .like:
                action = "removelike"
            case .dislike:
                action = "removedislike"
            case .indifferent:
                return
            }
        }

        let authorization =
            try await SmartTubeAuthService.shared
                .authorizationHeader()
        let bootstrap =
            try await SmartTubeAuthService.shared
                .bootstrap()

        var client: [String: Any] = [
            "hl": L10n.currentLanguageCode,
            "gl": "CZ",
            "clientName":
                SmartTubeAuthService
                    .tvClientName,
            "clientVersion":
                SmartTubeAuthService
                    .tvClientVersion
        ]

        if let visitorData =
                bootstrap.visitorData,
           !visitorData.isEmpty {
            client["visitorData"] =
                visitorData
        }

        let payload: [String: Any] = [
            "context": [
                "client": client
            ],
            "target": [
                "videoId": videoID
            ]
        ]

        guard let url = URL(
            string:
                "https://www.youtube.com/youtubei/v1/like/\(action)"
        ) else {
            throw InnerTubeError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue(
            "application/json",
            forHTTPHeaderField:
                "Content-Type"
        )
        request.setValue(
            SmartTubeAuthService.tvUserAgent,
            forHTTPHeaderField:
                "User-Agent"
        )
        request.setValue(
            SmartTubeAuthService.tvReferer,
            forHTTPHeaderField:
                "Referer"
        )
        request.setValue(
            authorization,
            forHTTPHeaderField:
                "Authorization"
        )
        request.setValue(
            "7",
            forHTTPHeaderField:
                "X-YouTube-Client-Name"
        )
        request.setValue(
            SmartTubeAuthService.tvClientVersion,
            forHTTPHeaderField:
                "X-YouTube-Client-Version"
        )

        if let visitorData =
                bootstrap.visitorData,
           !visitorData.isEmpty {
            request.setValue(
                visitorData,
                forHTTPHeaderField:
                    "X-Goog-Visitor-Id"
            )
        }

        if let pageID =
                await SmartTubeAuthService
                    .shared
                    .selectedPageID(),
           !pageID.isEmpty {
            request.setValue(
                pageID,
                forHTTPHeaderField:
                    "X-Goog-Pageid"
            )
        }

        request.httpBody =
            try JSONSerialization.data(
                withJSONObject: payload
            )

        let (_, response) =
            try await URLSession.shared
                .data(for: request)

        guard let http =
                response as? HTTPURLResponse,
              (200..<300).contains(
                http.statusCode
              ) else {
            throw InnerTubeError.invalidResponse
        }

        logger.notice(
            "Reaction action=\(action, privacy: .public) video=\(videoID, privacy: .public) status=\(http.statusCode, privacy: .public)"
        )
    }

    func setChannelSubscription(
        channelID: String,
        subscribed: Bool
    ) async throws {
        guard !channelID.isEmpty else {
            throw InnerTubeError.invalidResponse
        }

        let authorization =
            try await SmartTubeAuthService.shared
                .authorizationHeader()
        let bootstrap =
            try await SmartTubeAuthService.shared
                .bootstrap()

        var client: [String: Any] = [
            "hl": L10n.currentLanguageCode,
            "gl": "CZ",
            "clientName":
                SmartTubeAuthService
                    .tvClientName,
            "clientVersion":
                SmartTubeAuthService
                    .tvClientVersion
        ]

        if let visitorData =
                bootstrap.visitorData,
           !visitorData.isEmpty {
            client["visitorData"] =
                visitorData
        }

        let payload: [String: Any] = [
            "context": [
                "client": client
            ],
            "channelIds": [channelID],
            "params": ""
        ]

        let action =
            subscribed
                ? "subscribe"
                : "unsubscribe"

        guard let url = URL(
            string:
                "https://www.youtube.com/youtubei/v1/subscription/\(action)"
        ) else {
            throw InnerTubeError.invalidResponse
        }

        var request = URLRequest(
            url: url
        )
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue(
            "application/json",
            forHTTPHeaderField:
                "Content-Type"
        )
        request.setValue(
            SmartTubeAuthService
                .tvUserAgent,
            forHTTPHeaderField:
                "User-Agent"
        )
        request.setValue(
            SmartTubeAuthService
                .tvReferer,
            forHTTPHeaderField:
                "Referer"
        )
        request.setValue(
            authorization,
            forHTTPHeaderField:
                "Authorization"
        )
        request.setValue(
            "7",
            forHTTPHeaderField:
                "X-YouTube-Client-Name"
        )
        request.setValue(
            SmartTubeAuthService
                .tvClientVersion,
            forHTTPHeaderField:
                "X-YouTube-Client-Version"
        )

        if let visitorData =
                bootstrap.visitorData,
           !visitorData.isEmpty {
            request.setValue(
                visitorData,
                forHTTPHeaderField:
                    "X-Goog-Visitor-Id"
            )
        }

        if let pageID =
                await SmartTubeAuthService
                    .shared
                    .selectedPageID(),
           !pageID.isEmpty {
            request.setValue(
                pageID,
                forHTTPHeaderField:
                    "X-Goog-Pageid"
            )
        }

        request.httpBody =
            try JSONSerialization
                .data(
                    withJSONObject:
                        payload
                )

        let (_, response) =
            try await URLSession.shared
                .data(for: request)

        guard let http =
                response
                    as? HTTPURLResponse,
              (200..<300).contains(
                http.statusCode
              ) else {
            throw InnerTubeError.invalidResponse
        }

        NotificationCenter.default.post(
            name: .youtubeSubscriptionsDidChange,
            object: nil
        )

        logger.notice(
            "Subscription action=\(action, privacy: .public) channel=\(channelID, privacy: .public) status=\(http.statusCode, privacy: .public)"
        )
    }

    func continueChannelVideos(
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

    private func search(
        query: String?,
        continuation: String?
    ) async throws -> Any {
        let isSignedIn =
            await SmartTubeAuthService.shared
                .signedIn()
        let authorization =
            isSignedIn
                ? try await SmartTubeAuthService.shared
                    .authorizationHeader()
                : nil
        let bootstrap =
            isSignedIn
                ? try? await SmartTubeAuthService.shared
                    .bootstrap()
                : nil

        var client: [String: Any] = [
            "hl": L10n.currentLanguageCode,
            "gl": "CZ",
            "clientName":
                SmartTubeAuthService.tvClientName,
            "clientVersion":
                SmartTubeAuthService.tvClientVersion
        ]

        let visitorData =
            browseVisitorData
            ?? bootstrap?.visitorData

        if let visitorData,
           !visitorData.isEmpty {
            client["visitorData"] =
                visitorData
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
        } else if let query,
                  !query.isEmpty {
            payload["query"] = query
        } else {
            throw InnerTubeError.invalidResponse
        }

        guard let url = URL(
            string:
                "https://www.youtube.com/youtubei/v1/search"
        ) else {
            throw InnerTubeError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue(
            "application/json",
            forHTTPHeaderField:
                "Content-Type"
        )
        request.setValue(
            SmartTubeAuthService.tvUserAgent,
            forHTTPHeaderField:
                "User-Agent"
        )
        request.setValue(
            SmartTubeAuthService.tvReferer,
            forHTTPHeaderField:
                "Referer"
        )
        request.setValue(
            "7",
            forHTTPHeaderField:
                "X-YouTube-Client-Name"
        )
        request.setValue(
            SmartTubeAuthService.tvClientVersion,
            forHTTPHeaderField:
                "X-YouTube-Client-Version"
        )

        if let authorization {
            request.setValue(
                authorization,
                forHTTPHeaderField:
                    "Authorization"
            )
        }

        if let visitorData,
           !visitorData.isEmpty {
            request.setValue(
                visitorData,
                forHTTPHeaderField:
                    "X-Goog-Visitor-Id"
            )
        }

        if isSignedIn,
           let pageID =
                await SmartTubeAuthService.shared
                    .selectedPageID(),
           !pageID.isEmpty {
            request.setValue(
                pageID,
                forHTTPHeaderField:
                    "X-Goog-Pageid"
            )
        }

        request.httpBody =
            try JSONSerialization.data(
                withJSONObject: payload
            )

        let (data, response) =
            try await URLSession.shared
                .data(for: request)

        guard let http =
                response as? HTTPURLResponse,
              (200..<300).contains(
                http.statusCode
              ),
              let root =
                try JSONSerialization
                    .jsonObject(
                        with: data
                    ) as? [String: Any]
        else {
            throw InnerTubeError.invalidResponse
        }

        if let responseContext =
                root["responseContext"]
                    as? [String: Any],
           let visitor =
                responseContext[
                    "visitorData"
                ] as? String,
           !visitor.isEmpty {
            browseVisitorData = visitor
        }

        logger.notice(
            "Search client=TV continuation=\(continuation != nil, privacy: .public) items=\(Self.extractSearchResultItems(from: root).count, privacy: .public)"
        )

        return root
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

        guard var components = URLComponents(
            string: endpoint
        ) else {
            throw InnerTubeError.invalidResponse
        }

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

    private static func extractSearchResultItems(
        from root: Any
    ) -> [YouTubeSearchResultItem] {
        var dictionaries: [[String: Any]] = []
        collectDictionaries(
            from: root,
            into: &dictionaries
        )

        var seen = Set<String>()
        var result: [YouTubeSearchResultItem] = []

        for dictionary in dictionaries {
            guard let renderer =
                    dictionary["tileRenderer"]
                    as? [String: Any],
                  let contentType =
                    renderer["contentType"]
                    as? String else {
                continue
            }

            switch contentType {
            case "TILE_CONTENT_TYPE_VIDEO":
                guard let video =
                        extractVideos(
                            from: renderer
                        ).first else {
                    continue
                }

                let identity =
                    "video-\(video.id)"
                guard seen.insert(identity).inserted else {
                    continue
                }

                result.append(
                    .video(video)
                )

            case "TILE_CONTENT_TYPE_CHANNEL":
                let channelID =
                    (renderer["contentId"] as? String)
                    ?? findChannelID(
                        in: renderer
                    )

                guard let channelID,
                      channelID.hasPrefix("UC")
                else {
                    continue
                }

                let title =
                    firstText(
                        in: renderer,
                        keys: [
                            "title",
                            "headline",
                            "primaryText"
                        ]
                    )
                    ?? metadataTexts(
                        from: renderer
                    ).first
                    ?? "YouTube"

                let channel =
                    YouTubeSubscribedChannel(
                        id: channelID,
                        title: title,
                        thumbnailURL:
                            firstThumbnailURL(
                                in: renderer
                            )
                    )
                let identity =
                    "channel-\(channel.id)"
                guard seen.insert(identity).inserted else {
                    continue
                }

                result.append(
                    .channel(channel)
                )

            case "TILE_CONTENT_TYPE_PLAYLIST":
                let directID =
                    renderer["contentId"]
                        as? String
                let browseID =
                    nested(
                        renderer,
                        path: [
                            "onSelectCommand",
                            "browseEndpoint",
                            "browseId"
                        ]
                    ) as? String
                let playlistID =
                    (browseID?.hasPrefix("VL") == true)
                        ? browseID
                        : directID

                guard let playlistID,
                      !playlistID.isEmpty else {
                    continue
                }

                let title =
                    firstText(
                        in: renderer,
                        keys: [
                            "title",
                            "headline",
                            "primaryText"
                        ]
                    )
                    ?? "YouTube playlist"

                let metadata =
                    metadataTexts(
                        from: renderer
                    )
                    .filter {
                        !$0.isEmpty
                            && $0 != title
                    }

                let playlist =
                    YouTubePlaylistItem(
                        id: playlistID,
                        title: title,
                        subtitle:
                            metadata.first
                            ?? "",
                        thumbnailURL:
                            firstThumbnailURL(
                                in: renderer
                            )
                    )
                let identity =
                    "playlist-\(playlist.id)"
                guard seen.insert(identity).inserted else {
                    continue
                }

                result.append(
                    .playlist(playlist)
                )

            default:
                continue
            }
        }

        if result.isEmpty {
            return extractVideos(
                from: root
            ).map {
                .video($0)
            }
        }

        return result
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
                homeShelfTitle(
                    from: shelf
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

    private static func homeShelfTitle(
        from shelf: [String: Any]
    ) -> String? {
        if let title =
                text(
                    from: shelf["title"] as Any
                ),
           !title.isEmpty {
            return title
        }

        if let headerTitle =
                nested(
                    shelf,
                    path: [
                        "headerRenderer",
                        "shelfHeaderRenderer",
                        "title"
                    ]
                ),
           let title =
                text(from: headerTitle),
           !title.isEmpty {
            return title
        }

        if let avatarTitle =
                nested(
                    shelf,
                    path: [
                        "headerRenderer",
                        "shelfHeaderRenderer",
                        "avatarLockup",
                        "avatarLockupRenderer",
                        "title"
                    ]
                ),
           let title =
                text(from: avatarTitle),
           !title.isEmpty {
            return title
        }

        return nil
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

    private static func extractSubscribedChannels(
        from root: Any
    ) -> [YouTubeSubscribedChannel] {
        var candidates: [[String: Any]] = []
        collectDictionaries(
            from: root,
            into: &candidates
        )

        var seen = Set<String>()
        var result: [YouTubeSubscribedChannel] = []

        for dictionary in candidates {
            guard let renderer =
                    dictionary["tabRenderer"]
                    as? [String: Any],
                  let channelID =
                    findChannelID(in: renderer),
                  channelID.hasPrefix("UC"),
                  seen.insert(channelID).inserted else {
                continue
            }

            let title =
                firstText(
                    in: renderer,
                    keys: ["title"]
                )
                ?? "YouTube"

            result.append(
                YouTubeSubscribedChannel(
                    id: channelID,
                    title: title,
                    thumbnailURL:
                        firstThumbnailURL(
                            in: renderer
                        )
                )
            )
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

    private func signedTVPost(
        path: String,
        payload: [String: Any],
        authorization: String,
        bootstrap: TVBootstrap
    ) async throws -> [String: Any] {
        guard let url = URL(
            string:
                "https://www.youtube.com/youtubei/v1/\(path)"
        ) else {
            throw InnerTubeError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue(
            "application/json",
            forHTTPHeaderField:
                "Content-Type"
        )
        request.setValue(
            SmartTubeAuthService.tvUserAgent,
            forHTTPHeaderField:
                "User-Agent"
        )
        request.setValue(
            SmartTubeAuthService.tvReferer,
            forHTTPHeaderField:
                "Referer"
        )
        request.setValue(
            authorization,
            forHTTPHeaderField:
                "Authorization"
        )
        request.setValue(
            "7",
            forHTTPHeaderField:
                "X-YouTube-Client-Name"
        )
        request.setValue(
            SmartTubeAuthService.tvClientVersion,
            forHTTPHeaderField:
                "X-YouTube-Client-Version"
        )

        if let visitorData =
                bootstrap.visitorData,
           !visitorData.isEmpty {
            request.setValue(
                visitorData,
                forHTTPHeaderField:
                    "X-Goog-Visitor-Id"
            )
        }

        if let pageID =
                await SmartTubeAuthService
                    .shared
                    .selectedPageID(),
           !pageID.isEmpty {
            request.setValue(
                pageID,
                forHTTPHeaderField:
                    "X-Goog-Pageid"
            )
        }

        request.httpBody =
            try JSONSerialization.data(
                withJSONObject: payload
            )

        let (data, response) =
            try await URLSession.shared
                .data(for: request)

        guard let http =
                response as? HTTPURLResponse,
              (200..<300).contains(
                http.statusCode
              ) else {
            throw InnerTubeError.invalidResponse
        }

        if data.isEmpty {
            return [:]
        }

        guard let root =
                try JSONSerialization
                    .jsonObject(
                        with: data
                    ) as? [String: Any]
        else {
            throw InnerTubeError.invalidResponse
        }

        return root
    }

    private func signedWebPost(
        path: String,
        payload: [String: Any],
        authorization: String,
        bootstrap: TVBootstrap
    ) async throws -> [String: Any] {
        var components = URLComponents(
            string:
                "https://www.youtube.com/youtubei/v1/\(path)"
        )

        components?.queryItems = [
            URLQueryItem(
                name: "key",
                value: Self.webAPIKey
            )
        ]

        guard let url = components?.url else {
            throw InnerTubeError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue(
            "application/json",
            forHTTPHeaderField:
                "Content-Type"
        )
        request.setValue(
            "https://www.youtube.com",
            forHTTPHeaderField:
                "Origin"
        )
        request.setValue(
            authorization,
            forHTTPHeaderField:
                "Authorization"
        )
        request.setValue(
            Self.webClientNameID,
            forHTTPHeaderField:
                "X-YouTube-Client-Name"
        )
        request.setValue(
            Self.webClientVersion,
            forHTTPHeaderField:
                "X-YouTube-Client-Version"
        )

        if let visitorData =
                bootstrap.visitorData,
           !visitorData.isEmpty {
            request.setValue(
                visitorData,
                forHTTPHeaderField:
                    "X-Goog-Visitor-Id"
            )
        }

        if let pageID =
                await SmartTubeAuthService
                    .shared
                    .selectedPageID(),
           !pageID.isEmpty {
            request.setValue(
                pageID,
                forHTTPHeaderField:
                    "X-Goog-Pageid"
            )
        }

        request.httpBody =
            try JSONSerialization.data(
                withJSONObject: payload
            )

        let (data, response) =
            try await URLSession.shared
                .data(for: request)

        guard let http =
                response as? HTTPURLResponse,
              (200..<300).contains(
                http.statusCode
              ) else {
            throw InnerTubeError.invalidResponse
        }

        if data.isEmpty {
            return [:]
        }

        guard let root =
                try JSONSerialization
                    .jsonObject(
                        with: data
                    ) as? [String: Any]
        else {
            throw InnerTubeError.invalidResponse
        }

        return root
    }

    private static func extractPlaylistMemberships(
        from node: Any
    ) -> [YouTubePlaylistMembership] {
        var dictionaries:
            [[String: Any]] = []

        collectDictionaries(
            from: node,
            into: &dictionaries
        )

        var seen = Set<String>()
        var result:
            [YouTubePlaylistMembership] = []

        for dictionary in dictionaries {
            guard let renderer =
                    dictionary[
                        "playlistAddToOptionRenderer"
                    ] as? [String: Any],
                  let playlistID =
                    renderer[
                        "playlistId"
                    ] as? String,
                  !playlistID.isEmpty,
                  seen.insert(
                    playlistID
                  ).inserted else {
                continue
            }

            let title =
                firstText(
                    in: renderer,
                    keys: ["title"]
                )
                ?? playlistID
            let selected =
                (
                    renderer[
                        "containsSelectedVideos"
                    ] as? String
                ) == "ALL"

            result.append(
                YouTubePlaylistMembership(
                    id: playlistID,
                    title: title,
                    isSelected: selected
                )
            )
        }

        return result
    }

    private static func findVideoLikeStatus(
        in node: Any
    ) -> YouTubeLikeStatus? {
        if let dictionary =
                node as? [String: Any] {
            if let renderer =
                    dictionary[
                        "videoMetadataRenderer"
                    ] as? [String: Any] {
                if let raw =
                        renderer[
                            "likeStatus"
                        ] as? String,
                   let status =
                        YouTubeLikeStatus(
                            rawValue: raw
                        ) {
                    return status
                }

                if let likeButton =
                        renderer[
                            "likeButton"
                        ] as? [String: Any],
                   let buttonRenderer =
                        likeButton[
                            "likeButtonRenderer"
                        ] as? [String: Any],
                   let raw =
                        buttonRenderer[
                            "likeStatus"
                        ] as? String,
                   let status =
                        YouTubeLikeStatus(
                            rawValue: raw
                        ) {
                    return status
                }
            }

            for value in dictionary.values {
                if let status =
                    findVideoLikeStatus(
                        in: value
                    ) {
                    return status
                }
            }
        } else if let array =
                    node as? [Any] {
            for value in array {
                if let status =
                    findVideoLikeStatus(
                        in: value
                    ) {
                    return status
                }
            }
        }

        return nil
    }

    private static func channelSubscriptionState(
        from node: Any
    ) -> Bool? {
        if let dictionary =
                node as? [String: Any] {
            if let renderer =
                    dictionary[
                        "subscribeButtonRenderer"
                    ] as? [String: Any],
               let subscribed =
                    renderer[
                        "subscribed"
                    ] as? Bool {
                return subscribed
            }

            for value
                in dictionary.values {
                if let state =
                    channelSubscriptionState(
                        from: value
                    ) {
                    return state
                }
            }
        } else if let array =
                    node as? [Any] {
            for value in array {
                if let state =
                    channelSubscriptionState(
                        from: value
                    ) {
                    return state
                }
            }
        }

        return nil
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
