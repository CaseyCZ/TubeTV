import SwiftUI

struct HomeView: View {
    var onSearch: (String) -> Void = { _ in }

    private static let refreshInterval: TimeInterval =
        3 * 60 * 60

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
    @State private var sections: [YouTubeHomeSection] = []
    @State private var loadingSectionIDs = Set<String>()
    @State private var homeContinuationToken: String?
    @State private var isLoadingMoreHomeSections = false
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var lastLoadedAt: Date?
    @State private var homeLoadGeneration = UUID()

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 42) {
                    HStack(alignment: .bottom, spacing: 24) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("TUBETV · YOUTUBE")
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

                            Text(L10n.text("home", languageCode: appLanguage))
                                .font(.system(size: 54, weight: .bold))
                                .tracking(-1.8)
                        }

                        Spacer()

                        if isLoading {
                            ProgressView()
                                .tint(TubeTVTheme.accent)
                                .padding(14)
                                .background(
                                    TubeTVTheme.panel.opacity(0.88),
                                    in: RoundedRectangle(
                                        cornerRadius: 16,
                                        style: .continuous
                                    )
                                )
                        }
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

                    ForEach(sections) { section in
                        if !section.videos.isEmpty {
                            VideoRow(
                                title:
                                    section.title.isEmpty
                                    ? L10n.text(
                                        "recommended",
                                        languageCode: appLanguage
                                    )
                                    : section.title,
                                videos: section.videos,
                                isLoadingMore:
                                    loadingSectionIDs
                                        .contains(
                                            section.id
                                        )
                            ) {
                                Task {
                                    await loadMore(
                                        sectionID:
                                            section.id
                                    )
                                }
                            }
                        } else if !section.searchTiles.isEmpty {
                            HomeSearchTileRow(
                                title:
                                    section.title.isEmpty
                                    ? L10n.text(
                                        "search",
                                        languageCode: appLanguage
                                    )
                                    : section.title,
                                tiles:
                                    section.searchTiles,
                                onSearch: onSearch
                            )
                        }
                    }

                    if let token = homeContinuationToken,
                       !token.isEmpty {
                        HStack {
                            Spacer()

                            ProgressView()
                                .tint(TubeTVTheme.accent)
                                .padding(16)
                                .background(
                                    TubeTVTheme.panel.opacity(0.76),
                                    in: RoundedRectangle(
                                        cornerRadius: 16,
                                        style: .continuous
                                    )
                                )

                            Spacer()
                        }
                        .frame(height: 84)
                        .id(token)
                        .onAppear {
                            let generation = homeLoadGeneration

                            Task {
                                await loadRemainingHomeSections(
                                    generation: generation
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 52)
                .padding(.top, 42)
                .padding(.bottom, 56)
            }
            .navigationDestination(for: VideoItem.self) { video in
                VideoDetailView(video: video)
            }
            .task {
                await loadHome()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else {
                    return
                }

                Task {
                    await refreshHomeIfStale()
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .youtubeAccountDidChange
                )
            ) { _ in
                Task {
                    await reloadHomeForAccountChange()
                }
            }
        }
    }

    @MainActor
    private func reloadHomeForAccountChange() async {
        lastLoadedAt = nil
        homeContinuationToken = nil
        loadingSectionIDs.removeAll()

        await loadHome(force: true)
    }

    @MainActor
    private func refreshHomeIfStale() async {
        guard let lastLoadedAt else {
            await loadHome()
            return
        }

        guard Date()
                .timeIntervalSince(lastLoadedAt)
                >= Self.refreshInterval else {
            return
        }

        await loadHome(force: true)
    }

    @MainActor
    private func loadHome(
        force: Bool = false
    ) async {
        guard force || sections.isEmpty else { return }

        let generation = UUID()
        homeLoadGeneration = generation

        if force {
            isLoadingMoreHomeSections = false
        }

        isLoading = true
        errorMessage = nil
        defer {
            if generation == homeLoadGeneration {
                isLoading = false
            }
        }

        do {
            do {
                // SmartTube uses the TV InnerTube Home for signed-in
                // and anonymous browsing.
                let page =
                    try await InnerTubeService.shared
                        .homePage()

                guard generation
                        == homeLoadGeneration else {
                    return
                }

                sections = page.sections
                homeContinuationToken =
                    page.continuationToken
            } catch {
                // Keep the public web parser only as a last-resort fallback.
                let videos =
                    try await YouTubeService.shared.home()

                guard generation
                        == homeLoadGeneration else {
                    return
                }

                sections = [
                    YouTubeHomeSection(
                        id: "web-fallback",
                        title: L10n.text(
                            "recommended",
                            languageCode: appLanguage
                        ),
                        videos: videos,
                        searchTiles: [],
                        continuationToken: nil
                    )
                ]
                homeContinuationToken = nil
            }

            if sections.allSatisfy({
                $0.videos.isEmpty
                    && $0.searchTiles.isEmpty
            }) {
                errorMessage = L10n.text(
                    "youtube_no_videos",
                    languageCode: appLanguage
                )
            } else {
                // The first usable Home page is enough to render immediately.
                // Remaining global continuations now load only when the user
                // reaches the end of the currently visible Home feed so they
                // do not compete with playback startup in the background.
                errorMessage = nil
                lastLoadedAt = Date()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadRemainingHomeSections(
        generation: UUID
    ) async {
        guard generation == homeLoadGeneration,
              !isLoadingMoreHomeSections,
              let token = homeContinuationToken,
              !token.isEmpty else {
            return
        }

        isLoadingMoreHomeSections = true
        defer {
            isLoadingMoreHomeSections = false
        }

        do {
            let result =
                try await InnerTubeService.shared
                    .continueHomePage(token)

            guard generation == homeLoadGeneration else {
                return
            }

            var seen = Set(sections.map(\.id))
            let newSections =
                result.sections.filter {
                    seen.insert($0.id).inserted
                }

            sections.append(contentsOf: newSections)

            let nextToken = result.continuationToken

            if nextToken == token
                && newSections.isEmpty {
                homeContinuationToken = nil
            } else {
                homeContinuationToken = nextToken
            }
        } catch {
            // The first Home page is already usable. A failed lazy
            // continuation simply ends the feed instead of replacing visible
            // content with a fatal account error.
            homeContinuationToken = nil

            let hasVisibleContent =
                sections.contains {
                    !$0.videos.isEmpty
                        || !$0.searchTiles.isEmpty
                }

            if !hasVisibleContent {
                errorMessage = error.localizedDescription
            } else {
                errorMessage = nil
            }
        }
    }

    @MainActor
    private func loadMore(
        sectionID: String
    ) async {
        guard !loadingSectionIDs
                .contains(sectionID),
              let index =
                sections.firstIndex(
                    where: {
                        $0.id == sectionID
                    }
                ),
              let token =
                sections[index]
                    .continuationToken,
              !token.isEmpty else {
            return
        }

        loadingSectionIDs.insert(sectionID)
        defer {
            loadingSectionIDs.remove(sectionID)
        }

        do {
            let result =
                try await InnerTubeService.shared
                    .continueHomeSection(
                        token
                    )

            var seen = Set(
                sections[index]
                    .videos
                    .map(\.id)
            )
            let newVideos =
                result.videos.filter {
                    seen.insert($0.id).inserted
                }

            let nextToken =
                result.continuationToken

            sections[index] =
                YouTubeHomeSection(
                    id:
                        sections[index].id,
                    title:
                        sections[index].title,
                    videos:
                        sections[index].videos
                        + newVideos,
                    searchTiles:
                        sections[index].searchTiles,
                    continuationToken:
                        nextToken == token
                            && newVideos.isEmpty
                        ? nil
                        : nextToken
                )
        } catch {
            // Keep the already loaded row usable. A failed "load more"
            // request should not show a global account error over valid Home
            // content or retrigger endlessly when focus reaches the row end.
            let current =
                sections[index]

            sections[index] =
                YouTubeHomeSection(
                    id: current.id,
                    title: current.title,
                    videos: current.videos,
                    searchTiles:
                        current.searchTiles,
                    continuationToken: nil
                )

            let hasVisibleContent =
                sections.contains {
                    !$0.videos.isEmpty
                        || !$0.searchTiles.isEmpty
                }

            if !hasVisibleContent {
                errorMessage =
                    error.localizedDescription
            } else {
                errorMessage = nil
            }
        }
    }
}

struct HomeSearchTileRow: View {
    let title: String
    let tiles: [YouTubeSearchTile]
    let onSearch: (String) -> Void

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 18
        ) {
            TubeTVSectionTitle(title: title)

            ScrollView(
                .horizontal,
                showsIndicators: false
            ) {
                LazyHStack(spacing: 24) {
                    ForEach(tiles) { tile in
                        Button {
                            onSearch(tile.query)
                        } label: {
                            HomeSearchTileCard(tile: tile)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 12)
            }
        }
        .focusSection()
    }
}

struct VideoRow: View {
    let title: String
    let videos: [VideoItem]
    var isLoadingMore = false
    var onLoadMore: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TubeTVSectionTitle(title: title)

            ScrollView(
                .horizontal,
                showsIndicators: false
            ) {
                LazyHStack(spacing: 24) {
                    ForEach(videos) { video in
                        NavigationLink(
                            value: video
                        ) {
                            VideoCard(video: video)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            let nearEndIDs =
                                videos
                                    .suffix(4)
                                    .map(\.id)

                            if nearEndIDs.contains(video.id) {
                                onLoadMore?()
                            }
                        }
                    }

                    if isLoadingMore {
                        ProgressView()
                            .tint(TubeTVTheme.accent)
                            .frame(
                                width: 96,
                                height: 236
                            )
                    }
                }
                .padding(.vertical, 14)
            }
        }
        .focusSection()
    }
}

