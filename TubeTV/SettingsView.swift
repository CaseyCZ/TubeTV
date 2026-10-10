import AVFoundation
import SwiftUI

struct SettingsView: View {
    @AppStorage("appLanguage") private var appLanguage =
        AppLanguage.english.rawValue
    @AppStorage("preferredQuality") private var preferredQuality = "Auto"
    @AppStorage("preferredCaptionLanguage") private var preferredCaptionLanguage = "cs"
    @AppStorage("autoEnableCaptions") private var autoEnableCaptions = true
    @AppStorage("autoTranslateCaptions") private var autoTranslateCaptions = true

    @State private var isSignedIn = false
    @State private var authorization: TVDeviceAuthorization?
    @State private var isSigningIn = false
    @State private var accountMessage: String?
    @State private var profiles: [YouTubeAccountProfile] = []
    @State private var selectedProfileID = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("TUBETV · SETTINGS")
                        .font(.caption.weight(.heavy))
                        .tracking(1.2)
                        .foregroundStyle(TubeTVTheme.accent)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .background(
                            TubeTVTheme.accent.opacity(0.10),
                            in: Capsule()
                        )
                        .overlay {
                            Capsule()
                                .strokeBorder(
                                    TubeTVTheme.accent.opacity(0.34),
                                    lineWidth: 1
                                )
                        }

