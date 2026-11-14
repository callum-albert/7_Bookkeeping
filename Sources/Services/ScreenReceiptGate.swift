import Foundation

/// 自动识屏只接受稳定的成功付款页。与 UI/采集 API 分离，使用相同解析器回归。
struct ScreenReceiptGate {
    private var pending: String?
    private var firstSeen: Date?
    private var processed = Set<String>()

    mutating func accept(_ text: String, now: Date = Date()) -> Bool {
        let parsed = BillParser.parse(text, now: now)
        guard parsed.count == 1, let bill = parsed.first, bill.flow == .expense,
              bill.source == .wechat || bill.source == .alipay,
              ["支付成功", "付款成功", "支付完成"].contains(where: { text.contains($0) }) else {
            pending = nil; firstSeen = nil
            return false
        }
        let time = bill.hasPaidTime ? String(Int(bill.date.timeIntervalSince1970)) : "current"
        let fields = [bill.source.rawValue, String(bill.amountCents), bill.merchant, bill.account, time].joined(separator: "|")
        let identity = bill.transactionID.isEmpty ? fields : bill.source.rawValue + "|" + bill.transactionID
        let key = identity + "|" + fields
        guard !processed.contains(identity) else {
            pending = nil; firstSeen = nil
            return false
        }
        if pending != key {
            pending = key; firstSeen = now
            return false
        }
        guard let firstSeen, now.timeIntervalSince(firstSeen) >= 1 else { return false }
        processed.insert(identity)
        // 会话内限量保存标识，不保存普通画面的图片或文字。
        if processed.count > 1000 { processed = [identity] }
        return true
    }
}
