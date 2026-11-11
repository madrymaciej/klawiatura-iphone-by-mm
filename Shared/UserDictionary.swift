import Foundation

/// Pojedynczy wpis słownika użytkownika. `updatedAt` + `deleted` (tombstone)
/// pozwalają bezkonfliktowo scalać dane z kilku urządzeń: wygrywa nowszy wpis.
struct WordEntry: Codable, Equatable {
    var count: Int
    var updatedAt: Date
    var deleted: Bool
}

struct UserDictionary: Codable, Equatable {
    /// Słowa nauczone (klucz = słowo w zapisie użytkownika).
    var learned: [String: WordEntry] = [:]
    /// Słowa, których nie wolno podpowiadać (klucz = małe litery).
    var blocked: [String: WordEntry] = [:]
    /// Pary „poprzednie słowo → następne słowo → liczba użyć” do podpowiedzi kolejnego słowa.
    var bigrams: [String: [String: Int]] = [:]

    /// Od ilu użyć słowo spoza słownika bazowego zaczyna być podpowiadane.
    static let suggestThreshold = 2

    func isBlocked(_ word: String) -> Bool {
        if let e = blocked[word.lowercased()] { return !e.deleted }
        return false
    }

    var activeLearned: [(word: String, count: Int)] {
        learned.compactMap { $0.value.deleted ? nil : (word: $0.key, count: $0.value.count) }
            .sorted { $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending }
    }

    var activeBlocked: [String] {
        blocked.compactMap { $0.value.deleted ? nil : $0.key }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private static func newer(_ a: WordEntry, _ b: WordEntry) -> WordEntry {
        if a.updatedAt == b.updatedAt {
            return a.count >= b.count ? a : b
        }
        return a.updatedAt > b.updatedAt ? a : b
    }

    func merged(with other: UserDictionary) -> UserDictionary {
        var result = self
        result.learned.merge(other.learned) { Self.newer($0, $1) }
        result.blocked.merge(other.blocked) { Self.newer($0, $1) }
        for (prev, nexts) in other.bigrams {
            result.bigrams[prev, default: [:]].merge(nexts) { max($0, $1) }
        }
        return result
    }

    static func decode(_ data: Data) -> UserDictionary? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(UserDictionary.self, from: data)
    }

    func encode() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return try? encoder.encode(self)
    }
}

/// Trwały magazyn słownika użytkownika — plik JSON w kontenerze App Group,
/// współdzielony przez aplikację i klawiaturę. Synchronizację z iCloud robi aplikacja.
final class DictionaryStore {
    static let shared = DictionaryStore()

    private(set) var data = UserDictionary()
    private let fileURL: URL?
    private var pendingSave: DispatchWorkItem?
    private static let maxBigramKeys = 3000

    init() {
        fileURL = AppGroup.containerURL?.appendingPathComponent("user_dictionary.json")
        reload()
    }

    /// Wczytuje plik i scala go ze stanem w pamięci (drugi proces mógł coś dopisać).
    func reload() {
        guard let fileURL, let raw = try? Data(contentsOf: fileURL),
              let disk = UserDictionary.decode(raw) else { return }
        data = data.merged(with: disk)
    }

    func save() {
        pendingSave?.cancel()
        pendingSave = nil
        guard let fileURL else { return }
        reload()
        pruneBigrams()
        guard let raw = data.encode() else { return }
        try? raw.write(to: fileURL, options: .atomic)
    }

    /// Zapis z opóźnieniem — klawiatura nie pisze na dysk po każdym słowie.
    func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    func merge(_ other: UserDictionary) {
        data = data.merged(with: other)
        save()
    }

    // MARK: - Modyfikacje

    /// `explicit` = użytkownik świadomie dodał słowo (od razu jest podpowiadane).
    func learn(_ word: String, explicit: Bool) {
        guard !word.isEmpty else { return }
        var entry = data.learned[word] ?? WordEntry(count: 0, updatedAt: Date(), deleted: false)
        if entry.deleted {
            entry.deleted = false
            entry.count = 0
        }
        entry.count += explicit ? UserDictionary.suggestThreshold : 1
        entry.updatedAt = Date()
        data.learned[word] = entry
        if explicit { unblock(word, saveNow: false) }
        scheduleSave()
    }

    func forget(_ word: String) {
        guard data.learned[word] != nil else { return }
        data.learned[word] = WordEntry(count: 0, updatedAt: Date(), deleted: true)
        scheduleSave()
    }

    func block(_ word: String) {
        let key = word.lowercased()
        guard !key.isEmpty else { return }
        data.blocked[key] = WordEntry(count: 1, updatedAt: Date(), deleted: false)
        scheduleSave()
    }

    func unblock(_ word: String, saveNow: Bool = true) {
        let key = word.lowercased()
        guard let e = data.blocked[key], !e.deleted else { return }
        data.blocked[key] = WordEntry(count: 0, updatedAt: Date(), deleted: true)
        if saveNow { scheduleSave() }
    }

    func recordBigram(previous: String, next: String) {
        let p = previous.lowercased()
        guard !p.isEmpty, !next.isEmpty else { return }
        data.bigrams[p, default: [:]][next, default: 0] += 1
        scheduleSave()
    }

    private func pruneBigrams() {
        guard data.bigrams.count > Self.maxBigramKeys else { return }
        let ranked = data.bigrams
            .map { (key: $0.key, total: $0.value.values.reduce(0, +)) }
            .sorted { $0.total > $1.total }
        for item in ranked.dropFirst(Self.maxBigramKeys * 3 / 4) {
            data.bigrams[item.key] = nil
        }
    }
}
