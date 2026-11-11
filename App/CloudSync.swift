import CloudKit
import Foundation

/// Synchronizacja słownika użytkownika z prywatną bazą CloudKit (iCloud).
/// Cały słownik to jeden rekord z plikiem JSON; scalanie robi `UserDictionary.merged`,
/// więc kilka urządzeń może pisać niezależnie i nic nie ginie.
final class CloudSync {
    private let database = CKContainer(identifier: AppGroup.cloudContainerID).privateCloudDatabase
    private let recordID = CKRecord.ID(recordName: "userDictionary")
    private static let recordType = "UserDictionary"
    private static let payloadKey = "payload"

    func sync(store: DictionaryStore) async throws {
        do {
            try await syncOnce(store: store)
        } catch let error as CKError where error.code == .serverRecordChanged {
            // Inne urządzenie zapisało w międzyczasie — pobierz i scal jeszcze raz.
            try await syncOnce(store: store)
        }
    }

    private func syncOnce(store: DictionaryStore) async throws {
        let record: CKRecord
        do {
            record = try await database.record(for: recordID)
            if let asset = record[Self.payloadKey] as? CKAsset, let url = asset.fileURL,
               let raw = try? Data(contentsOf: url), let remote = UserDictionary.decode(raw) {
                await MainActor.run { store.merge(remote) }
            }
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: Self.recordType, recordID: recordID)
        }

        let local = await MainActor.run { () -> Data? in
            store.reload()
            return store.data.encode()
        }
        guard let local else { return }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("user_dictionary_upload_\(UUID().uuidString).json")
        try local.write(to: tempURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        record[Self.payloadKey] = CKAsset(fileURL: tempURL)
        _ = try await database.save(record)
    }
}
