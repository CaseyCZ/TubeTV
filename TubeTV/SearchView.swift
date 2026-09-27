import SwiftUI

struct SearchView: View {
    @State private var query = ""

    private var results: [VideoItem] {
        guard !query.isEmpty else { return VideoItem.demo }

        return VideoItem.demo.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.channel.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 28) {
                Text("Hledat")
                    .font(.largeTitle.bold())

                TextField("Hledat na YouTube", text: $query)
                    .textFieldStyle(.roundedBorder)

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
