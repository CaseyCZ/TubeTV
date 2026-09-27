import SwiftUI

struct SearchView: View {
    @State private var query = ""
    @State private var results: [VideoItem] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    private var directVideoID: String? {
        StreamResolver.videoID(from: query)
    }

    private var visibleResults: [VideoItem] {
        query.isEmpty ? VideoItem.demo : results
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 28) {
                Text("Hledat")
                    .font(.largeTitle.bold())

                HStack(spacing: 18) {
                    TextField("Hledat na YouTube nebo vložit URL / video ID", text: $query)
                        .textFieldStyle(.roundedBorder)
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
                                Label("Hledat", systemImage: "magnifyingglass")
                            }
                        }
                        .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                    }
                }

                if let videoID = directVideoID {
                    NavigationLink(value: VideoItem.youtube(videoID: videoID)) {
                        Label("Přehrát vložené YouTube video", systemImage: "play.rectangle.fill")
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
                errorMessage = "YouTube nevrátil žádná videa."
            }
        } catch {
            results = []
            errorMessage = error.localizedDescription
        }
    }
}
