import SwiftUI

struct AccountFeedView: View {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
    let kind: AccountFeedKind

    @State private var videos: [VideoItem] = []
    @State private var continuationToken: String?
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var isSignedIn = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    HStack {
                        Label(L10n.text(kind.titleKey, languageCode: appLanguage), systemImage: kind.icon)
                            .font(.largeTitle.bold())

                        Spacer()

                        if isLoading {
                            ProgressView()
                        }
                    }

                    if let errorMessage {
                        VStack(alignment: .leading, spacing: 14) {
                            Label(
                                errorMessage,
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .foregroundStyle(.red)

                            if !isSignedIn {
                                Text(L10n.text("sign_in_hint", languageCode: appLanguage))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 420), spacing: 28)],
                        spacing: 28
                    ) {
                        ForEach(
                            videos.indices,
                            id: \.self
                        ) { index in
                            let video = videos[index]

                            NavigationLink(value: video) {
                                VideoCard(video: video)
                            }
                            .buttonStyle(.card)
                            .onAppear {
                                let threshold =
                                    max(
                                        0,
                                        videos.count - 4
                                    )

                                guard index >= threshold else {
                                    return
                                }

                                Task {
                                    switch kind {
                                    case .subscriptions:
                                        await loadMoreSubscriptions()
                                    case .history:
                                        await loadMoreHistory()
                                    }
                                }
                            }
                        }

                        if isLoadingMore {
                            ProgressView()
                                .frame(
                                    width: 420,
                                    height: 236
                                )
                        }
                    }
                }
                .padding(48)
            }
            .navigationDestination(for: VideoItem.self) { video in
                VideoDetailView(video: video)
            }
            .task {
                await load()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .youtubeSubscriptionsDidChange
                )
            ) { _ in
                guard kind == .subscriptions else {
                    return
                }

                Task {
                    await load()
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .youtubeAccountDidChange
                )
            ) { _ in
                Task {
                    await load()
                }
            }
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        isSignedIn =
            await SmartTubeAuthService.shared
                .signedIn()
        defer { isLoading = false }

        do {
            switch kind {
            case .subscriptions:
                let page =
                    try await InnerTubeService.shared
                        .subscriptionsPage()

                videos = page.videos
                continuationToken =
                    page.continuationToken

            case .history:
                let page =
                    try await InnerTubeService.shared
                        .historyPage()

                videos = page.videos
                continuationToken =
                    page.continuationToken
            }

            if videos.isEmpty {
                errorMessage = L10n.text("youtube_no_videos", languageCode: appLanguage)
            }
        } catch {
            videos = []
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadMoreSubscriptions() async {
        guard kind == .subscriptions,
              !isLoadingMore,
              let token = continuationToken,
              !token.isEmpty else {
            return
        }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page =
                try await InnerTubeService.shared
                    .continueSubscriptions(
                        token
                    )

            append(
                page.videos,
                nextToken: page.continuationToken,
                previousToken: token
            )
        } catch {
            errorMessage =
                error.localizedDescription
        }
    }

    @MainActor
    private func loadMoreHistory() async {
        guard kind == .history,
              !isLoadingMore,
              let token = continuationToken,
              !token.isEmpty else {
            return
        }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page =
                try await InnerTubeService.shared
                    .continueHistory(
                        token
                    )

            append(
                page.videos,
                nextToken: page.continuationToken,
                previousToken: token
            )
        } catch {
            errorMessage =
                error.localizedDescription
        }
    }

    @MainActor
    private func append(
        _ incoming: [VideoItem],
        nextToken: String?,
        previousToken: String
    ) {
        var seen = Set(
            videos.map(\.id)
        )
        let newVideos =
            incoming.filter {
                seen.insert($0.id).inserted
            }

        videos.append(
            contentsOf: newVideos
        )

        continuationToken =
            nextToken == previousToken
                && newVideos.isEmpty
            ? nil
            : nextToken
    }
}

struct PlaylistsView: View {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
    @State private var playlists: [YouTubePlaylistItem] = []
    @State private var continuationToken: String?
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var isSignedIn = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    HStack {
                        Label(L10n.text("playlists", languageCode: appLanguage), systemImage: "rectangle.stack.fill")
                            .font(.largeTitle.bold())

                        Spacer()

                        if isLoading {
                            ProgressView()
                        }
                    }

