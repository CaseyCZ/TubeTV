import SwiftUI

struct SearchView: View {
    let requestedQuery: String?

    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
    @State private var query = ""
    @State private var results: [YouTubeSearchResultItem] = []
    @State private var continuationToken: String?
    @State private var isSearching = false
    @State private var isLoadingMore = false
    @State private var searchGeneration = UUID()
    @State private var errorMessage: String?
    @FocusState private var isSearchFieldFocused: Bool

    init(
        requestedQuery: String? = nil
    ) {
        self.requestedQuery = requestedQuery
    }

    private var directVideoID: String? {
        StreamResolver.videoID(from: query)
    }

    private var visibleResults: [YouTubeSearchResultItem] {
        results
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("TUBETV · DISCOVER")
                        .font(.caption.weight(.heavy))
                        .tracking(1.2)
                        .foregroundStyle(TubeTVTheme.accent)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .background(
                            TubeTVTheme.accent.opacity(0.10),
                            in: Capsule()
                        )
                        .overlay {
                            Capsule()
                                .strokeBorder(
                                    TubeTVTheme.accent.opacity(0.34),
                                    lineWidth: 1
                                )
                        }

                    Text(L10n.text("search", languageCode: appLanguage))
                        .font(.system(size: 54, weight: .bold))
                        .tracking(-1.8)
                }

                HStack(spacing: 16) {
                    TextField(
                        L10n.text(
                            "search_placeholder",
                            languageCode: appLanguage
                        ),
                        text: $query
                    )
                    .focused($isSearchFieldFocused)
                    .defaultFocus(
                        $isSearchFieldFocused,
                        true
                    )
                    .submitLabel(.search)
                    .onSubmit {
                        isSearchFieldFocused = false

                        Task {
                            await runSearch()
                        }
                    }

                    if directVideoID == nil {
                        Button {
                            Task { await runSearch() }
                        } label: {
                            if isSearching {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Label(
                                    L10n.text(
                                        "search",
                                        languageCode: appLanguage
                                    ),
                                    systemImage: "magnifyingglass"
                                )
                                .font(.headline.weight(.bold))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(TubeTVTheme.action)
                        .disabled(
                            query
                                .trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                )
                                .isEmpty
                                || isSearching
                        )
                    }
                }
                .padding(14)
                .background(
                    TubeTVTheme.panel.opacity(0.84),
                    in: RoundedRectangle(
                        cornerRadius: 20,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 20,
                        style: .continuous
                    )
                    .strokeBorder(
                        TubeTVTheme.border.opacity(0.72),
                        lineWidth: 1
                    )
                }

                if let videoID = directVideoID {
                    NavigationLink(
                        value: VideoItem.youtube(videoID: videoID)
                    ) {
                        Label(
                            L10n.text(
                                "play_pasted_video",
                                languageCode: appLanguage
                            ),
                            systemImage: "play.rectangle.fill"
                        )
                        .font(.title2.bold())
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(TubeTVTheme.action)
                }

                if let errorMessage {
                    Label(
                        errorMessage,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.headline)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(
                        TubeTVTheme.panel.opacity(0.92),
                        in: RoundedRectangle(
                            cornerRadius: 16,
                            style: .continuous
                        )
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: 16,
                            style: .continuous
                        )
                        .strokeBorder(
                            Color.red.opacity(0.30),
                            lineWidth: 1
                        )
                    }
                }

                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(
                                .adaptive(minimum: 420),
                                spacing: 24
                            )
                        ],
                        spacing: 24
                    ) {
                        ForEach(
                            visibleResults.indices,
                            id: \.self
                        ) { index in
                            let item = visibleResults[index]

                            searchResultView(item)
                                .onAppear {
                                    guard !query.isEmpty,
                                          index >= max(
                                            0,
                                            results.count - 4
                                          ) else {
                                        return
                                    }

                                    let generation = searchGeneration

                                    Task {
                                        await loadMore(
                                            generation: generation
                                        )
                                    }
                                }
                        }

                        if isLoadingMore {
                            ProgressView()
                                .tint(TubeTVTheme.accent)
                                .frame(
                                    width: 420,
                                    height: 236
                                )
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 52)
            .padding(.top, 42)
            .padding(.bottom, 48)
            .navigationDestination(for: VideoItem.self) { video in
                VideoDetailView(video: video)
            }
            .task(id: requestedQuery) {
                if let requestedQuery {
                    let trimmed =
                        requestedQuery
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )

                    guard !trimmed.isEmpty else {
                        return
                    }

                    query = trimmed
                    isSearchFieldFocused = false
                    await runSearch()
                    return
                }

                // On tvOS the sidebar otherwise keeps focus and the
                // search field cannot be reached reliably with the remote.
                // Give the field focus after the view has entered the
                // hierarchy so the system keyboard opens immediately.
                await Task.yield()
                isSearchFieldFocused = true
            }
        }
    }

    @ViewBuilder
    private func searchResultView(
        _ item: YouTubeSearchResultItem
    ) -> some View {
        switch item {
        case .video(let video):
            NavigationLink(value: video) {
                VideoCard(video: video)
            }
            .buttonStyle(.plain)

        case .channel(let channel):
            NavigationLink {
                ChannelView(
                    channelID: channel.id,
                    fallbackTitle: channel.title
                )
            } label: {
                SearchChannelCard(channel: channel)
            }
            .buttonStyle(.plain)

        case .playlist(let playlist):
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
        }
    }

    @MainActor
    private func runSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty, directVideoID == nil else {
            return
        }

        let generation = UUID()
        searchGeneration = generation
        isSearching = true
        isLoadingMore = false
        continuationToken = nil
        errorMessage = nil
        defer {
            if generation == searchGeneration {
                isSearching = false
            }
        }

        do {
            let page =
                try await InnerTubeService.shared
                    .searchPage(trimmed)

            guard generation
                    == searchGeneration else {
                return
            }

            results = page.items
            continuationToken = page.continuationToken

            if results.isEmpty {
                errorMessage = L10n.text(
                    "youtube_no_videos",
                    languageCode: appLanguage
                )
            }
        } catch {
            guard generation
                    == searchGeneration else {
                return
            }

            results = []
            continuationToken = nil
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadMore(
        generation: UUID
    ) async {
        guard generation == searchGeneration,
              !isSearching,
              !isLoadingMore,
              let token = continuationToken,
              !token.isEmpty else {
            return
        }

        isLoadingMore = true
        defer {
            if generation == searchGeneration {
                isLoadingMore = false
            }
        }

        do {
            let page =
                try await InnerTubeService.shared
                    .continueSearch(token)

            guard generation
                    == searchGeneration else {
                return
            }

            var seen = Set(results.map(\.id))
            let newItems =
                page.items.filter {
                    seen.insert($0.id).inserted
                }

            results.append(contentsOf: newItems)

            let nextToken = page.continuationToken

            continuationToken =
                nextToken == token
                    && newItems.isEmpty
                ? nil
                : nextToken
        } catch {
            guard generation
                    == searchGeneration else {
                return
            }

            errorMessage = error.localizedDescription
        }
    }
}

