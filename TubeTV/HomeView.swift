import SwiftUI

struct HomeView: View {
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
                LazyVStack(alignment: .leading, spacing: 44) {
                    HStack {
                        Text(L10n.text("home", languageCode: appLanguage))
                            .font(.largeTitle.bold())

                        Spacer()

                        if isLoading {
                            ProgressView()
                        }
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }

                    if sections.isEmpty && !isLoading {
                        VideoRow(
                            title: "TubeTV",
                            videos: VideoItem.demo(languageCode: appLanguage)
                        )
                    } else {
                        ForEach(sections) { section in
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
                        }
                    }
                }
                .padding(48)
            }
            .navigationDestination(for: VideoItem.self) { video in
                VideoDetailView(video: video)
            }
            .task {
                await loadHome()
            }
            .onChange(of: scenePhase) { newPhase in
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
                        continuationToken: nil
                    )
                ]
                homeContinuationToken = nil
            }

            if sections.allSatisfy({ $0.videos.isEmpty }) {
                errorMessage = L10n.text(
                    "youtube_no_videos",
                    languageCode: appLanguage
                )
            } else {
                lastLoadedAt = Date()

                if homeContinuationToken != nil {
                    Task {
                        await loadRemainingHomeSections(
                            generation: generation
                        )
                    }
                }
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
              !isLoadingMoreHomeSections else {
            return
        }

        isLoadingMoreHomeSections = true
        defer {
            isLoadingMoreHomeSections = false
        }

        while let token = homeContinuationToken,
              !token.isEmpty {
            do {
                let result =
                    try await InnerTubeService.shared
                        .continueHomePage(
                            token
                        )

                guard generation
                        == homeLoadGeneration else {
                    break
                }

                var seen = Set(
                    sections.map(\.id)
                )
                let newSections =
                    result.sections.filter {
                        seen.insert($0.id).inserted
                    }

                sections.append(
                    contentsOf: newSections
                )

                let nextToken =
                    result.continuationToken

                if nextToken == token
                    && newSections.isEmpty {
                    homeContinuationToken = nil
                    break
                }

                homeContinuationToken =
                    nextToken
            } catch {
                errorMessage =
                    error.localizedDescription
                break
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
                    continuationToken:
                        nextToken == token
                            && newVideos.isEmpty
                        ? nil
                        : nextToken
                )
        } catch {
            errorMessage =
                error.localizedDescription
        }
    }
}

struct VideoRow: View {
    let title: String
    let videos: [VideoItem]
    var isLoadingMore = false
    var onLoadMore: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.title2.bold())

            ScrollView(
                .horizontal,
                showsIndicators: false
            ) {
                LazyHStack(spacing: 28) {
                    ForEach(
                        videos.indices,
                        id: \.self
                    ) { index in
                        let video =
                            videos[index]

                        NavigationLink(
                            value: video
                        ) {
                            VideoCard(
                                video: video
                            )
                        }
                        .buttonStyle(.card)
                        .onAppear {
                            let threshold =
                                max(
                                    0,
                                    videos.count - 4
                                )

                            if index >= threshold {
                                onLoadMore?()
                            }
                        }
                    }

                    if isLoadingMore {
                        ProgressView()
                            .frame(
                                width: 96,
                                height: 236
                            )
                    }
                }
            }
        }
    }
}

struct VideoCard: View {
    let video: VideoItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 18)
                    .fill(.white.opacity(0.12))

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

                if video.playbackURL != nil {
                    Text(L10n.text("test"))
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.75))
                        .clipShape(Capsule())
                        .padding(14)
                }
            }
            .frame(width: 420, height: 236)

            Text(video.title)
                .font(.headline)
                .lineLimit(2)
                .frame(width: 420, alignment: .leading)

            Text(video.channel)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if !video.subtitle.isEmpty {
                Text(video.subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    private var placeholder: some View {
        Image(systemName: "play.rectangle.fill")
            .font(.system(size: 64))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
