import SwiftUI
import UIKit

struct SetupView: View {
    @EnvironmentObject private var model: AppModel
    @State private var testText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Włączenie klawiatury") {
                    Label("Ustawienia › Ogólne › Klawiatura › Klawiatury › Dodaj klawiaturę › Klawiatura MM",
                          systemImage: "1.circle")
                    Label("Dotknij „Klawiatura MM” na liście i włącz „Pełny dostęp” — bez niego klawiatura nie zapisze nauczonych słów i nie wstawi podyktowanego tekstu",
                          systemImage: "2.circle")
                    Label("W dowolnym polu tekstowym przytrzymaj globus i wybierz Klawiaturę MM",
                          systemImage: "3.circle")
                    Button("Otwórz Ustawienia") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }

                Section("Wypróbuj") {
                    TextField("Pisz tutaj…", text: $testText, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section {
                    Toggle("Autokorekta polskich znaków", isOn: $model.autocorrect)
                } footer: {
                    Text("Po spacji zamienia np. „zolw” na „żółw”. Backspace od razu po poprawce przywraca wpisany tekst.")
                }

                Section {
                    HStack {
                        Text(model.syncStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if model.isSyncing { ProgressView() }
                    }
                    Button("Synchronizuj teraz") { model.sync() }
                        .disabled(model.isSyncing)
                    if !model.hasSharedContainer {
                        Text("Brak wspólnego kontenera App Group — sprawdź podpisywanie aplikacji w Xcode.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Kopia słów w iCloud")
                } footer: {
                    Text("Nauczone i zablokowane słowa są zapisywane w Twojej prywatnej bazie iCloud. Na nowym telefonie wystarczy zalogować się tym samym Apple ID i otworzyć aplikację.")
                }

                Section("Skróty") {
                    Text("Przytrzymaj literę — polskie znaki i cyfry (e → ę, 3)")
                    Text("Przytrzymaj podpowiedź — usuń słowo z podpowiedzi")
                    Text("Dotknij słowa w cudzysłowie — dodaj je do słownika")
                    Text("Dwie spacje — kropka; dwa razy Shift — Caps Lock")
                }
                .font(.footnote)
            }
            .navigationTitle("Klawiatura MM")
        }
    }
}
