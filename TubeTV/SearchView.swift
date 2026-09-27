import SwiftUI

struct SearchView: View {
    let requestedQuery: String?

    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
    @State private var query = ""
    @State private var results: [VideoItem] = []
    @State private var continuationToken: String?
    @State private var isSearching = false
    @State private var isLoadingMore = false
    @State private var searchGeneration = UUID()
    @State private var errorMessage: String?

    init(
        requestedQuery: String? = nil
    ) {
        self.requestedQuery =
            requestedQuery
    }

    private var directVideoID: String? {
        StreamResolver.videoID(from: query)
    }

    private var visibleResults: [VideoItem] {
        query.isEmpty
            ? VideoItem.demo(languageCode: appLanguage)
            : results
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 28) {
                Text(L10n.text("search", languageCode: appLanguage))
                    .font(.largeTitle.bold())

                HStack(spacing: 18) {
                    TextField(L10n.text("search_placeholder", languageCode: appLanguage), text: $query)
                        .onSubmit {
                            Task { await runSearch() }
                        }

                    if directVideoID == nil {
                        Button {
                            Task { await runSearch() }
                        } label: {
                            if isSearching {
                                ProgressView()
                            } else {
                                Label(L10n.text("search", languageCode: appLanguage), systemImage: "magnifyingglass")
                            }
                        }
                        .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                    }
                }

                if let videoID = directVideoID {
                    NavigationLink(value: VideoItem.youtube(videoID: videoID)) {
                        Label(L10n.text("play_pasted_video", languageCode: appLanguage), systemImage: "play.rectangle.fill")
                            .font(.title2.bold())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }

                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 420), spacing: 28)],
                        spacing: 28
                    ) {
                        ForEach(
                            visibleResults.indices,
                            id: \.self
                        ) { index in
                            let video =
                                visibleResults[index]

                            NavigationLink(value: video) {
                                VideoCard(video: video)
                            }
                            .buttonStyle(.card)
                            .onAppear {
                                guard !query.isEmpty,
                                      index
                                        >= max(
                                            0,
                                            results.count - 4
                                        ) else {
                                    return
                                }

                                let generation =
                                    searchGeneration

                                Task {
                                    await loadMore(
                                        generation:
                                            generation
                                    )
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
            .navigationDestination(for: VideoItem.self) { video in
                VideoDetailView(video: video)
            }
            .task(id: requestedQuery) {
                guard let requestedQuery else {
                    return
                }

                let trimmed =
                    requestedQuery
                        .trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        )

                guard !trimmed.isEmpty else {
                    return
                }

                query = trimmed
                await runSearch()
            }
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
        defer { isSearching = false }

        do {
            let page =
                try await InnerTubeService.shared
                    .searchPage(trimmed)

            guard generation
                    == searchGeneration else {
                return
            }

            results = page.videos
            continuationToken =
                page.continuationToken

            if results.isEmpty {
                errorMessage = L10n.text(
                    "youtube_no_videos",
                    languageCode:
                        appLanguage
                )
            }
        } catch {
            guard generation
                    == searchGeneration else {
                return
            }

            results = []
            continuationToken = nil
            errorMessage =
                error.localizedDescription
        }
    }

    @MainActor
    private func loadMore(
        generation: UUID
    ) async {
        guard generation
                == searchGeneration,
              !isSearching,
              !isLoadingMore,
              let token =
                continuationToken,
              !token.isEmpty else {
            return
        }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page =
                try await InnerTubeService.shared
                    .continueSearch(
                        token
                    )

            guard generation
                    == searchGeneration else {
                return
            }

            var seen = Set(
                results.map(\.id)
            )
            let newVideos =
                page.videos.filter {
                    seen.insert(
                        $0.id
                    ).inserted
                }

            results.append(
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
            guard generation
                    == searchGeneration else {
                return
            }

            errorMessage =
                error.localizedDescription
        }
    }
}