struct TubeTVSectionTitle: View {
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(
                cornerRadius: 2,
                style: .continuous
            )
            .fill(TubeTVTheme.accent)
            .frame(width: 5, height: 26)

            Text(title)
                .font(.title2.bold())
                .tracking(-0.4)
        }
    }
}

private struct HomeSearchTileCard: View {
    @Environment(\.isFocused) private var isFocused

    let tile: YouTubeSearchTile

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
                .fill(TubeTVTheme.panelRaised)

                if let thumbnailURL = tile.thumbnailURL {
                    AsyncImage(url: thumbnailURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            searchPlaceholder
                        case .empty:
                            ProgressView()
                                .tint(TubeTVTheme.accent)
                        @unknown default:
                            searchPlaceholder
                        }
                    }
                } else {
                    searchPlaceholder
                }
            }
            .frame(width: 320, height: 180)
            .clipped()
            .clipShape(
                RoundedRectangle(
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
                    isFocused
                        ? TubeTVTheme.accent
                        : TubeTVTheme.border.opacity(0.72),
                    lineWidth: isFocused ? 4 : 1
                )
            }

            Text(tile.title)
                .font(.headline)
                .lineLimit(2)
                .frame(
                    width: 320,
                    alignment: .leading
                )
        }
        .scaleEffect(isFocused ? 1.035 : 1.0)
        .shadow(
            color:
                isFocused
                ? TubeTVTheme.accent.opacity(0.20)
                : Color.black.opacity(0.22),
            radius: isFocused ? 22 : 12,
            y: 8
        )
        .animation(
            .easeOut(duration: 0.13),
            value: isFocused
        )
    }

    private var searchPlaceholder: some View {
        Image(systemName: "magnifyingglass")
            .font(.system(size: 56, weight: .semibold))
            .foregroundStyle(TubeTVTheme.accent)
    }
}

