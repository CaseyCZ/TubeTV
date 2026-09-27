import SwiftUI

struct SettingsView: View {
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
                Section("Přehrávání") {
                    Picker("Preferovaná kvalita", selection: $preferredQuality) {
                        Text("Automaticky").tag("Auto")
                        Text("1080p").tag("1080p")
                        Text("1440p").tag("1440p")
                        Text("4K / 2160p").tag("2160p")
                    }
                }

                Section("Titulky") {
                    Toggle("Automaticky zapnout titulky", isOn: $autoEnableCaptions)
                    Toggle("Automaticky překládat", isOn: $autoTranslateCaptions)

                    Picker("Preferovaný jazyk", selection: $preferredCaptionLanguage) {
                        Text("Čeština").tag("cs")
                        Text("English").tag("en")
                        Text("Deutsch").tag("de")
                        Text("Polski").tag("pl")
                        Text("Slovenčina").tag("sk")
                    }

                    Text("Když video nemá českou stopu, TubeTV bude preferovat překlad dostupných nebo automaticky generovaných titulků do češtiny.")
                        .foregroundStyle(.secondary)
                }

                Section("YouTube účet") {
                    if isSignedIn {
                        Label(
                            "Přihlášeno k YouTube",
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundStyle(.green)

                        if !profiles.isEmpty {
                            Picker("YouTube profil", selection: $selectedProfileID) {
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
                                    accountMessage = "Aktivní YouTube profil: \(profile.name)"
                                }
                            }
                        }

                        Button("Obnovit profily") {
                            Task {
                                await loadProfiles()
                            }
                        }

                        Button("Odhlásit účet") {
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
                                    Text("Čekám na potvrzení…")
                                }
                            } else {
                                Label(
                                    "Přihlásit YouTube účet",
                                    systemImage: "person.crop.circle.badge.plus"
                                )
                            }
                        }
                        .disabled(isSigningIn)

                        if let authorization {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Na telefonu nebo počítači otevři:")
                                    .foregroundStyle(.secondary)

                                Text(authorization.verificationURL)
                                    .font(.title3.weight(.semibold))

                                Text("Zadej kód:")
                                    .foregroundStyle(.secondary)

                                Text(authorization.userCode)
                                    .font(.system(size: 42, weight: .bold, design: .monospaced))

                                Text("TubeTV čeká na dokončení přihlášení.")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 10)
                        }
                    }

                    if let accountMessage {
                        Text(accountMessage)
                            .foregroundStyle(.secondary)
                    }

                    Text("TubeTV používá stejný princip jako SmartTube: YouTube TV device login, refresh token v Keychainu a InnerTube TV profil včetně brand kanálů.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Nastavení")
            .task {
                await loadAccountState()
            }
        }
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

            let selectedPageID = await SmartTubeAuthService.shared.selectedPageID()

            if let current = loaded.first(
                where: { $0.pageID == selectedPageID && selectedPageID != nil }
            ) ?? loaded.first(where: { $0.isSelected }) ?? loaded.first {
                selectedProfileID = current.id
                await SmartTubeAuthService.shared.selectAccount(current)
            }

            if loaded.count > 1 {
                accountMessage = "Nalezeno \(loaded.count) YouTube profilů."
            }
        } catch {
            accountMessage = "Profily: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func beginSignIn() async {
        isSigningIn = true
        accountMessage = nil
        authorization = nil

        do {
            let auth = try await SmartTubeAuthService.shared.beginSignIn()
            authorization = auth

            try await SmartTubeAuthService.shared.finishSignIn(auth)

            isSignedIn = true
            authorization = nil
            accountMessage = "Přihlášení bylo dokončeno."
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
        accountMessage = "YouTube účet byl odhlášen."
    }
}
