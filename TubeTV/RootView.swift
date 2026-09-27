import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case home = "Domů"
    case subscriptions = "Odběry"
    case history = "Historie"
    case playlists = "Playlisty"
    case search = "Hledat"
    case settings = "Nastavení"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .subscriptions: return "person.2.fill"
        case .history: return "clock.arrow.circlepath"
        case .playlists: return "rectangle.stack.fill"
        case .search: return "magnifyingglass"
        case .settings: return "gearshape.fill"
        }
    }
}

struct RootView: View {
    @State private var selection: AppSection = .home

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 300)

            Group {
                switch selection {
                case .home:
                    HomeView()
                case .subscriptions:
                    AccountFeedView(kind: .subscriptions)
                case .history:
                    AccountFeedView(kind: .history)
                case .playlists:
                    PlaylistsView()
                case .search:
                    SearchView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("TubeTV")
                .font(.largeTitle.bold())
                .padding(.bottom, 24)

            ForEach(AppSection.allCases) { item in
                Button {
                    selection = item
                } label: {
                    Label(item.rawValue, systemImage: item.icon)
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                }
            }

            Spacer()
        }
        .padding(30)
        .background(.ultraThinMaterial)
    }
}

struct PlaceholderView: View {
    let title: String
    let icon: String

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 72))
            Text(title)
                .font(.largeTitle.bold())
            Text("Tahle část přijde v další etapě.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
