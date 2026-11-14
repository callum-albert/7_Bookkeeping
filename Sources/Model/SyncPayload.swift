import Foundation

/// 跨设备同步快照
struct SyncPayload: Codable {
    var version: Int = 1
    var exportedAt: Date
    var deviceName: String
    var entries: [Entry]
    var ignored: [LedgerStore.IgnoredEvent]
    var deletedIDs: [UUID]
    var balances: [String: Int]
}
