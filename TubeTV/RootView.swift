import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case home
    case subscriptions
    case history
    case playlists
    case search
    case settings

    var id: String { rawValue }

    var titleKey: String {
        rawValue
    }

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
    @AppStorage("appLanguage") private var appLanguage =
        AppLanguage.english.rawValue
    @State private var selection: AppSection = .home

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 390)

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
        .id(appLanguage)
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
                    Label(
                        L10n.text(item.titleKey, languageCode: appLanguage),
                        systemImage: item.icon
                    )
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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
