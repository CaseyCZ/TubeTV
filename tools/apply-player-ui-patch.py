from pathlib import Path

path = Path("TubeTV/PlayerView.swift")
text = path.read_text(encoding="utf-8")

start_marker = "    private var transportOverlay: some View {\n"
end_marker = "    private func revealTransportControls()"

if text.count(start_marker) != 1 or text.count(end_marker) != 1:
    raise SystemExit("Player transport markers changed; refusing blind patch")

start = text.index(start_marker)
end = text.index(end_marker, start)

new_transport = r'''    private var transportOverlay: some View {
        VStack {
            Spacer()

            LinearGradient(
                colors: [
                    .clear,
                    TubeTVTheme.background.opacity(0.72),
                    TubeTVTheme.page.opacity(0.98)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 390)
            .overlay(alignment: .bottom) {
                VStack(
                    alignment: .leading,
                    spacing: 16
                ) {
                    if !model.currentVideoTitle
                        .isEmpty {
                        Text(
                            model.currentVideoTitle
                        )
                        .font(.title2.bold())
                        .lineLimit(1)
                    }

                    if !model.currentChannelTitle
                        .isEmpty {
                        Text(
                            model.currentChannelTitle
                        )
                        .font(.headline)
                        .foregroundStyle(
                            .white.opacity(0.68)
                        )
                        .lineLimit(1)
                    }

                    TimelineView(
                        .periodic(
                            from: .now,
                            by: 0.5
                        )
                    ) { _ in
                        let current =
                            max(
                                0,
                                model.player
                                    .currentTime()
                                    .seconds
                            )
                        let duration =
                            model.player
                                .currentItem?
                                .duration
                                .seconds
                            ?? 0
                        let safeCurrent =
                            current.isFinite
                            ? current
                            : 0
                        let safeDuration =
                            duration.isFinite
                                && duration > 0
                            ? duration
                            : 1

                        VStack(
                            spacing: 12
                        ) {
                            ProgressView(
                                value:
                                    min(
                                        safeCurrent,
                                        safeDuration
                                    ),
                                total:
                                    safeDuration
                            )
                            .progressViewStyle(
                                .linear
                            )
                            .tint(TubeTVTheme.accent)

                            HStack(spacing: 20) {
                                Text(
                                    formatTransportTime(
                                        safeCurrent
                                    )
                                )

                                Spacer()

                                Image(
                                    systemName:
                                        model.player
                                            .timeControlStatus
                                        == .playing
                                        ? "pause.fill"
                                        : "play.fill"
                                )
                                .font(.title2.bold())
                                .foregroundStyle(.white)
                                .frame(
                                    width: 58,
                                    height: 42
                                )
                                .background(
                                    TubeTVTheme.panelRaised.opacity(0.92),
                                    in: Capsule()
                                )
                                .overlay {
                                    Capsule()
                                        .strokeBorder(
                                            TubeTVTheme.accent.opacity(0.28),
                                            lineWidth: 1
                                        )
                                }

                                Spacer()

                                Text(
                                    duration.isFinite
                                        && duration > 0
                                    ? formatTransportTime(
                                        duration
                                    )
                                    : "--:--"
                                )
                            }
                            .font(
                                .headline
                                    .monospacedDigit()
                            )
                            .foregroundStyle(.white)
                        }
                    }

                    HStack(spacing: 10) {
                        Image(
                            systemName:
                                "arrow.left.and.right"
                        )
                        Text("10 s")

                        Circle()
                            .fill(
                                TubeTVTheme.border
                            )
                            .frame(
                                width: 4,
                                height: 4
                            )

                        Image(
                            systemName:
                                "chevron.up"
                        )
                        Text(
                            L10n.text(
                                "settings",
                                languageCode:
                                    appLanguage
                            )
                        )
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        .white.opacity(0.78)
                    )
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        TubeTVTheme.panelRaised.opacity(0.82),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                TubeTVTheme.border.opacity(0.72),
                                lineWidth: 1
                            )
                    }
                }
                .padding(24)
                .background(
                    TubeTVTheme.panel.opacity(0.84),
                    in: RoundedRectangle(
                        cornerRadius: 24,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 24,
                        style: .continuous
                    )
                    .strokeBorder(
                        TubeTVTheme.border.opacity(0.78),
                        lineWidth: 1
                    )
                }
                .shadow(
                    color: .black.opacity(0.28),
                    radius: 24,
                    y: 12
                )
                .padding(.horizontal, 60)
                .padding(.bottom, 42)
            }
        }
        .allowsHitTesting(false)
    }

'''

text = text[:start] + new_transport + text[end:]

old_settings = '''            .padding(30)
            .frame(width: 620)
            .frame(maxHeight: .infinity)
            .focusSection()
            .background(.ultraThinMaterial)
'''

new_settings = '''            .padding(30)
            .frame(width: 620)
            .frame(maxHeight: .infinity)
            .focusSection()
            .background {
                ZStack {
                    TubeTVTheme.panel.opacity(0.98)

                    LinearGradient(
                        colors: [
                            TubeTVTheme.hero.opacity(0.48),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                }
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(
                            TubeTVTheme.accent.opacity(0.30)
                        )
                        .frame(width: 1)
                }
            }
            .shadow(
                color: .black.opacity(0.36),
                radius: 28,
                x: -10
            )
'''

if old_settings not in text:
    raise SystemExit("Player settings marker changed; refusing blind patch")

text = text.replace(old_settings, new_settings, 1)
path.write_text(text, encoding="utf-8")
print("Patched TubeTV/PlayerView.swift")