                    if let errorMessage {
                        VStack(alignment: .leading, spacing: 14) {
                            Label(
                                errorMessage,
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .foregroundStyle(.red)

                            if !isSignedIn {
                                Text(L10n.text("sign_in_hint", languageCode: appLanguage))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 420), spacing: 28)],
                        spacing: 28
                    ) {
                        ForEach(
                            playlists.indices,
                            id: \.self
                        ) { index in
                            let playlist = playlists[index]

                            NavigationLink {
                                PlaylistDetailView(
                                    playlist: playlist
                                )
                            } label: {
                                PlaylistCard(
                                    playlist: playlist
                                )
                            }
                            .buttonStyle(.card)
                            .onAppear {
                                let threshold =
                                    max(
                                        0,
                                        playlists.count - 4
                                    )

                                if index >= threshold {
                                    Task {
                                        await loadMore()
                                    }
                                }
                            }
                        }

                        if isLoadingMore {
                            ProgressView()
                                .frame(
                                    width: 420,
                                    height: 236
                                )
                        }
                    }
                }
                .padding(48)
            }
            .task {
                await load()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .youtubePlaylistsDidChange
                )
            ) { _ in
                Task {
                    await load()
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .youtubeAccountDidChange
                )
            ) { _ in
                Task {
                    await load()
                }
            }
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        isSignedIn =
            await SmartTubeAuthService.shared
                .signedIn()
        defer { isLoading = false }

        do {
            let page =
                try await InnerTubeService.shared
                    .playlistsPage()

            playlists = page.playlists
            continuationToken =
                page.continuationToken

            if playlists.isEmpty {
                errorMessage = L10n.text("youtube_no_playlists", languageCode: appLanguage)
            }
        } catch {
            playlists = []
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadMore() async {
        guard !isLoadingMore,
              let token = continuationToken,
              !token.isEmpty else {
            return
        }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page =
                try await InnerTubeService.shared
                    .continuePlaylists(
                        token
                    )

            var seen = Set(
                playlists.map(\.id)
            )
            let newPlaylists =
                page.playlists.filter {
                    seen.insert($0.id).inserted
                }

            playlists.append(
                contentsOf: newPlaylists
            )

            let nextToken =
                page.continuationToken

            continuationToken =
                nextToken == token
                    && newPlaylists.isEmpty
                ? nil
                : nextToken
        } catch {
            errorMessage =
                error.localizedDescription
        }
    }
}

struct PlaylistDetailView: View {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
    let playlist: YouTubePlaylistItem

    @State private var videos: [VideoItem] = []
    @State private var continuationToken: String?
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                Text(playlist.title)
                    .font(.largeTitle.bold())

                if !playlist.subtitle.isEmpty {
                    Text(playlist.subtitle)
                        .foregroundStyle(.secondary)
                }

                if isLoading {
                    ProgressView(L10n.text("loading_playlist", languageCode: appLanguage))
                }

                if let errorMessage {
                    Label(
                        errorMessage,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.red)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 420), spacing: 28)],
                    spacing: 28
                ) {
                    ForEach(
                        videos.indices,
                        id: \.self
                    ) { index in
                        let video = videos[index]

                        NavigationLink(value: video) {
                            VideoCard(video: video)
                        }
                        .buttonStyle(.card)
                        .onAppear {
                            let threshold =
                                max(
                                    0,
                                    videos.count - 4
                                )

                            if index >= threshold {
                                Task {
                                    await loadMore()
                                }
                            }
                        }
                    }

                    if isLoadingMore {
                        ProgressView()
                            .frame(
                                width: 420,
                                height: 236
                            )
                    }
                }
            }
            .padding(48)
        }
        .navigationDestination(for: VideoItem.self) { video in
            VideoDetailView(video: video)
        }
        .task {
            await load()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .youtubePlaylistsDidChange
            )
        ) { _ in
            Task {
                await load()
            }
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let page =
                try await InnerTubeService.shared
                    .playlistVideosPage(
                        playlist.id
                    )

            videos = page.videos
            continuationToken =
                page.continuationToken

            if videos.isEmpty {
                errorMessage = L10n.text("playlist_empty", languageCode: appLanguage)
            }
        } catch {
            videos = []
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadMore() async {
        guard !isLoadingMore,
              let token = continuationToken,
              !token.isEmpty else {
            return
        }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page =
                try await InnerTubeService.shared
                    .continuePlaylistVideos(
                        token
                    )

            var seen = Set(
                videos.map(\.id)
            )
            let newVideos =
                page.videos.filter {
                    seen.insert($0.id).inserted
                }

            videos.append(
                contentsOf: newVideos
            )

            let nextToken =
                page.continuationToken

            continuationToken =
                nextToken == token
                    && newVideos.isEmpty
                ? nil
                : nextToken
        } catch {
            errorMessage =
                error.localizedDescription
        }
    }
}

