import SwiftUI

struct SearchView: View {
    let requestedQuery: String?

    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
    @State private var query = ""
    @State private var results: [VideoItem] = []
    @State private var isSearching = false
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
                        ForEach(visibleResults) { video in
                            NavigationLink(value: video) {
                                VideoCard(video: video)
                            }
                            .buttonStyle(.card)
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

        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        do {
            results = try await YouTubeService.shared.search(query: trimmed)

            if results.isEmpty {
                errorMessage = L10n.text("youtube_no_videos", languageCode: appLanguage)
            }
        } catch {
            results = []
            errorMessage = error.localizedDescription
        }
    }
}
