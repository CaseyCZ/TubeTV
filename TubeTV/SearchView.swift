import SwiftUI

struct SearchView: View {
    @State private var query = ""

    private var directVideoID: String? {
        StreamResolver.videoID(from: query)
    }

    private var results: [VideoItem] {
        guard !query.isEmpty else { return VideoItem.demo }

        return VideoItem.demo.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.channel.localizedCaseInsensitiveContains(query) ||
            $0.subtitle.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 28) {
                Text("Hledat")
                    .font(.largeTitle.bold())

                TextField("Hledat nebo vložit YouTube URL / video ID", text: $query)
                    .textFieldStyle(.roundedBorder)

                if let videoID = directVideoID {
                    NavigationLink(value: VideoItem.youtube(videoID: videoID)) {
                        Label("Přehrát YouTube video", systemImage: "play.rectangle.fill")
                            .font(.title2.bold())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderedProminent)
                }

                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 420), spacing: 28)],
                        spacing: 28
                    ) {
                        ForEach(results) { video in
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
}