                    Text(
                        L10n.text(
                            "settings",
                            languageCode: appLanguage
                        )
                    )
                    .font(.system(size: 54, weight: .bold))
                    .tracking(-1.8)
                }
                .padding(.horizontal, 52)
                .padding(.top, 42)

                Form {
                    Section(
                        L10n.text(
                            "language_section",
                            languageCode: appLanguage
                        )
                    ) {
                        Picker(
                            L10n.text(
                                "app_language",
                                languageCode: appLanguage
                            ),
                            selection: $appLanguage
                        ) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(language.displayName)
                                    .tag(language.rawValue)
                            }
                        }

                        Text(
                            L10n.text(
                                "language_restart_note",
                                languageCode: appLanguage
                            )
                        )
                        .foregroundStyle(.secondary)
                    }

                    Section(
                        L10n.text(
                            "playback_section",
                            languageCode: appLanguage
                        )
                    ) {
                        Picker(
                            L10n.text(
                                "preferred_quality",
                                languageCode: appLanguage
                            ),
                            selection: $preferredQuality
                        ) {
                            Text(
                                L10n.text(
                                    "automatic",
                                    languageCode: appLanguage
                                )
                            )
                            .tag("Auto")
                            Text("1080p").tag("1080p")
                            Text("1440p").tag("1440p")
                            Text("4K / 2160p").tag("2160p")
                        }

                        Label(
                            L10n.text(
                                AVPlayer.eligibleForHDRPlayback
                                    ? "hdr_available"
                                    : "hdr_unavailable",
                                languageCode: appLanguage
                            ),
                            systemImage:
                                AVPlayer.eligibleForHDRPlayback
                                    ? "sparkles.tv"
                                    : "tv.slash"
                        )
                        .foregroundStyle(.secondary)

                        Label(
                            L10n.text(
                                "ads_active",
                                languageCode: appLanguage
                            ),
                            systemImage: "hand.raised.fill"
                        )
                        .foregroundStyle(TubeTVTheme.accent)

                        Text(
                            L10n.text(
                                "ads_description",
                                languageCode: appLanguage
                            )
                        )
                        .foregroundStyle(.secondary)
                    }

                    Section(
                        L10n.text(
                            "subtitles_section",
                            languageCode: appLanguage
                        )
                    ) {
                        Toggle(
                            L10n.text(
                                "auto_enable_subtitles",
                                languageCode: appLanguage
                            ),
                            isOn: $autoEnableCaptions
                        )
                        Toggle(
                            L10n.text(
                                "auto_translate_subtitles",
                                languageCode: appLanguage
                            ),
                            isOn: $autoTranslateCaptions
                        )

                        Picker(
                            L10n.text(
                                "preferred_subtitle_language",
                                languageCode: appLanguage
                            ),
                            selection: $preferredCaptionLanguage
                        ) {
                            Text("Čeština").tag("cs")
                            Text("English").tag("en")
                            Text("Deutsch").tag("de")
                            Text("Polski").tag("pl")
                            Text("Slovenčina").tag("sk")
                        }

                        Text(
                            L10n.text(
                                "subtitle_fallback_description",
                                languageCode: appLanguage
                            )
                        )
                        .foregroundStyle(.secondary)
                    }

                    Section(
                        L10n.text(
                            "youtube_account",
                            languageCode: appLanguage
                        )
                    ) {
                        if isSignedIn {
                            Label(
                                L10n.text(
                                    "signed_in",
                                    languageCode: appLanguage
                                ),
                                systemImage: "checkmark.circle.fill"
                            )
                            .foregroundStyle(.green)

                            if !profiles.isEmpty {
                                Picker(
                                    L10n.text(
                                        "youtube_profile",
                                        languageCode: appLanguage
                                    ),
                                    selection: $selectedProfileID
                                ) {
                                    ForEach(profiles) { profile in
                                        VStack(alignment: .leading) {
                                            Text(profile.name)

                                            if let handle = profile.channelHandle,
                                               !handle.isEmpty {
                                                Text(handle)
                                            }
                                        }
                                        .tag(profile.id)
                                    }
                                }
                                .onChange(of: selectedProfileID) { _, newValue in
                                    guard let profile = profiles.first(
                                        where: { $0.id == newValue }
                                    ) else {
                                        return
                                    }

                                    Task {
                                        await SmartTubeAuthService.shared.selectAccount(profile)
                                        accountMessage =
                                            "\(L10n.text("profile_active", languageCode: appLanguage)): \(profile.name)"
                                    }
                                }
                            }

                            Button(
                                L10n.text(
                                    "refresh_profiles",
                                    languageCode: appLanguage
                                )
                            ) {
                                Task {
                                    await loadProfiles()
                                }
                            }

                            Button(
                                L10n.text(
                                    "sign_out",
                                    languageCode: appLanguage
                                )
                            ) {
                                Task {
                                    await signOut()
                                }
                            }
                        } else {
                            Button {
                                Task {
                                    await beginSignIn()
                                }
                            } label: {
                                if isSigningIn {
                                    HStack(spacing: 12) {
                                        ProgressView()
                                            .tint(TubeTVTheme.accent)

                                        Text(
                                            L10n.text(
                                                "waiting_confirmation",
                                                languageCode: appLanguage
                                            )
                                        )
                                    }
                                } else {
                                    Label(
                                        L10n.text(
                                            "sign_in",
                                            languageCode: appLanguage
                                        ),
                                        systemImage:
                                            "person.crop.circle.badge.plus"
                                    )
                                }
                            }
                            .disabled(isSigningIn)
                        }

                        if let accountMessage {
                            Text(accountMessage)
                                .foregroundStyle(.secondary)
                        }

                        Text(
                            L10n.text(
                                "smarttube_login_description",
                                languageCode: appLanguage
                            )
                        )
                        .foregroundStyle(.secondary)
                    }
                }
                .tint(TubeTVTheme.accent)
            }
            .task {
                await loadAccountState()
            }
        }
        .overlay {
            if let authorization {
                YouTubeDeviceAuthorizationOverlay(
                    authorization: authorization,
                    appLanguage: appLanguage
                )
            }
        }
        .id(appLanguage)
    }

    @MainActor
    private func loadAccountState() async {
        isSignedIn = await SmartTubeAuthService.shared.signedIn()

        if isSignedIn {
            await loadProfiles()
        } else {
            profiles = []
            selectedProfileID = ""
        }
    }

    @MainActor
    private func loadProfiles() async {
        guard await SmartTubeAuthService.shared.signedIn() else {
            profiles = []
            selectedProfileID = ""
            return
        }

        do {
            let loaded = try await SmartTubeAuthService.shared.accounts()
            profiles = loaded

            let selectedPageID =
                await SmartTubeAuthService.shared.selectedPageID()

            if let current = loaded.first(
                where: {
                    $0.pageID == selectedPageID
                    && selectedPageID != nil
                }
            ) ?? loaded.first(
                where: { $0.isSelected }
            ) ?? loaded.first {
                selectedProfileID = current.id
                await SmartTubeAuthService.shared.selectAccount(current)
            }

            if loaded.count > 1 {
                accountMessage =
                    "\(loaded.count) \(L10n.text("profiles_found", languageCode: appLanguage))"
            }
        } catch {
            accountMessage =
                "\(L10n.text("profile_error", languageCode: appLanguage)): \(error.localizedDescription)"
        }
    }

    @MainActor
    private func beginSignIn() async {
        isSigningIn = true
        accountMessage = nil
        authorization = nil

        do {
            let auth =
                try await SmartTubeAuthService.shared.beginSignIn()
            authorization = auth

            try await SmartTubeAuthService.shared.finishSignIn(auth)

            isSignedIn = true
            authorization = nil
            accountMessage =
                L10n.text(
                    "sign_in_complete",
                    languageCode: appLanguage
                )
            await loadProfiles()
        } catch {
            accountMessage = error.localizedDescription
        }

        isSigningIn = false
    }

    @MainActor
    private func signOut() async {
        await SmartTubeAuthService.shared.signOut()
        isSignedIn = false
        authorization = nil
        profiles = []
        selectedProfileID = ""
        accountMessage =
            L10n.text("signed_out", languageCode: appLanguage)
    }
}

