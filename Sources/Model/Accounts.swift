import Foundation
import SwiftUI
import Observation

// MARK: - 支付渠道
enum PayChannel: String, Codable, CaseIterable {
    case wechatZero       // 微信零钱
    case wechatCard       // 微信绑定的银行卡
    case alipayBalance    // 支付宝余额
    case alipayCard       // 支付宝绑定的银行卡
    case bank             // 直接刷银行卡 / 银行短信
    case huabei           // 花呗（信贷）
    case creditCard       // 信用卡（信贷）
    case unknown

    var title: String {
        switch self {
        case .wechatZero: return "零钱"
        case .wechatCard: return "微信银行卡"
        case .alipayBalance: return "余额"
        case .alipayCard: return "支付宝银行卡"
        case .bank: return "银行卡"
        case .huabei: return "花呗"
        case .creditCard: return "信用卡"
        case .unknown: return "未识别"
        }
    }

    var isCredit: Bool { self == .huabei || self == .creditCard }

    /// 是否从三大余额池里扣钱
    var balanceBucket: BalanceBucket? {
        switch self {
        case .wechatZero: return .wechat
        case .alipayBalance: return .alipay
        case .wechatCard, .alipayCard, .bank: return .bank
        case .huabei, .creditCard, .unknown: return nil
        }
    }
}

// MARK: - 余额池
enum BalanceBucket: String, Codable, CaseIterable, Identifiable {
    case wechat
    case alipay
    case bank

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wechat: return "微信余额"
        case .alipay: return "支付宝余额"
        case .bank: return "银行卡"
        }
    }

    var shortTitle: String {
        switch self {
        case .wechat: return "微信"
        case .alipay: return "支付宝"
        case .bank: return "银行卡"
        }
    }

    var symbol: String {
        switch self {
        case .wechat: return "message.fill"
        case .alipay: return "a.circle.fill"
        case .bank: return "creditcard.fill"
        }
    }

    var tint: Color {
        switch self {
        case .wechat: return Color(red: 0.13, green: 0.76, blue: 0.36)
        case .alipay: return Color(red: 0.10, green: 0.47, blue: 0.96)
        case .bank: return Color(red: 0.42, green: 0.46, blue: 0.58)
        }
    }
}

// MARK: - 单张银行卡
struct BankCard: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var bankName: String = ""        // 招商银行
    var tail: String = ""            // 1234
    var alias: String = ""           // 工资卡
    var balanceCents: Int = 0
    /// 余额是否由用户确认过（自动识别出来的卡为 false，显示"待设置"）
    var confirmed: Bool = false

    var displayName: String {
        if !alias.isEmpty { return alias }
        if bankName.isEmpty {
            return tail.isEmpty ? "银行卡" : "尾号\(tail)"
        }
        return tail.isEmpty ? bankName : "\(bankName)\(tail)"
    }

    var shortLabel: String {
        if !tail.isEmpty { return "尾号\(tail)" }
        return bankName.isEmpty ? "银行卡" : bankName
    }
}

// MARK: - 余额管理（微信 / 支付宝 / 多张银行卡）
@Observable
final class Accounts {
    static let shared = Accounts()

    private(set) var wechat: Int = 0
    private(set) var alipay: Int = 0
    private(set) var cards: [BankCard] = []

    /// 是否已由用户设定过（未设定时不显示数字，避免误导）
    private(set) var configured: Bool = false

    private let fileURL: URL

    private struct Snapshot: Codable {
        var wechat: Int
        var alipay: Int
        var bank: Int?            // 旧版本单一银行卡余额（迁移用）
        var cards: [BankCard]?
        var lastBankTail: String?
        var configured: Bool
    }

    init() {
        let dir = LedgerStore.storageDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("accounts.json")
        load()
    }

