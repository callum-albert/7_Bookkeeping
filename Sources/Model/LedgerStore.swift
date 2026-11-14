import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// 轻量本地存储：JSON 落盘，无外部依赖
@Observable
final class LedgerStore {
    static let shared = LedgerStore()

    private(set) var entries: [Entry] = []
    /// 被判定为「转账 / 收款 / 退款」而忽略的事件，供用户复核，防止漏记
    private(set) var ignored: [IgnoredEvent] = []

    /// 可注入的存储目录（测试时可指向临时目录）
    static var storageDirectory: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

    /// 已删除的账目 id（墓碑），用于跨设备同步时不被"复活"
    private(set) var deletedIDs: [UUID] = []

    private let fileURL: URL
    private let ignoredURL: URL
    private let deletedURL: URL

    var lastAdded: Entry?

    /// 数据变化回调（App 启动时注入，用来触发 iCloud 自动备份）
    var onDataChanged: (() -> Void)?

    struct IgnoredEvent: Codable, Identifiable {
        var id = UUID()
        var date: Date
        var reason: String
        var text: String
        var amountCents: Int?
        var source: Source
    }

    /// 触发来源：手动按键/截图需要更宽的合并窗口，但强去重
    enum Trigger {
        case automatic   // 银行短信 / 邮件 / 剪贴板自动检测
        case manual      // 操作按钮 / 截图识别 / 手动粘贴

        /// 跨渠道合并窗口
        var window: TimeInterval { self == .manual ? 1800 : 300 }
        /// 强重复窗口（极短时间内同金额视为同一笔）
        var strongWindow: TimeInterval { self == .manual ? 150 : 90 }
    }

    enum Outcome {
        case inserted(Entry)      // 新记一笔
        case merged(Entry)        // 与其它渠道的消息合并
        case duplicate(Entry)     // 完全重复，丢弃
        case ignored(String)      // 转账/收入，不入账
    }

    init() {
        let dir = Self.storageDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("ledger.json")
        ignoredURL = dir.appendingPathComponent("ignored.json")
        deletedURL = dir.appendingPathComponent("deleted.json")
        load()
        var repaired = false
        for index in entries.indices {
            let old = entries[index].merchant
            // 老版本 raw 可能只保存字段区，不含顶部金额；使用已存金额辅助解析，不修改金额。
            let reparsedText = entries[index].raw + "\n金额 " + entries[index].amountCents.moneyText
            if let parsed = BillParser.parse(reparsedText).first,
               parsed.amountCents == entries[index].amountCents,
               parsed.merchant.count > old.count, parsed.merchant.hasPrefix(old),
               ["司", "公司", "限公司", "有限公司"].contains(String(parsed.merchant.dropFirst(old.count))) {
                entries[index].merchant = parsed.merchant
                entries[index].updatedAt = Date()
                repaired = true
            }
        }
        if repaired { persist() }
        for entry in entries { registerCard(account: entry.account, channel: entry.channel) }
    }

