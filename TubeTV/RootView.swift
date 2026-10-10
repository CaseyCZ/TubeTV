import SwiftUI

extension Notification.Name {
    static let tubeTVPlayerVisibilityChanged =
        Notification.Name("TubeTVPlayerVisibilityChanged")
}

enum TubeTVTheme {
    static let page = Color(
        red: 7.0 / 255.0,
        green: 11.0 / 255.0,
        blue: 20.0 / 255.0
    )
    static let background = Color(
        red: 11.0 / 255.0,
        green: 16.0 / 255.0,
        blue: 32.0 / 255.0
    )
    static let panel = Color(
        red: 17.0 / 255.0,
        green: 24.0 / 255.0,
        blue: 39.0 / 255.0
    )
    static let panelRaised = Color(
        red: 23.0 / 255.0,
        green: 32.0 / 255.0,
        blue: 51.0 / 255.0
    )
    static let border = Color(
        red: 42.0 / 255.0,
        green: 56.0 / 255.0,
        blue: 80.0 / 255.0
    )
    static let accent = Color(
        red: 56.0 / 255.0,
        green: 189.0 / 255.0,
        blue: 248.0 / 255.0
    )
    static let action = Color(
        red: 3.0 / 255.0,
        green: 118.0 / 255.0,
        blue: 181.0 / 255.0
    )
    static let hero = Color(
        red: 23.0 / 255.0,
        green: 37.0 / 255.0,
        blue: 84.0 / 255.0
    )

    static let cardCornerRadius: CGFloat = 22
}

struct TubeTVBackground: View {
    var body: some View {
        ZStack {
            TubeTVTheme.page

            LinearGradient(
                colors: [
                    TubeTVTheme.hero.opacity(0.82),
                    TubeTVTheme.background.opacity(0.96),
                    TubeTVTheme.page
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    TubeTVTheme.accent.opacity(0.13),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 20,
                endRadius: 980
            )
        }
        .ignoresSafeArea()
    }
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
        ZStack {
            TubeTVBackground()

            HStack(spacing: 0) {
                if !playerIsVisible {
                    sidebar
                        .frame(
                            width:
                                sidebarCollapsed
                                ? 108
                                : 430
                        )
                        .transition(
                            .move(edge: .leading)
                                .combined(with: .opacity)
                        )
                }

                Group {
                    switch selection {
                    case .home:
                        HomeView { query in
                            requestedSearchQuery = query
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
                            requestedQuery: requestedSearchQuery
                        )
                    case .settings:
                        SettingsView()
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
            }
        }
        .tint(TubeTVTheme.accent)
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
            sidebarCollapsed = newValue == nil
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
        .preferredColorScheme(.dark)
        .id(appLanguage)
    }

    private var sidebar: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            sidebarBrand

            ForEach(AppSection.allCases) { item in
                Button {
                    if item == .search {
                        requestedSearchQuery = nil
                    }

                    selection = item
                } label: {
                    TubeTVSidebarItem(
                        item: item,
                        title: L10n.text(
                            item.titleKey,
                            languageCode: appLanguage
                        ),
                        isSelected: selection == item,
                        isCollapsed: sidebarCollapsed
                    )
                }
                .buttonStyle(.plain)
                .focused(
                    $focusedSidebarItem,
                    equals: item
                )
            }

            Spacer()

            if !sidebarCollapsed {
                HStack(spacing: 9) {
                    Circle()
                        .fill(TubeTVTheme.accent)
                        .frame(width: 8, height: 8)

                    Text("tvOS · SmartTube inspired")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 4)
                .transition(.opacity)
            }
        }
        .padding(
            .horizontal,
            sidebarCollapsed ? 10 : 24
        )
        .padding(.vertical, 28)
        .background {
            ZStack {
                TubeTVTheme.panel.opacity(0.91)

                LinearGradient(
                    colors: [
                        TubeTVTheme.hero.opacity(0.34),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .center
                )
            }
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(TubeTVTheme.border.opacity(0.72))
                    .frame(width: 1)
            }
        }
    }

    @ViewBuilder
    private var sidebarBrand: some View {
        if sidebarCollapsed {
            ZStack {
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
                .fill(
                    LinearGradient(
                        colors: [
                            TubeTVTheme.action,
                            TubeTVTheme.accent
                        ],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    )
                )

                Image(systemName: "play.fill")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
            }
            .frame(width: 64, height: 64)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 22)
            .transition(.opacity)
        } else {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(
                        cornerRadius: 18,
                        style: .continuous
                    )
                    .fill(
                        LinearGradient(
                            colors: [
                                TubeTVTheme.action,
                                TubeTVTheme.accent
                            ],
                            startPoint: .bottomLeading,
                            endPoint: .topTrailing
                        )
                    )
                    .shadow(
                        color: TubeTVTheme.accent.opacity(0.22),
                        radius: 20,
                        y: 8
                    )

                    Image(systemName: "play.fill")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }
                .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 3) {
                    Text("TubeTV")
                        .font(.title.bold())
                        .tracking(-1.2)

                    Text("YouTube · Apple TV")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TubeTVTheme.accent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 22)
            .transition(.opacity)
        }
    }
}

private struct TubeTVSidebarItem: View {
    @Environment(\.isFocused) private var isFocused

    let item: AppSection
    let title: String
    let isSelected: Bool
    let isCollapsed: Bool

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
                .fill(iconBackground)

                Image(systemName: item.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(iconForeground)
            }
            .frame(width: 48, height: 48)

            if !isCollapsed {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .layoutPriority(1)

                Spacer(minLength: 0)

                if isSelected {
                    Circle()
                        .fill(TubeTVTheme.accent)
                        .frame(width: 8, height: 8)
                }
            }
        }
        .frame(
            maxWidth: .infinity,
            alignment: isCollapsed ? .center : .leading
        )
        .padding(.horizontal, isCollapsed ? 8 : 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(
                cornerRadius: 17,
                style: .continuous
            )
            .fill(rowBackground)
            .overlay {
                RoundedRectangle(
                    cornerRadius: 17,
                    style: .continuous
                )
                .strokeBorder(
                    rowBorder,
                    lineWidth: isFocused ? 2 : 1
                )
            }
        }
        .scaleEffect(isFocused ? 1.035 : 1.0)
        .shadow(
            color:
                isFocused
                ? TubeTVTheme.accent.opacity(0.18)
                : .clear,
            radius: 16,
            y: 8
        )
        .animation(
            .easeOut(duration: 0.13),
            value: isFocused
        )
    }

    private var rowBackground: Color {
        if isFocused {
            return TubeTVTheme.panelRaised.opacity(0.98)
        }

        if isSelected {
            return TubeTVTheme.accent.opacity(0.10)
        }

        return Color.clear
    }

    private var rowBorder: Color {
        if isFocused {
            return TubeTVTheme.accent.opacity(0.88)
        }

        if isSelected {
            return TubeTVTheme.accent.opacity(0.30)
        }

        return Color.clear
    }

    private var iconBackground: Color {
        if isFocused || isSelected {
            return TubeTVTheme.accent.opacity(0.17)
        }

        return TubeTVTheme.panelRaised.opacity(0.75)
    }

    private var iconForeground: Color {
        if isFocused || isSelected {
            return TubeTVTheme.accent
        }

        return .white.opacity(0.76)
    }
}
