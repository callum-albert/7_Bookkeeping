import Foundation

/// 跨设备同步快照
struct SyncPayload: Codable {
    var version: Int = 2
    var exportedAt: Date
    var deviceName: String
    var entries: [Entry]
    var ignored: [LedgerStore.IgnoredEvent]
    var deletedIDs: [UUID]
    var balances: [String: Int]
    var customCategories: [Category]? = nil
    var deletedCategories: [String]? = nil
    var bankCards: [BankCard]? = nil
    var transfers: [LedgerStore.Transfer]? = nil
}