    // MARK: - 持久化
    private func load() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = decoded
        }
        if let data = try? Data(contentsOf: ignoredURL),
           let decoded = try? JSONDecoder().decode([IgnoredEvent].self, from: data) {
            ignored = decoded
        }
        if let data = try? Data(contentsOf: deletedURL),
           let decoded = try? JSONDecoder().decode([UUID].self, from: data) {
            deletedIDs = decoded
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
        if let data = try? JSONEncoder().encode(ignored) {
            try? data.write(to: ignoredURL, options: .atomic)
        }
        if let data = try? JSONEncoder().encode(deletedIDs) {
            try? data.write(to: deletedURL, options: .atomic)
        }
    }

    // MARK: - 核心：入账（含跨渠道去重）
    @discardableResult
    func ingest(_ p: BillParser.Parsed, trigger: Trigger = .automatic) -> Outcome {
        // 1) 非消费，直接忽略并留档
        if p.flow == .transfer {
            let reason = p.flow == .transfer ? "转账 / 提现 / 还款" : "收款 / 退款"
            recordIgnored(p, reason: reason)
            return .ignored(reason)
        }

        // 2) 找候选：金额相同 + 时间接近
        registerCard(account: p.account, channel: p.channel)
        if !p.transactionID.isEmpty, let same = entries.first(where: {
            $0.kind == p.kind && $0.source == p.source && $0.transactionID == p.transactionID
        }) {
            var updated = same
            merge(&updated, with: p)
            guard updated != same else { return .duplicate(same) }
            update(updated)
            if updated.channel != same.channel || updated.account != same.account {
                applyBalance(same, undo: true); applyBalance(updated)
            }
            return .merged(updated)
        }
        //    自动触发 5 分钟；手动触发 30 分钟（人按按钮可能晚一点）
        let candidates = entries.filter {
            $0.kind == p.kind && $0.amountCents == p.amountCents
            && abs($0.date.timeIntervalSince(p.date)) <= trigger.window
            && !(p.source != .manual && $0.source == p.source && paidTimesConflict($0, p))
            && !(bankTail(of: $0.account).isEmpty == false && bankTail(of: p.account).isEmpty == false && bankTail(of: $0.account) != bankTail(of: p.account))
            && !(bankName(of: $0.account).isEmpty == false && bankName(of: p.account).isEmpty == false && bankName(of: $0.account) != bankName(of: p.account))
            && !($0.source == p.source && !$0.transactionID.isEmpty && !p.transactionID.isEmpty && $0.transactionID != p.transactionID)
        }

        // 3) 强重复：极短时间内同金额，且至少一方信息模糊 → 同一笔
        //    覆盖「连按两次按钮」和「银行短信与手动记账几乎同时到达」
        if let same = candidates.first(where: { e in
            if (e.source == .wechat && p.source == .alipay) || (e.source == .alipay && p.source == .wechat) { return false }
            let dt = abs(e.date.timeIntervalSince(p.date))
            guard dt <= trigger.strongWindow else { return false }
            guard isVague(e) || isVague(p) else { return false }
            // 同平台、都有商户、商户又对不上 → 那是两笔真实消费，不合并
            if e.source == p.source, !isVague(e), !isVague(p), !fuzzyMatch(e.merchant, p.merchant) {
                return false
            }
            return true
        }) {
            // 已有记录信息更少 → 把新信息补进去（例如银行短信 + 截图商户名、卡尾号）
            let bringsNewInfo = !isVague(p) || !p.account.isEmpty || p.channel != .unknown
            if isVague(same), bringsNewInfo {
                var e = same
                let oldEntry = e
                merge(&e, with: p)
                update(e)
                if oldEntry.channel != e.channel || oldEntry.account != e.account {
                    applyBalance(oldEntry, undo: true)
                    applyBalance(e)
                }
                return .merged(e)
            }
            return .duplicate(same)
        }

        // 4) 完全重复：同一平台重复推送（微信常有 2 条）
        if let same = candidates.first(where: {
            $0.source == p.source
            && abs($0.date.timeIntervalSince(p.date)) <= 150
            && fuzzyMatch($0.merchant, p.merchant)
        }) {
            return .duplicate(same)
        }

        // 5) 跨渠道合并：微信/支付宝 ↔ 银行短信/手机银行 ↔ 手动按键
        if let existing = candidates.first(where: { canMerge($0, p) }) {
            var e = existing
            let oldEntry = e
            merge(&e, with: p)
            update(e)

            // 渠道变了 → 把余额从旧资金池挪到新资金池
            if oldEntry.channel != e.channel || oldEntry.account != e.account {
                applyBalance(oldEntry, undo: true)
                applyBalance(e)
            }
            // 短信里带余额 → 以余额为准校准
            if let bal = p.balanceAfter, e.channel.balanceBucket == .bank {
                Accounts.shared.applyBankBalance(bal, tail: bankTail(of: e.account), bankName: bankName(of: e.account))
            }
            return .merged(e)
        }

        // 6) 新建
        let entry = Entry(
            amountCents: p.amountCents,
            date: p.date,
            category: p.category,
            merchant: p.merchant.isEmpty ? p.source.title : p.merchant,
            note: "",
            source: p.source,
            raw: p.raw,
            auto: true,
            account: p.account,
            needsReview: p.needsReview,
            channel: p.channel,
            hasPaidTime: p.hasPaidTime, product: p.product, transactionID: p.transactionID, kind: p.kind
        )
        add(entry)

        let tail = bankTail(of: entry.account)
        applyBalance(entry)
        if let bal = p.balanceAfter, entry.channel.balanceBucket == .bank {
            Accounts.shared.applyBankBalance(bal, tail: tail, bankName: bankName(of: entry.account))
        }
        return .inserted(entry)
    }

    private func canMerge(_ existing: Entry, _ p: BillParser.Parsed) -> Bool {
        if (existing.source == .wechat && p.source == .alipay) || (existing.source == .alipay && p.source == .wechat) { return false }
        // 同一平台：只有商户也对得上才合并（否则是真的两笔）
        if existing.source == p.source {
            return fuzzyMatch(existing.merchant, p.merchant)
        }
        // 跨平台：任意一方信息模糊（银行短信无商户 / 待确认）即可合并
        let existingVague = isVague(existing)
        let newVague = isVague(p)
        if existingVague || newVague { return true }
        return fuzzyMatch(existing.merchant, p.merchant)
    }

    /// 合并两个渠道的同一笔消费，保留信息更全的一方
    private func merge(_ e: inout Entry, with p: BillParser.Parsed) {
        let wasReview = e.needsReview
        // 交易时间取更早的（通知可能延迟）；任一方是真实支付时间就采用
        if p.hasPaidTime && !e.hasPaidTime {
            e.date = p.date
            e.hasPaidTime = true
        } else if p.date < e.date {
            e.date = p.date
        }

        // 商户：优先「具体商户名」，跳过「微信支付 / 银行卡」这类来源名
        let newIsConcrete = !p.merchant.isEmpty && p.merchant != p.source.title
        let oldIsConcrete = !e.merchant.isEmpty && e.merchant != e.source.title
        if newIsConcrete && (!oldIsConcrete || p.merchant.count > e.merchant.count) {
            e.merchant = p.merchant
            e.category = p.category == .other ? e.category : p.category
        }

        if !p.product.isEmpty { e.product = p.product }
        if e.transactionID.isEmpty { e.transactionID = p.transactionID }

        // 渠道信息累加：招商银行(1234) · 零钱
        if !p.account.isEmpty, !e.account.contains(p.account) {
            if e.account.isEmpty || (bankTail(of: e.account).isEmpty && !bankTail(of: p.account).isEmpty) { e.account = p.account }
        }

        // 来源升级：通知类（微信/支付宝）比银行短信信息更全
        if p.source.richness > e.source.richness {
            if p.source != e.source { e.mergedSources.append(e.source.title) }
            e.source = p.source
        } else if p.source != e.source {
            e.mergedSources.append(p.source.title)
        }

        // 渠道：越具体越优先（花呗/零钱 > 银行卡 > 未识别）
        if channelPriority(p.channel) > channelPriority(e.channel) {
            e.channel = p.channel
        }
        if !p.raw.isEmpty, !e.raw.contains(p.raw) {
            e.raw = e.raw.isEmpty ? p.raw : e.raw + "\n" + p.raw
        }

        // 商户仍然只是来源名 → 仍需确认
        e.needsReview = (newIsConcrete && p.source != .bank ? p.needsReview : wasReview)
            || e.merchant.isEmpty || e.merchant == e.source.title || (e.source == .bank && e.merchant.count < 2)
    }

    /// 信息是否模糊（没有可用商户名，或来自银行短信）
    private func isVague(_ e: Entry) -> Bool {
        e.merchant.isEmpty
            || e.merchant == e.source.title
            || ["财付通", "微信支付", "支付宝", "银联", "网联", "快捷支付"].contains(e.merchant)
    }

    private func isVague(_ p: BillParser.Parsed) -> Bool {
        p.merchant.isEmpty || p.merchant == p.source.title
            || ["财付通", "微信支付", "支付宝", "银联", "网联", "快捷支付"].contains(p.merchant)
    }

    private func channelPriority(_ c: PayChannel) -> Int {
        switch c {
        case .huabei, .creditCard: return 4
        case .wechatZero, .alipayBalance: return 3
        case .wechatCard, .alipayCard: return 2
        case .bank: return 1
        case .unknown: return 0
        }
    }

    private func bankName(of account: String) -> String {
        BillParser.bankNames.first { account.contains($0) } ?? ""
    }

    private func paidTimesConflict(_ entry: Entry, _ parsed: BillParser.Parsed) -> Bool {
        guard entry.hasPaidTime, parsed.hasPaidTime,
              abs(entry.date.timeIntervalSince(parsed.date)) > 1 else { return false }
        func includesSeconds(_ text: String) -> Bool {
            text.range(of: #"[0-9]{1,2}[:：][0-9]{2}[:：][0-9]{2}"#, options: .regularExpression) != nil
        }
        if includesSeconds(entry.raw) && includesSeconds(parsed.raw) { return true }
        // 一条只显示分钟、另一条显示秒时，同一分钟内仍可能是同一笔。
        return !Calendar.current.isDate(entry.date, equalTo: parsed.date, toGranularity: .minute)
    }

    private func registerCard(account: String, channel: PayChannel) {
        let name = bankName(of: account), tail = bankTail(of: account)
        guard channel.balanceBucket == .bank || channel == .creditCard || (!name.isEmpty && !tail.isEmpty) else { return }
        guard !name.isEmpty || !tail.isEmpty else { return }
        Accounts.shared.upsertCard(bankName: name, tail: tail)
    }

    private func applyBalance(_ entry: Entry, undo: Bool = false) {
        let name = bankName(of: entry.account), tail = bankTail(of: entry.account)
        if (entry.kind == .income) != undo {
            Accounts.shared.refund(entry.amountCents, channel: entry.channel, tail: tail, bankName: name)
        } else {
            Accounts.shared.charge(entry.amountCents, channel: entry.channel, tail: tail, bankName: name)
        }
    }

    private func bankTail(of account: String) -> String {
        guard let r = account.range(of: #"\((\d{4})\)"#, options: .regularExpression) else { return "" }
        let s = account[r]
        return s.trimmingCharacters(in: CharacterSet(charactersIn: "()"))
    }

    /// 商户模糊匹配：去符号后互相包含，或前 4 个字符一致
    private func fuzzyMatch(_ a: String, _ b: String) -> Bool {
        let na = normalizeName(a)
        let nb = normalizeName(b)
        if na.isEmpty || nb.isEmpty { return na.isEmpty && nb.isEmpty }
        if na == nb { return true }
        return min(na.count, nb.count) >= 2 && (na.contains(nb) || nb.contains(na))
    }

    private func normalizeName(_ s: String) -> String {
        let noise = ["微信支付", "支付宝", "银行卡", "银行", "信用卡", "消费", "支付", "付款", "有限公司", "科技"]
        var t = s.lowercased()
        for n in noise { t = t.replacingOccurrences(of: n, with: "") }
        return t.filter { $0.isLetter || $0.isNumber }
    }

    private func recordIgnored(_ p: BillParser.Parsed, reason: String) {
        let ev = IgnoredEvent(date: p.date, reason: reason, text: p.raw,
                              amountCents: p.amountCents, source: p.source)
        ignored.insert(ev, at: 0)
        if ignored.count > 200 { ignored = Array(ignored.prefix(200)) }
        persist()
    }

    /// 用户确认忽略，不再展示
    func dismissIgnored(_ ev: IgnoredEvent) {
        ignored.removeAll { $0.id == ev.id }
        persist()
    }

    /// 用户复核：这条其实是消费，捞回来入账
    func restoreIgnored(_ ev: IgnoredEvent) {
        ignored.removeAll { $0.id == ev.id }
        guard let cents = ev.amountCents else { persist(); return }
        var parsed = BillParser.parse(ev.text).first ?? BillParser.Parsed(
            amountCents: cents, source: ev.source, category: .other, merchant: ev.source.title,
            account: "", date: ev.date, raw: ev.text, flow: .expense,
            needsReview: true, channel: .unknown, balanceAfter: nil)
        if parsed.flow == .transfer { parsed.flow = .expense }
        parsed.needsReview = true
        switch ingest(parsed, trigger: .manual) {
        case .inserted(var entry), .merged(var entry):
            entry.auto = false; update(entry)
        default: break
        }
        persist()
    }

    // MARK: - CRUD
    func add(_ entry: Entry) {
        var e = entry
        e.updatedAt = Date()
        entries.append(e)
        lastAdded = e
        persist()
        onDataChanged?()
    }

    func update(_ entry: Entry) {
        guard let i = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var e = entry
        e.updatedAt = Date()
        entries[i] = e
        persist()
        onDataChanged?()
    }

    func delete(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
        if !deletedIDs.contains(entry.id) { deletedIDs.append(entry.id) }
        if deletedIDs.count > 500 { deletedIDs = Array(deletedIDs.suffix(500)) }
        applyBalance(entry, undo: true)
        persist()
        onDataChanged?()
    }

    func deleteAll() {
        entries.removeAll()
        ignored.removeAll()
        persist()
    }

    // MARK: - 跨设备同步
    static var deviceName: String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return ProcessInfo.processInfo.hostName
        #endif
    }

    func exportPayload() -> SyncPayload {
        SyncPayload(
            exportedAt: Date(),
            deviceName: Self.deviceName,
            entries: entries,
            ignored: Array(ignored.prefix(200)),
            deletedIDs: deletedIDs,
            balances: Accounts.shared.exportBalances(),
            customCategories: CategoryStore.shared.categories, deletedCategories: CategoryStore.shared.deleted
        )
    }

    /// 合并远端快照：按 id 去重，updatedAt 新者胜；墓碑优先
    @discardableResult
    func mergeRemote(_ payload: SyncPayload) -> (added: Int, updated: Int, removed: Int) {
        CategoryStore.shared.merge(payload.customCategories ?? [], deleted: payload.deletedCategories ?? [])
        var tomb = Set(deletedIDs)
        for id in payload.deletedIDs { tomb.insert(id) }
        deletedIDs = Array(tomb)

        var byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        var added = 0, updated = 0

        for remote in payload.entries {
            if tomb.contains(remote.id) { continue }
            if let local = byID[remote.id] {
                if remote.updatedAt > local.updatedAt {
                    byID[remote.id] = remote
                    updated += 1
                }
            } else {
                byID[remote.id] = remote
                added += 1
            }
        }

        let before = byID.count
        byID = byID.filter { !tomb.contains($0.key) }
        let removed = before - byID.count

        entries = byID.values.sorted { $0.date > $1.date }

        // 忽略记录合并（按 id）
        var ignIDs = Set(ignored.map(\.id))
        for ev in payload.ignored where !ignIDs.contains(ev.id) {
            ignored.append(ev)
            ignIDs.insert(ev.id)
        }
        ignored.sort { $0.date > $1.date }
        if ignored.count > 200 { ignored = Array(ignored.prefix(200)) }

        if added > 0 || updated > 0 || removed > 0 { persist() }
        return (added, updated, removed)
    }


    // MARK: - 统计
    struct Summary {
        var total: Int = 0
        var count: Int = 0
        var byCategory: [(Category, Int)] = []
        var daily: [(Date, Int)] = []

        var average: Int { count == 0 ? 0 : total / count }
    }

    func entries(in range: DateInterval) -> [Entry] {
        entries.filter { $0.date >= range.start && $0.date < range.end }.sorted { $0.date > $1.date }
    }

    func summary(in range: DateInterval, kind: EntryKind = .expense) -> Summary {
        let items = entries(in: range).filter { $0.kind == kind }
        var s = Summary()
        s.count = items.count
        s.total = items.reduce(0) { $0 + $1.amountCents }

        var cat: [Category: Int] = [:]
        for e in items { cat[e.category, default: 0] += e.amountCents }
        s.byCategory = cat.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }

        var day: [Date: Int] = [:]
        let cal = Calendar.current
        for e in items { day[cal.startOfDay(for: e.date), default: 0] += e.amountCents }
        s.daily = day.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        return s
    }

    func dailySeries(in range: DateInterval) -> [(Date, Int)] {
        let cal = Calendar.current
        var map: [Date: Int] = [:]
        for e in entries(in: range) where e.kind == .expense {
            map[cal.startOfDay(for: e.date), default: 0] += e.amountCents
        }
        var out: [(Date, Int)] = []
        var day = cal.startOfDay(for: range.start)
        let last = cal.startOfDay(for: range.end.addingTimeInterval(-1))
        while day <= last {
            out.append((day, map[day] ?? 0))
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return out
    }
}

// MARK: - 时间区间
enum Period: String, CaseIterable, Identifiable {
    case day, week, month, year
    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return "日"
        case .week: return "周"
        case .month: return "月"
        case .year: return "年"
        }
    }

    var label: String {
        switch self {
        case .day: return "今日"
        case .week: return "本周"
        case .month: return "本月"
        case .year: return "今年"
        }
    }

    func range(containing date: Date = Date()) -> DateInterval {
        var cal = Calendar.current
        cal.firstWeekday = 2
        switch self {
        case .day: return cal.dateInterval(of: .day, for: date)!
        case .week: return cal.dateInterval(of: .weekOfYear, for: date)!
        case .month: return cal.dateInterval(of: .month, for: date)!
        case .year: return cal.dateInterval(of: .year, for: date)!
        }
    }

    func previous(of date: Date = Date()) -> DateInterval {
        range(containing: range(containing: date).start.addingTimeInterval(-1))
    }
}

extension Int {
    var moneyText: String {
        let v = Double(self) / 100.0
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "CNY"
        f.currencySymbol = "¥"
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? "¥\(v)"
    }

    var amountOnly: String {
        let v = Double(self) / 100.0
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = (self % 100 == 0) ? 0 : 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }
}