private struct YouTubeDeviceAuthorizationOverlay: View {
    let authorization: TVDeviceAuthorization
    let appLanguage: String

    var body: some View {
        ZStack {
            TubeTVTheme.page
                .opacity(0.92)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .fill(TubeTVTheme.accent.opacity(0.12))

                    Image(
                        systemName:
                            "person.crop.circle.badge.checkmark"
                    )
                    .font(.system(size: 68, weight: .semibold))
                    .foregroundStyle(TubeTVTheme.accent)
                }
                .frame(width: 116, height: 116)

                Text(
                    L10n.text(
                        "youtube_account",
                        languageCode: appLanguage
                    )
                )
                .font(.largeTitle.bold())

                Text(
                    L10n.text(
                        "open_on_phone",
                        languageCode: appLanguage
                    )
                )
                .font(.title3)
                .foregroundStyle(.secondary)

                Text(authorization.verificationURL)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(TubeTVTheme.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(
                    L10n.text(
                        "enter_code",
                        languageCode: appLanguage
                    )
                )
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.top, 8)

                Text(authorization.userCode)
                    .font(
                        .system(
                            size: 60,
                            weight: .bold,
                            design: .monospaced
                        )
                    )
                    .foregroundStyle(.white)
                    .tracking(5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 16)
                    .background(
                        TubeTVTheme.panelRaised,
                        in: RoundedRectangle(
                            cornerRadius: 18,
                            style: .continuous
                        )
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: 18,
                            style: .continuous
                        )
                        .strokeBorder(
                            TubeTVTheme.accent.opacity(0.44),
                            lineWidth: 2
                        )
                    }

                HStack(spacing: 14) {
                    ProgressView()
                        .tint(TubeTVTheme.accent)

                    Text(
                        L10n.text(
                            "waiting_sign_in",
                            languageCode: appLanguage
                        )
                    )
                    .font(.headline)
                    .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 70)
            .padding(.vertical, 48)
            .frame(maxWidth: 920)
            .background(
                TubeTVTheme.panel.opacity(0.96),
                in: RoundedRectangle(
                    cornerRadius: 32,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 32,
                    style: .continuous
                )
                .strokeBorder(
                    TubeTVTheme.border.opacity(0.85),
                    lineWidth: 1
                )
            }
            .shadow(
                color: TubeTVTheme.accent.opacity(0.16),
                radius: 36,
                y: 16
            )
            .padding(60)
        }
    }
}
