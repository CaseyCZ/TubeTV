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
            Form {
                Section(L10n.text("language_section", languageCode: appLanguage)) {
                    Picker(
                        L10n.text("app_language", languageCode: appLanguage),
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

                Section(L10n.text("playback_section", languageCode: appLanguage)) {
                    Picker(
                        L10n.text("preferred_quality", languageCode: appLanguage),
                        selection: $preferredQuality
                    ) {
                        Text(L10n.text("automatic", languageCode: appLanguage))
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
                        L10n.text("ads_active", languageCode: appLanguage),
                        systemImage: "hand.raised.fill"
                    )
                    .foregroundStyle(.secondary)

                    Text(
                        L10n.text(
                            "ads_description",
                            languageCode: appLanguage
                        )
                    )
                    .foregroundStyle(.secondary)
                }

                Section(L10n.text("subtitles_section", languageCode: appLanguage)) {
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

                Section(L10n.text("youtube_account", languageCode: appLanguage)) {
                    if isSignedIn {
                        Label(
                            L10n.text("signed_in", languageCode: appLanguage),
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
                            .onChange(of: selectedProfileID) { newValue in
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
                            L10n.text("sign_out", languageCode: appLanguage)
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

                        if let authorization {
                            VStack(alignment: .leading, spacing: 14) {
                                Text(
                                    L10n.text(
                                        "open_on_phone",
                                        languageCode: appLanguage
                                    )
                                )
                                .foregroundStyle(.secondary)

                                Text(authorization.verificationURL)
                                    .font(.title3.weight(.semibold))

                                Text(
                                    L10n.text(
                                        "enter_code",
                                        languageCode: appLanguage
                                    )
                                )
                                .foregroundStyle(.secondary)

                                Text(authorization.userCode)
                                    .font(
                                        .system(
                                            size: 42,
                                            weight: .bold,
                                            design: .monospaced
                                        )
                                    )

                                Text(
                                    L10n.text(
                                        "waiting_sign_in",
                                        languageCode: appLanguage
                                    )
                                )
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 10)
                        }
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
            .navigationTitle(
                L10n.text("settings", languageCode: appLanguage)
            )
            .task {
                await loadAccountState()
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
