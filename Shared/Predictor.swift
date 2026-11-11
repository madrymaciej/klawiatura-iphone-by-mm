import Foundation

struct Suggestion: Equatable {
    enum Kind { case verbatim, prediction }
    let text: String
    let kind: Kind
    /// Czy słowo jest znane (słownik bazowy lub nauczone). Nieznane słowo dosłowne
    /// jest pokazywane w cudzysłowie, a jego wybranie dodaje je do słownika.
    let isKnown: Bool
}

/// Silnik podpowiedzi: słownik bazowy (ok. 50 tys. polskich słów z częstością)
/// + słownik użytkownika. Dopasowanie ignoruje polskie znaki („zolw” → „żółw”).
final class Predictor {
    static let shared = Predictor()

    private struct Entry {
        let word: String
        let folded: String
        let score: Double
    }

    /// Posortowane rosnąco po `folded` (plik jest posortowany przy generowaniu).
    private var entries: [Entry] = []
    private(set) var isLoaded = false
    private var isLoading = false

    private static let alphabet: [Character] = Array("abcdefghijklmnopqrstuvwxyz")

    // MARK: - Ładowanie

    func loadIfNeeded(completion: @escaping () -> Void) {
        if isLoaded { completion(); return }
        if isLoading { return }
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = Self.readBaseDictionary()
            DispatchQueue.main.async {
                self.entries = loaded
                self.isLoaded = true
                self.isLoading = false
                completion()
            }
        }
    }

    private static func readBaseDictionary() -> [Entry] {
        guard let url = Bundle.main.url(forResource: "pl_words", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var result: [Entry] = []
        result.reserveCapacity(50_000)
        for line in text.split(separator: "\n") {
            guard let space = line.firstIndex(of: " ") else { continue }
            let word = String(line[..<space])
            let freq = Double(line[line.index(after: space)...]) ?? 1
            result.append(Entry(word: word, folded: fold(word), score: log10(max(freq, 1))))
        }
        return result
    }

    // MARK: - Normalizacja

    /// Małe litery bez polskich znaków diakrytycznych.
    static func fold(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.utf8.count)
        for ch in s.lowercased() {
            switch ch {
            case "ą": out.append("a")
            case "ć": out.append("c")
            case "ę": out.append("e")
            case "ł": out.append("l")
            case "ń": out.append("n")
            case "ó": out.append("o")
            case "ś": out.append("s")
            case "ź", "ż": out.append("z")
            default: out.append(ch)
            }
        }
        return out
    }

    private static func applyCase(of typed: String, to word: String) -> String {
        guard let first = typed.first, first.isUppercase else { return word }
        if typed.count > 1, typed == typed.uppercased() { return word.uppercased() }
        return word.prefix(1).uppercased() + word.dropFirst()
    }

    // MARK: - Wyszukiwanie binarne

    /// Indeks pierwszego wpisu, którego `folded` >= `key`.
    private func lowerBound(_ key: String) -> Int {
        var lo = 0
        var hi = entries.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if entries[mid].folded < key { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    private func exactMatches(folded key: String) -> [Entry] {
        var result: [Entry] = []
        var i = lowerBound(key)
        while i < entries.count, entries[i].folded == key {
            result.append(entries[i])
            i += 1
        }
        return result
    }

    private func userBoost(_ count: Int) -> Double {
        1.5 * log2(1 + Double(count))
    }

    func isKnown(_ typed: String, user: UserDictionary) -> Bool {
        let lower = typed.lowercased()
        for candidate in [typed, lower] {
            if let e = user.learned[candidate], !e.deleted, e.count >= UserDictionary.suggestThreshold {
                return true
            }
        }
        return exactMatches(folded: Self.fold(lower)).contains { $0.word == lower }
    }

    // MARK: - Podpowiedzi

    /// Zwraca listę: [słowo dosłowne, najlepsze podpowiedzi…]. Przy pustym `typed`
    /// zwraca podpowiedzi następnego słowa na podstawie poprzedniego.
    func suggestions(typed: String, previous: String?, user: UserDictionary,
                     capitalizeNext: Bool = false, limit: Int = 3) -> [Suggestion] {
        if typed.isEmpty {
            return nextWordSuggestions(previous: previous, user: user,
                                       capitalize: capitalizeNext, limit: limit)
        }

        let lower = typed.lowercased()
        let folded = Self.fold(lower)
        // klucz = małe litery, wartość = (zapis do pokazania, ocena)
        var pool: [String: (display: String, score: Double)] = [:]

        func offer(_ display: String, _ score: Double) {
            let key = display.lowercased()
            if let existing = pool[key], existing.score >= score { return }
            pool[key] = (display, score)
        }

        // 1. Słownik bazowy — wszystkie słowa zaczynające się od wpisanego prefiksu.
        var i = lowerBound(folded)
        while i < entries.count, entries[i].folded.hasPrefix(folded) {
            let e = entries[i]
            var score = e.score
            if e.folded.count == folded.count { score += 3 }      // pełne słowo, różni się najwyżej ogonkami
            if e.word.hasPrefix(lower) { score += 0.5 }            // zgodne także polskie znaki
            if let u = user.learned[e.word], !u.deleted { score += userBoost(u.count) }
            offer(e.word, score)
            i += 1
        }

        // 2. Słowa nauczone przez użytkownika.
        for (word, entry) in user.learned
        where !entry.deleted && entry.count >= UserDictionary.suggestThreshold {
            let wordFolded = Self.fold(word)
            guard wordFolded.hasPrefix(folded) else { continue }
            var score = 3 + userBoost(entry.count)
            if wordFolded.count == folded.count { score += 3 }
            if word.lowercased().hasPrefix(lower) { score += 0.5 }
            offer(word, score)
        }

        // 3. Literówki (odległość edycyjna 1), gdy brakuje lepszych kandydatów.
        if pool.count < limit, folded.count >= 3 {
            for variant in Self.edits(of: folded) {
                for e in exactMatches(folded: variant) {
                    offer(e.word, e.score - 2)
                }
            }
        }

        let ranked = pool.values
            .filter { !user.isBlocked($0.display) && $0.display.lowercased() != lower }
            .sorted { $0.score > $1.score }

        var result = [Suggestion(text: typed, kind: .verbatim, isKnown: isKnown(typed, user: user))]
        for item in ranked.prefix(limit - 1) {
            result.append(Suggestion(text: Self.applyCase(of: typed, to: item.display),
                                     kind: .prediction, isKnown: true))
        }
        return result
    }

    private func nextWordSuggestions(previous: String?, user: UserDictionary,
                                     capitalize: Bool, limit: Int) -> [Suggestion] {
        guard let previous, let nexts = user.bigrams[previous.lowercased()] else { return [] }
        return nexts
            .filter { !user.isBlocked($0.key) }
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { item -> Suggestion in
                let word = item.key
                let text = capitalize ? word.prefix(1).uppercased() + word.dropFirst() : word
                return Suggestion(text: text, kind: .prediction, isKnown: true)
            }
    }

    /// Autokorekta przy spacji — celowo zachowawcza: tylko przywraca polskie znaki
    /// („zolw” → „żółw”), i tylko gdy wpisany ciąg sam nie jest znanym słowem.
    func autocorrection(for typed: String, user: UserDictionary) -> String? {
        guard typed.count >= 2, !isKnown(typed, user: user) else { return nil }
        let lower = typed.lowercased()
        let folded = Self.fold(lower)
        guard folded == lower else { return nil }   // użytkownik sam wpisał polskie znaki
        let best = exactMatches(folded: folded)
            .filter { !user.isBlocked($0.word) }
            .max { $0.score < $1.score }
        guard let best else { return nil }
        return Self.applyCase(of: typed, to: best.word)
    }

    private static func edits(of word: String) -> Set<String> {
        let chars = Array(word)
        var result = Set<String>()
        for i in chars.indices {
            var deletion = chars
            deletion.remove(at: i)
            result.insert(String(deletion))
            if i + 1 < chars.count {
                var swapped = chars
                swapped.swapAt(i, i + 1)
                result.insert(String(swapped))
            }
            for letter in alphabet where letter != chars[i] {
                var replaced = chars
                replaced[i] = letter
                result.insert(String(replaced))
            }
        }
        for i in 0...chars.count {
            for letter in alphabet {
                var inserted = chars
                inserted.insert(letter, at: i)
                result.insert(String(inserted))
            }
        }
        result.remove(word)
        return result
    }
}
