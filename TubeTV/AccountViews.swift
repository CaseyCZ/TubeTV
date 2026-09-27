import SwiftUI

struct AccountFeedView: View {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
    let kind: AccountFeedKind

    @State private var videos: [VideoItem] = []
    @State private var continuationToken: String?
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var errorMessage: String?

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

                            Text(L10n.text("sign_in_hint", languageCode: appLanguage))
                                .foregroundStyle(.secondary)
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
                                guard kind == .subscriptions else {
                                    return
                                }

                                let threshold =
                                    max(
                                        0,
                                        videos.count - 4
                                    )

                                if index >= threshold {
                                    Task {
                                        await loadMoreSubscriptions()
                                    }
                                }
                            }
                        }

                        if kind == .subscriptions
                            && isLoadingMore {
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
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            if kind == .subscriptions {
                let page =
                    try await InnerTubeService.shared
                        .subscriptionsPage()

                videos = page.videos
                continuationToken =
                    page.continuationToken
            } else {
                videos =
                    try await InnerTubeService.shared
                        .videos(for: kind)
                continuationToken = nil
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

struct PlaylistsView: View {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
    @State private var playlists: [YouTubePlaylistItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

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

                            Text(L10n.text("sign_in_hint", languageCode: appLanguage))
                                .foregroundStyle(.secondary)
                        }
                    }

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 420), spacing: 28)],
                        spacing: 28
                    ) {
                        ForEach(playlists) { playlist in
                            NavigationLink {
                                PlaylistDetailView(playlist: playlist)
                            } label: {
                                PlaylistCard(playlist: playlist)
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
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            playlists = try await InnerTubeService.shared.playlists()

            if playlists.isEmpty {
                errorMessage = L10n.text("youtube_no_playlists", languageCode: appLanguage)
            }
        } catch {
            playlists = []
            errorMessage = error.localizedDescription
        }
    }
}

struct PlaylistDetailView: View {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
    let playlist: YouTubePlaylistItem

    @State private var videos: [VideoItem] = []
    @State private var isLoading = true
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
                    ForEach(videos) { video in
                        NavigationLink(value: video) {
                            VideoCard(video: video)
                        }
                        .buttonStyle(.card)
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
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            videos = try await InnerTubeService.shared.playlistVideos(playlist.id)

            if videos.isEmpty {
                errorMessage = L10n.text("playlist_empty", languageCode: appLanguage)
            }
        } catch {
            videos = []
            errorMessage = error.localizedDescription
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
