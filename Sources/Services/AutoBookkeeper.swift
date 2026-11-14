import Foundation
import SwiftUI
import UIKit
import Observation

/// 自动记账调度中心：所有入口（剪贴板 / OCR / 快捷指令 / URL Scheme）都走这里
@MainActor
@Observable
final class AutoBookkeeper {
    static let shared = AutoBookkeeper()

    var toast: Toast?

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        var title: String
        var subtitle: String
        var kind: Kind

        enum Kind { case success, merged, ignored, failed }
    }


    // MARK: - 核心入口
    @discardableResult
    func ingest(_ text: String, source: String = "自动",
                trigger: LedgerStore.Trigger = .automatic, forceReview: Bool = false) -> [Entry] {
        let parsed = BillParser.parse(text)
        guard !parsed.isEmpty else {
            showToast("没识别到账单", "文本里需要包含微信支付/支付宝/银行卡与金额", .failed)
            return []
        }

        let store = LedgerStore.shared
        var inserted: [Entry] = []
        var merged: [Entry] = []
        var duplicates = 0
        var ignoredReason: String?
        var ignoredCount = 0

        for var p in parsed {
            if forceReview { p.needsReview = true }
            switch store.ingest(p, trigger: trigger) {
            case .inserted(let e): inserted.append(e)
            case .merged(let e): merged.append(e)
            case .duplicate: duplicates += 1
            case .ignored(let reason):
                ignoredReason = reason
                ignoredCount += 1
            }
        }

        // 结果反馈：优先展示新账，其次合并，其次忽略
        if !inserted.isEmpty || !merged.isEmpty {
            let all = inserted + merged
            let total = all.reduce(0) { $0 + $1.amountCents }
            let first = all[0]
            let review = all.contains { $0.needsReview }

            if !merged.isEmpty && inserted.isEmpty {
                showToast("已合并同一笔 \(total.moneyText)",
                          "\(first.merchant) · 多渠道消息已去重", .merged)
            } else if all.count > 1 {
                showToast("已记录 \(all.count) 笔", "收入 \(all.filter { $0.kind == .income }.count) 笔 · 支出 \(all.filter { $0.kind == .expense }.count) 笔", .success)
            } else if review {
                showToast("已记账 \(first.amountText)", "\(first.merchant) · 请核对识别结果", .merged)
            } else {
                showToast("已自动记账 \(first.amountText)",
                          "\(first.merchant) · \(first.category.title)", .success)
            }

            let balance = LiveActivityController.balanceInfo(for: first)
            let islandOK = LiveActivityController.shared.start(for: first,
                                                              todayTotal: todayTotal(),
                                                              auto: true)
            // 灵动岛成功就够；失败或后台才用通知兜底，避免三处重复提示
            if !islandOK, UIApplication.shared.applicationState != .active {
                NotificationService.shared.notify(entry: first,
                                                 balanceLabel: balance.label,
                                                 balanceText: balance.text)
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return all
        }

        if let reason = ignoredReason {
            showToast("已忽略这笔", "\(reason)不计入消费\(ignoredCount > 1 ? "（\(ignoredCount) 笔）" : "")", .ignored)
            return []
        }

        if duplicates > 0 {
            showToast("这笔已经记过啦", "已自动去重，不会多记", .merged)
        }
        return []
    }

    private(set) var lastOCRText: String = ""

    func ingestImage(_ image: UIImage, source: String) async -> [Entry] {
        let receipt = await OCRService.recognizeReceipt(image)
        let text = receipt.text
        lastOCRText = text
        IntentLog.record("OCR：\(text.count)字，\(receipt.needsReview ? "待核对" : "字段完整")")
        guard !text.isEmpty else {
            showToast("图片里没找到文字", "试试更清晰的账单截图", .failed)
            return []
        }
        // 截图属于人工触发 → 用更宽的合并窗口 + 强去重
        return ingest(text, source: source, trigger: .manual, forceReview: receipt.needsReview)
    }

    // MARK: - 剪贴板
    func ingestClipboardNow() {
        let pb = UIPasteboard.general
        guard let s = pb.string, !s.isEmpty else {
            showToast("剪贴板是空的", "先复制微信/支付宝/银行的账单通知", .failed)
            return
        }
        _ = ingest(s, source: "剪贴板", trigger: .manual)
    }

    // MARK: - 手动
    func addManual(amountCents: Int, category: Category, merchant: String, note: String, date: Date,
                   kind: EntryKind = .expense, channel: PayChannel = .unknown, account: String = "") {
        let store = LedgerStore.shared
        let parsed = BillParser.Parsed(amountCents: amountCents, source: .manual, category: category,
            merchant: merchant.isEmpty ? category.title : merchant, account: account, date: date,
            raw: "手动录入", flow: kind == .income ? .income : .expense, needsReview: false,
            channel: channel, balanceAfter: nil, hasPaidTime: true)
        let outcome = store.ingest(parsed, trigger: .manual)
        var entry: Entry
        switch outcome {
        case .inserted(let e), .merged(let e): entry = e
        case .duplicate:
            showToast("这笔已经记过啦", "已自动去重，不会重复更新余额", .merged)
            return
        case .ignored: return
        }
        entry.auto = false; entry.note = note
        store.update(entry)
        showToast("已记录\(kind.title) \(entry.amountText)", entry.category.title, .success)
        let balance = LiveActivityController.balanceInfo(for: entry)
        let islandOK = LiveActivityController.shared.start(for: entry, todayTotal: todayTotal(), auto: false)
        if !islandOK, UIApplication.shared.applicationState != .active {
            NotificationService.shared.notify(entry: entry, balanceLabel: balance.label, balanceText: balance.text)
        }
    }

    func todayTotal() -> Int {
        LedgerStore.shared.summary(in: Period.day.range()).total
    }

    private func showToast(_ title: String, _ subtitle: String, _ kind: Toast.Kind) {
        toast = Toast(title: title, subtitle: subtitle, kind: kind)
        Task {
            try? await Task.sleep(for: .seconds(2.8))
            if toast?.subtitle == subtitle { toast = nil }
        }
    }
}