    // MARK: - 持久化
    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let s = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        wechat = s.wechat
        alipay = s.alipay
        if let cards = s.cards, !cards.isEmpty {
            self.cards = cards
        } else if let legacy = s.bank, legacy > 0 {
            // 老数据迁移：把单一银行卡余额变成一张卡
            cards = [BankCard(bankName: "银行卡", tail: s.lastBankTail ?? "",
                              balanceCents: legacy, confirmed: true)]
        }
        configured = s.configured
        normalizeCards()
    }

    private func persist() {
        let s = Snapshot(wechat: wechat, alipay: alipay, bank: nil,
                         cards: cards, lastBankTail: cards.first?.tail, configured: configured)
        if let data = try? JSONEncoder().encode(s) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: - 查询
    func balance(_ bucket: BalanceBucket) -> Int {
        switch bucket {
        case .wechat: return wechat
        case .alipay: return alipay
        case .bank: return bankTotal
        }
    }

    var bankTotal: Int { cards.reduce(0) { $0 + $1.balanceCents } }
    var total: Int { wechat + alipay + bankTotal }

    func card(tail: String, bankName: String = "") -> BankCard? {
        guard let index = indexOfCard(tail: tail, bankName: bankName) else { return nil }
        return cards[index]
    }

    // MARK: - 修改
    func setBalance(_ cents: Int, for bucket: BalanceBucket) {
        switch bucket {
        case .wechat: wechat = max(0, cents)
        case .alipay: alipay = max(0, cents)
        case .bank:
            if cards.isEmpty {
                cards = [BankCard(bankName: "银行卡", balanceCents: max(0, cents), confirmed: true)]
            } else {
                cards[0].balanceCents = max(0, cents)
                cards[0].confirmed = true
            }
        }
        configured = true
        persist()
    }

    func setAll(wechat: Int, alipay: Int, bank: Int) {
        self.wechat = max(0, wechat)
        self.alipay = max(0, alipay)
        if cards.isEmpty {
            cards = [BankCard(bankName: "银行卡", balanceCents: max(0, bank), confirmed: true)]
        } else {
            cards[0].balanceCents = max(0, bank)
            cards[0].confirmed = true
        }
        configured = true
        persist()
    }

    // MARK: - 银行卡管理
    @discardableResult
    func upsertCard(bankName: String, tail: String) -> BankCard {
        let normalized = Self.canonicalName(bankName)
        let name = normalized.isEmpty ? "银行卡" : normalized

        if !tail.isEmpty {
            // ① 尾号已存在 → 复用
            let exact = cards.firstIndex { $0.tail == tail && Self.canonicalName($0.bankName) == name }
            let unspecified = cards.firstIndex { $0.tail == tail && (bankName.isEmpty || $0.bankName == "银行卡" || $0.bankName.isEmpty) }
            if let i = exact ?? unspecified {
                if cards[i].bankName.isEmpty || cards[i].bankName == "银行卡" {
                    cards[i].bankName = name
                }
                persist()
                return cards[i]
            }
            // ② 有一张"未指定尾号"的卡 → 给它补上尾号，绝不新建
            if let i = cards.firstIndex(where: { $0.tail.isEmpty && ($0.bankName == name || $0.bankName == "银行卡" || $0.bankName.isEmpty) }) {
                let old = cards[i]
                cards[i] = BankCard(id: old.id, bankName: name, tail: tail,
                                    alias: old.alias, balanceCents: old.balanceCents,
                                    confirmed: old.confirmed)
                persist()
                return cards[i]
            }
        } else {
            // 无尾号：① 已有同名卡
            if let i = cards.firstIndex(where: { $0.tail.isEmpty && $0.bankName == name }) {
                persist()
                return cards[i]
            }
            // ② 只有一张"通用银行卡" → 直接改名成这家银行，不新建
            if let i = cards.firstIndex(where: {
                $0.tail.isEmpty && ($0.bankName.isEmpty || $0.bankName == "银行卡")
            }) {
                cards[i].bankName = name
                persist()
                return cards[i]
            }
            // ③ 同名但已有尾号（例如先有"招商银行(1234)"，又来一条"招商银行"无尾号短信）
            if let i = cards.firstIndex(where: { $0.bankName == name }) {
                persist()
                return cards[i]
            }
            if cards.count == 1 { return cards[0] }
        }

        let card = BankCard(bankName: name, tail: tail, confirmed: false)
        cards.append(card)
        configured = true
        persist()
        return card
    }

    /// 修复历史数据里重复的银行卡（同尾号 / 多张无尾号）
    func normalizeCards() {
        guard cards.count > 1 else { return }
        var changed = false

        // 同尾号去重：保留余额大的
        var byTail: [String: Int] = [:]
        for (i, c) in cards.enumerated() where !c.tail.isEmpty {
            let key = c.bankName + "|" + c.tail
            if let j = byTail[key] {
                if cards[i].balanceCents > cards[j].balanceCents { byTail[key] = i }
                changed = true
            } else {
                byTail[key] = i
            }
        }
        if changed {
            var keep = Set(byTail.values)
            keep.formUnion(cards.indices.filter { cards[$0].tail.isEmpty })
            cards = cards.indices.filter { keep.contains($0) }.map { cards[$0] }
        }

        // 多张无尾号卡 → 合并成一张
        let noTail = cards.enumerated().filter { $0.element.tail.isEmpty }
        if noTail.count > 1 && Set(noTail.map { $0.element.bankName }).count == 1 {
            let total = noTail.reduce(0) { $0 + $1.element.balanceCents }
            // 优先保留有具体银行名的
            let best = noTail.max { a, b in
                (a.element.bankName.isEmpty || a.element.bankName == "银行卡" ? 0 : 1)
                    < (b.element.bankName.isEmpty || b.element.bankName == "银行卡" ? 0 : 1)
            }!
            var merged = best.element
            merged.balanceCents = total
            merged.confirmed = noTail.contains { $0.element.confirmed }
            let dropIDs = Set(noTail.map { $0.element.id }).subtracting([best.element.id])
            cards.removeAll { dropIDs.contains($0.id) }
            if let i = cards.firstIndex(where: { $0.id == merged.id }) { cards[i] = merged }
            changed = true
        }

        if changed { persist() }
    }

    func addCard(bankName: String, tail: String, balanceCents: Int, alias: String = "") {
        cards.append(BankCard(bankName: Self.canonicalName(bankName), tail: tail, alias: alias,
                              balanceCents: max(0, balanceCents), confirmed: true))
        configured = true
        persist()
    }

    func setCardBalance(id: UUID, cents: Int) {
        guard let i = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[i].balanceCents = max(0, cents)
        cards[i].confirmed = true
        persist()
    }

    func updateCard(_ card: BankCard) {
        guard let i = cards.firstIndex(where: { $0.id == card.id }) else { return }
        cards[i] = card
        persist()
    }

    func removeCard(id: UUID) {
        cards.removeAll { $0.id == id }
        persist()
    }

    // MARK: - 记账扣减
    func charge(_ cents: Int, channel: PayChannel, tail: String = "", bankName: String = "") {
        guard let bucket = channel.balanceBucket else { return }
        switch bucket {
        case .wechat: wechat = max(0, wechat - cents)
        case .alipay: alipay = max(0, alipay - cents)
        case .bank:
            if let i = indexOfCard(tail: tail, bankName: bankName) {
                cards[i].balanceCents = max(0, cards[i].balanceCents - cents)
            }
        }
        persist()
    }

    func refund(_ cents: Int, channel: PayChannel, tail: String = "", bankName: String = "") {
        guard let bucket = channel.balanceBucket else { return }
        switch bucket {
        case .wechat: wechat += cents
        case .alipay: alipay += cents
        case .bank:
            if let i = indexOfCard(tail: tail, bankName: bankName) {
                cards[i].balanceCents += cents
            }
        }
        persist()
    }

    private func indexOfCard(tail: String, bankName: String = "") -> Int? {
        let indices = cards.indices.filter {
            (tail.isEmpty || cards[$0].tail == tail)
                && (bankName.isEmpty || Self.canonicalName(cards[$0].bankName) == Self.canonicalName(bankName))
        }
        return indices.count == 1 ? indices[0] : nil
    }

    private static func canonicalName(_ name: String) -> String {
        BillParser.bankNames.first { name.contains($0) } ?? name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 银行短信里带「余额」→ 以它为准校准对应那张卡
    func applyBankBalance(_ cents: Int, tail: String, bankName: String = "") {
        if let i = indexOfCard(tail: tail, bankName: bankName) {
            cards[i].balanceCents = max(0, cents)
            cards[i].confirmed = true
        } else {
            cards.append(BankCard(bankName: bankName.isEmpty ? "银行卡" : bankName, tail: tail,
                                  balanceCents: max(0, cents), confirmed: true))
        }
        configured = true
        persist()
    }

    // MARK: - 同步
    func exportBalances() -> [String: Int] {
        var d: [String: Int] = ["wechat": wechat, "alipay": alipay, "bank": bankTotal]
        for c in cards { d["card:\(c.tail)"] = c.balanceCents }
        return d
    }

    func importBalances(_ dict: [String: Int]) {
        if let v = dict["wechat"] { wechat = max(0, v) }
        if let v = dict["alipay"] { alipay = max(0, v) }
        configured = true
        persist()
    }
}
