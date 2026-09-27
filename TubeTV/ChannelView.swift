import SwiftUI

struct ChannelView: View {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
    let channelID: String
    let fallbackTitle: String

    @State private var page: YouTubeChannelPage?
    @State private var continuationToken: String?
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                HStack(spacing: 24) {
                    Group {
                        if let avatarURL = page?.avatarURL {
                            AsyncImage(url: avatarURL) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                case .empty:
                                    ProgressView()
                                default:
                                    Image(systemName: "person.crop.circle.fill")
                                        .resizable()
                                        .scaledToFit()
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 150, height: 150)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 12) {
                        Text(page?.title ?? fallbackTitle)
                            .font(.largeTitle.bold())

                        if let description = page?.description,
                           !description.isEmpty {
                            Text(description)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .lineLimit(4)
                                .frame(maxWidth: 1200, alignment: .leading)
                        }

                        if isLoading {
                            ProgressView(L10n.text("loading_channel", languageCode: appLanguage))
                        }
                    }
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }

                if let videos = page?.videos,
                   !videos.isEmpty {
                    Text(L10n.text("videos", languageCode: appLanguage))
                        .font(.title2.bold())

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
            }
            .padding(48)
        }
        .navigationDestination(for: VideoItem.self) { video in
            VideoDetailView(video: video)
        }
        .task {
            await loadChannel()
        }
    }

    @MainActor
    private func loadChannel() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            if await SmartTubeAuthService.shared.signedIn() {
                do {
                    let result =
                        try await InnerTubeService.shared
                            .channelPage(
                                channelID
                            )

                    page = result.page
                    continuationToken =
                        result.continuationToken
                } catch {
                    page =
                        try await YouTubeService.shared
                            .channel(
                                channelID
                            )
                    continuationToken = nil
                }
            } else {
                page =
                    try await YouTubeService.shared
                        .channel(
                            channelID
                        )
                continuationToken = nil
            }

            if page?.videos.isEmpty == true {
                errorMessage = L10n.text("channel_no_videos", languageCode: appLanguage)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadMore() async {
        guard !isLoadingMore,
              let token = continuationToken,
              !token.isEmpty,
              let currentPage = page else {
            return
        }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let result =
                try await InnerTubeService.shared
                    .continueChannelVideos(
                        token
                    )

            var seen = Set(
                currentPage.videos.map(\.id)
            )
            let newVideos =
                result.videos.filter {
                    seen.insert($0.id).inserted
                }

            page = YouTubeChannelPage(
                id: currentPage.id,
                title: currentPage.title,
                description: currentPage.description,
                avatarURL: currentPage.avatarURL,
                videos:
                    currentPage.videos
                    + newVideos
            )

            let nextToken =
                result.continuationToken

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
