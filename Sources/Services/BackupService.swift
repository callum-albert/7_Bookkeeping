import Foundation
import UIKit
import Observation

/// iCloud Drive 文件夹备份 / 同步
///
/// 说明：免费签名无法申请 iCloud 容器 entitlement（CloudKit / iCloud Documents），
/// 所以这里用「用户选择一个 iCloud Drive 文件夹 + 安全作用域书签」的方式：
/// - 文件真实存放在 iCloud Drive，会自动上传到云端
/// - 换手机后重新选一次同一文件夹即可自动合并恢复
@MainActor
@Observable
final class BackupService {
    static let shared = BackupService()

    private(set) var folderName: String?
    private(set) var lastSyncAt: Date?
    private(set) var lastError: String?
    private(set) var lastSummary: String?
    private(set) var isWorking = false

    var isConfigured: Bool { folderURL != nil }

    private var folderURL: URL?
    private var debounceTask: Task<Void, Never>?

    private let bookmarkKey = "syncFolderBookmark"
    private let lastSyncKey = "syncLastSyncAt"
    private static let fileName = "7jizhang-backup.json"

    init() {
        restoreBookmark()
        lastSyncAt = UserDefaults.standard.object(forKey: lastSyncKey) as? Date
        // 数据变更 → 自动备份（防抖）
        LedgerStore.shared.onDataChanged = {
            Task { @MainActor in BackupService.shared.scheduleBackup() }
        }
    }

    // MARK: - 书签
    private func restoreBookmark() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                 options: [.withoutUI],
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else { return }
        folderURL = url
        folderName = url.lastPathComponent
    }

    /// 用户选择了一个文件夹（fileImporter 回调）
    func connect(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try url.bookmarkData(options: [],
                                            includingResourceValuesForKeys: nil,
                                            relativeTo: nil)
            UserDefaults.standard.set(data, forKey: bookmarkKey)
            folderURL = url
            folderName = url.lastPathComponent
            lastError = nil
            lastSummary = "已连接，正在合并…"
            Task {
                await pull(force: true)
                await backupNow()
            }
        } catch {
            lastError = "无法保存文件夹权限：\(error.localizedDescription)"
        }
    }

    func disconnect() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        folderURL = nil
        folderName = nil
        lastSummary = nil
        lastError = nil
    }

    // MARK: - 读写
    private func withFolder<T>(_ body: (URL) throws -> T) -> T? {
        guard let url = folderURL else { return nil }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do { return try body(url) } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: - 备份
    @discardableResult
    func backupNow() async -> Bool {
        guard folderURL != nil else {
            lastError = "还没有选择 iCloud 文件夹"
            return false
        }
        isWorking = true
        defer { isWorking = false }

        let payload = LedgerStore.shared.exportPayload()
        let ok: Bool = withFolder { folder in
            let data = try Self.encoder.encode(payload)
            try data.write(to: folder.appendingPathComponent(Self.fileName), options: .atomic)
            return true
        } ?? false

        if ok {
            lastSyncAt = Date()
            UserDefaults.standard.set(lastSyncAt, forKey: lastSyncKey)
            lastSummary = "已备份 \(payload.entries.count) 笔"
            lastError = nil
        }
        return ok
    }

    /// 记账后延迟 3 秒自动备份（避免连续操作时频繁写盘）
    func scheduleBackup() {
        guard folderURL != nil else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await self?.backupNow()
        }
    }

    // MARK: - 恢复 / 拉取
    @discardableResult
    func pull(force: Bool = false) async -> String {
        guard folderURL != nil else { return "还没有选择 iCloud 文件夹" }
        isWorking = true
        defer { isWorking = false }

        let wasEmpty = LedgerStore.shared.entries.isEmpty
        let loaded: SyncPayload? = withFolder { folder -> SyncPayload? in
            let url = folder.appendingPathComponent(Self.fileName)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let data = try Data(contentsOf: url)
            return try Self.decoder.decode(SyncPayload.self, from: data)
        } ?? nil

        guard let payload = loaded else {
            return "iCloud 里还没有备份文件"
        }

        // 非强制时，只有远端更新过才合并
        if !force, let last = lastSyncAt, payload.exportedAt <= last, !wasEmpty {
            return "已是最新"
        }

        let merged = LedgerStore.shared.mergeRemote(payload)
        // 新装设备首次恢复时，把余额也带过来
        if wasEmpty, !payload.balances.isEmpty {
            Accounts.shared.importBalances(payload.balances)
        }

        lastSyncAt = Date()
        UserDefaults.standard.set(lastSyncAt, forKey: lastSyncKey)
        lastError = nil
        let msg = "已合并：新增 \(merged.added) · 更新 \(merged.updated) · 移除 \(merged.removed)"
        lastSummary = msg
        return msg
    }

    /// App 回到前台时拉取（静默）
    func pullIfNeeded() {
        guard folderURL != nil else { return }
        Task { _ = await pull(force: false) }
    }
}