struct PlaylistCard: View {
    let playlist: YouTubePlaylistItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(.white.opacity(0.12))

                if let url = playlist.thumbnailURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()

                        case .failure:
                            placeholder

                        case .empty:
                            ProgressView()

                        @unknown default:
                            placeholder
                        }
                    }
                    .frame(width: 420, height: 236)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                } else {
                    placeholder
                }

                Image(systemName: "rectangle.stack.fill")
                    .font(.title)
                    .padding(12)
                    .background(.black.opacity(0.65))
                    .clipShape(Circle())
            }
            .frame(width: 420, height: 236)

            Text(playlist.title)
                .font(.headline)
                .lineLimit(2)
                .frame(width: 420, alignment: .leading)

            if !playlist.subtitle.isEmpty {
                Text(playlist.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var placeholder: some View {
        Image(systemName: "rectangle.stack.fill")
            .font(.system(size: 64))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


struct SubscribedChannelsView: View {
    @AppStorage("appLanguage") private var appLanguage =
        AppLanguage.english.rawValue

    @State private var channels: [YouTubeSubscribedChannel] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isSignedIn = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(
                    alignment: .leading,
                    spacing: 28
                ) {
                    HStack {
                        Label(
                            L10n.text(
                                "channels",
                                languageCode: appLanguage
                            ),
                            systemImage: "rectangle.stack.person.crop.fill"
                        )
                        .font(.largeTitle.bold())

                        Spacer()

                        if isLoading {
                            ProgressView()
                        }
                    }

                    if let errorMessage {
                        VStack(
                            alignment: .leading,
                            spacing: 14
                        ) {
                            Label(
                                errorMessage,
                                systemImage:
                                    "exclamationmark.triangle.fill"
                            )
                            .foregroundStyle(.red)

                            if !isSignedIn {
                                Text(
                                    L10n.text(
                                        "sign_in_hint",
                                        languageCode: appLanguage
                                    )
                                )
                                .foregroundStyle(.secondary)
                            }
                        }
                    }

                    LazyVGrid(
                        columns: [
                            GridItem(
                                .adaptive(
                                    minimum: 260
                                ),
                                spacing: 28
                            )
                        ],
                        spacing: 28
                    ) {
                        ForEach(channels) { channel in
                            NavigationLink {
                                ChannelView(
                                    channelID: channel.id,
                                    fallbackTitle:
                                        channel.title,
                                    reloadPageKey:
                                        channel.reloadPageKey
                                )
                            } label: {
                                VStack(
                                    spacing: 14
                                ) {
                                    Group {
                                        if let url =
                                                channel.thumbnailURL {
                                            AsyncImage(
                                                url: url
                                            ) { phase in
                                                switch phase {
                                                case .success(
                                                    let image
                                                ):
                                                    image
                                                        .resizable()
                                                        .scaledToFill()
                                                case .empty:
                                                    ProgressView()
                                                default:
                                                    Image(
                                                        systemName:
                                                            "person.crop.circle.fill"
                                                    )
                                                    .resizable()
                                                    .scaledToFit()
                                                    .foregroundStyle(
                                                        .secondary
                                                    )
                                                }
                                            }
                                        } else {
                                            Image(
                                                systemName:
                                                    "person.crop.circle.fill"
                                            )
                                            .resizable()
                                            .scaledToFit()
                                            .foregroundStyle(
                                                .secondary
                                            )
                                        }
                                    }
                                    .frame(
                                        width: 210,
                                        height: 210
                                    )
                                    .clipShape(Circle())

                                    Text(channel.title)
                                        .font(.headline)
                                        .lineLimit(2)
                                        .multilineTextAlignment(
                                            .center
                                        )
                                        .frame(
                                            width: 240
                                        )
                                }
                                .padding(16)
                            }
                            .buttonStyle(.card)
                        }
                    }
                }
                .padding(48)
            }
            .task {
                await load()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .youtubeSubscriptionsDidChange
                )
            ) { _ in
                Task {
                    await load()
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .youtubeAccountDidChange
                )
            ) { _ in
                Task {
                    await load()
                }
            }
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        isSignedIn =
            await SmartTubeAuthService.shared
                .signedIn()
        defer { isLoading = false }

        do {
            channels =
                try await InnerTubeService.shared
                    .subscribedChannels()

            if channels.isEmpty {
                errorMessage =
                    L10n.text(
                        "youtube_no_channels",
                        languageCode: appLanguage
                    )
            }
        } catch {
            channels = []
            errorMessage =
                error.localizedDescription
        }
    }
}
