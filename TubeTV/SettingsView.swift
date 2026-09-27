import SwiftUI

struct SettingsView: View {
    @AppStorage("preferredQuality") private var preferredQuality = "Auto"
    @AppStorage("preferredCaptionLanguage") private var preferredCaptionLanguage = "cs"
    @AppStorage("autoEnableCaptions") private var autoEnableCaptions = true
    @AppStorage("autoTranslateCaptions") private var autoTranslateCaptions = true

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

                Section("Účet") {
                    Button("Přihlásit YouTube účet") {
                        // OAuth device flow přijde v další etapě.
                    }
                }
            }
            .navigationTitle("Nastavení")
        }
    }
}
