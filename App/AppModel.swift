import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var learned: [(word: String, count: Int)] = []
    @Published var blocked: [String] = []
    @Published var syncStatus = "Jeszcze nie synchronizowano"
    @Published var isSyncing = false
    @Published var selectedTab = 0
    @Published var dictationRequest = 0
    @Published var autocorrect = SharedSettings.autocorrectEnabled {
        didSet { SharedSettings.autocorrectEnabled = autocorrect }
    }

    private let store = DictionaryStore.shared
    private let cloud = CloudSync()

    var hasSharedContainer: Bool { AppGroup.containerURL != nil }

    func refresh() {
        store.reload()
        learned = store.data.activeLearned
        blocked = store.data.activeBlocked
    }

    func addWord(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.learn(trimmed, explicit: true)
        commit()
    }

    func forget(_ word: String) {
        store.forget(word)
        commit()
    }

    func block(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.block(trimmed)
        commit()
    }

    func unblock(_ word: String) {
        store.unblock(word)
        commit()
    }

    private func commit() {
        store.save()
        refresh()
        sync()
    }

    func sync() {
        guard !isSyncing else { return }
        isSyncing = true
        syncStatus = "Synchronizacja z iCloud…"
        Task {
            do {
                try await cloud.sync(store: store)
                let time = Date().formatted(date: .omitted, time: .shortened)
                syncStatus = "Zsynchronizowano z iCloud o \(time)"
            } catch {
                syncStatus = "Błąd synchronizacji: \(error.localizedDescription)"
            }
            isSyncing = false
            refresh()
        }
    }

    func handle(url: URL) {
        guard url.scheme == AppGroup.urlScheme else { return }
        if url.host == "dictate" {
            selectedTab = 3
            dictationRequest += 1
        }
    }
}
