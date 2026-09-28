import SwiftUI

extension Notification.Name {
    static let tubeTVPlayerVisibilityChanged =
        Notification.Name("TubeTVPlayerVisibilityChanged")
}

enum AppSection: String, CaseIterable, Identifiable {
    case home
    case subscriptions
    case channels
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
        case .channels:
            return "rectangle.stack.person.crop.fill"
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
    @State private var sidebarCollapsed = false
    @State private var playerIsVisible = false
    @FocusState private var focusedSidebarItem: AppSection?

    var body: some View {
        HStack(spacing: 0) {
            if !playerIsVisible {
                sidebar
                    .frame(
                        width:
                            sidebarCollapsed
                            ? 96
                            : 460
                    )
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

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
                case .channels:
                    SubscribedChannelsView()
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
        .animation(
            .easeInOut(duration: 0.22),
            value: sidebarCollapsed
        )
        .animation(
            .easeInOut(duration: 0.18),
            value: playerIsVisible
        )
        .onChange(
            of: focusedSidebarItem
        ) { _, newValue in
            sidebarCollapsed =
                newValue == nil
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .tubeTVPlayerVisibilityChanged
            )
        ) { notification in
            playerIsVisible =
                notification.object as? Bool
                ?? false

            if playerIsVisible {
                focusedSidebarItem = nil
                sidebarCollapsed = true
            }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .id(appLanguage)
    }

    private var sidebar: some View {
        VStack(
            alignment: .leading,
            spacing: 14
        ) {
            if !sidebarCollapsed {
                Text("TubeTV")
                    .font(.largeTitle.bold())
                    .padding(.bottom, 24)
                    .transition(.opacity)
            } else {
                Spacer()
                    .frame(height: 58)
            }

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

                        if !sidebarCollapsed {
                            Text(
                                L10n.text(
                                    item.titleKey,
                                    languageCode:
                                        appLanguage
                                )
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .layoutPriority(1)

                            Spacer(minLength: 0)
                        }
                    }
                    .font(
                        .title3
                            .weight(.semibold)
                    )
                    .frame(
                        maxWidth: .infinity,
                        alignment:
                            sidebarCollapsed
                            ? .center
                            : .leading
                    )
                    .padding(
                        .horizontal,
                        sidebarCollapsed
                        ? 0
                        : 10
                    )
                }
                .focused(
                    $focusedSidebarItem,
                    equals: item
                )
            }

            Spacer()
        }
        .padding(
            .horizontal,
            sidebarCollapsed
            ? 8
            : 30
        )
        .padding(.vertical, 30)
        .background(.ultraThinMaterial)
    }
}
