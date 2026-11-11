import SwiftUI

struct LearnedWordsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var newWord = ""

    private var filtered: [(word: String, count: Int)] {
        guard !query.isEmpty else { return model.learned }
        return model.learned.filter { $0.word.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Dodaj słowo") {
                    AddWordRow(placeholder: "Nowe słowo", text: $newWord) {
                        model.addWord(newWord)
                        newWord = ""
                    }
                }
                Section {
                    ForEach(filtered, id: \.word) { item in
                        HStack {
                            Text(item.word)
                            Spacer()
                            Text("\(item.count)×")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button("Usuń", role: .destructive) { model.forget(item.word) }
                            Button("Zablokuj") {
                                model.forget(item.word)
                                model.block(item.word)
                            }
                            .tint(.orange)
                        }
                    }
                } header: {
                    Text("Nauczone słowa (\(model.learned.count))")
                } footer: {
                    Text("Liczba oznacza, ile razy słowo zostało użyte. Słowo spoza słownika bazowego jest podpowiadane od 2 użyć.")
                }
            }
            .searchable(text: $query, prompt: "Szukaj słowa")
            .navigationTitle("Słowa")
        }
    }
}

struct BlockedWordsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var newWord = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Zablokuj słowo") {
                    AddWordRow(placeholder: "Słowo, którego nie podpowiadać", text: $newWord) {
                        model.block(newWord)
                        newWord = ""
                    }
                }
                Section {
                    ForEach(model.blocked, id: \.self) { word in
                        Text(word)
                            .swipeActions {
                                Button("Odblokuj") { model.unblock(word) }
                                    .tint(.green)
                            }
                    }
                } header: {
                    Text("Niepodpowiadane (\(model.blocked.count))")
                } footer: {
                    Text("Przesuń słowo w lewo, aby znów było podpowiadane.")
                }
            }
            .navigationTitle("Zablokowane")
        }
    }
}

private struct AddWordRow: View {
    let placeholder: String
    @Binding var text: String
    let onAdd: () -> Void

    var body: some View {
        HStack {
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit(onAdd)
            Button(action: onAdd) {
                Image(systemName: "plus.circle.fill")
            }
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}