private struct SearchChannelCard: View {
    @Environment(\.isFocused) private var isFocused

    let channel: YouTubeSubscribedChannel

    var body: some View {
        VStack(spacing: 16) {
            Group {
                if let url = channel.thumbnailURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .empty:
                            ProgressView()
                                .tint(TubeTVTheme.accent)
                        default:
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .frame(width: 210, height: 210)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .strokeBorder(
                        isFocused
                            ? TubeTVTheme.accent
                            : TubeTVTheme.border.opacity(0.76),
                        lineWidth: isFocused ? 5 : 2
                    )
            }

            Text(channel.title)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
        }
        .frame(minWidth: 300, minHeight: 280)
        .padding(18)
        .background(
            TubeTVTheme.panel.opacity(
                isFocused ? 0.95 : 0.78
            ),
            in: RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
            .strokeBorder(
                isFocused
                    ? TubeTVTheme.accent.opacity(0.88)
                    : TubeTVTheme.border.opacity(0.55),
                lineWidth: isFocused ? 3 : 1
            )
        }
        .scaleEffect(isFocused ? 1.035 : 1.0)
        .shadow(
            color:
                isFocused
                ? TubeTVTheme.accent.opacity(0.20)
                : Color.black.opacity(0.18),
            radius: isFocused ? 22 : 12,
            y: 8
        )
        .animation(
            .easeOut(duration: 0.13),
            value: isFocused
        )
    }

    private var placeholder: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(TubeTVTheme.accent.opacity(0.68))
    }
}
