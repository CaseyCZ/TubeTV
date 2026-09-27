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
    @State private var requestedSearchQuery: String?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 460)

            Group {
                switch selection {
                case .home:
                    HomeView { query in
                        requestedSearchQuery =
                            query
                        selection = .search
                    }
                case .subscriptions:
                    AccountFeedView(kind: .subscriptions)
                case .history:
                    AccountFeedView(kind: .history)
                case .playlists:
                    PlaylistsView()
                case .search:
                    SearchView(
                        requestedQuery:
                            requestedSearchQuery
                    )
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
                    if item == .search {
                        requestedSearchQuery = nil
                    }

                    selection = item
                } label: {
                    HStack(spacing: 18) {
                        Image(systemName: item.icon)
                            .frame(width: 40)

                        Text(
                            L10n.text(
                                item.titleKey,
                                languageCode: appLanguage
                            )
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .layoutPriority(1)

                        Spacer(minLength: 0)
                    }
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