struct VideoCard: View {
    @Environment(\.isFocused) private var isFocused
    let video: VideoItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
                .fill(TubeTVTheme.panelRaised)

                if let thumbnailURL = video.thumbnailURL {
                    AsyncImage(url: thumbnailURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()

                        case .failure:
                            placeholder

                        case .empty:
                            ProgressView()
                                .tint(TubeTVTheme.accent)

                        @unknown default:
                            placeholder
                        }
                    }
                    .frame(width: 420, height: 236)
                    .clipped()
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 20,
                            style: .continuous
                        )
                    )
                } else {
                    placeholder
                }

                if video.playbackURL != nil {
                    Text(L10n.text("test"))
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            TubeTVTheme.action.opacity(0.94),
                            in: Capsule()
                        )
                        .padding(14)
                }
            }
            .frame(width: 420, height: 236)
            .overlay {
                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
                .strokeBorder(
                    isFocused
                        ? TubeTVTheme.accent
                        : TubeTVTheme.border.opacity(0.74),
                    lineWidth: isFocused ? 4 : 1
                )
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(video.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(video.channel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        isFocused
                            ? TubeTVTheme.accent
                            : Color.white.opacity(0.62)
                    )
                    .lineLimit(1)

                if !video.subtitle.isEmpty {
                    Text(video.subtitle)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(
                width: 420,
                alignment: .leading
            )
            .background(
                TubeTVTheme.panel.opacity(
                    isFocused ? 0.94 : 0.74
                ),
                in: RoundedRectangle(
                    cornerRadius: 15,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 15,
                    style: .continuous
                )
                .strokeBorder(
                    isFocused
                        ? TubeTVTheme.accent.opacity(0.22)
                        : TubeTVTheme.border.opacity(0.38),
                    lineWidth: 1
                )
            }
        }
        .scaleEffect(isFocused ? 1.025 : 1.0)
        .shadow(
            color:
                isFocused
                ? TubeTVTheme.accent.opacity(0.22)
                : Color.black.opacity(0.20),
            radius: isFocused ? 24 : 14,
            y: 9
        )
        .animation(
            .easeOut(duration: 0.13),
            value: isFocused
        )
    }

    private var placeholder: some View {
        Image(systemName: "play.rectangle.fill")
            .font(.system(size: 64))
            .foregroundStyle(TubeTVTheme.accent.opacity(0.70))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
