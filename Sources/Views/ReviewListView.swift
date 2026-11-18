import SwiftUI

/// 独立观察账本，首页提醒和弹层始终使用同一个实时查询。
struct ReviewListView: View {
    @Environment(\.dismiss) private var dismiss
    private var store: LedgerStore { LedgerStore.shared }

    var body: some View {
        NavigationStack {
            List {
                if store.pendingReview.isEmpty {
                    ContentUnavailableView("没有待确认的账目", systemImage: "checkmark.circle",
                                           description: Text("账目已核对，首页提醒会同步清除。"))
                } else {
                    Section {
                        ForEach(store.pendingReview) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                EntryRow(entry: entry)
                                Text(entry.reviewExplanation)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 8)
                            }
                        }
                    } footer: {
                        Text("待确认不代表未入账。核对后请点「确认这笔」；修改分类或商户不会自动替你确认。")
                    }
                }
            }
            .navigationTitle("待确认的账目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } }
        }
        .presentationDetents([.large])
    }
}

extension Entry {
    var reviewExplanation: String {
        var reasons: [String] = []
        if merchant.isEmpty || merchant == source.title { reasons.append("商户信息不完整") }
        if category == .other || category == .otherIncome { reasons.append("分类未确定") }
        if channel == .unknown { reasons.append("收支账户未识别") }
        if !hasPaidTime { reasons.append("未识别到支付时间，暂用记账时间") }
        if reasons.isEmpty { reasons.append("识别结果可能存在歧义，请对照原账单核对") }
        return reasons.joined(separator: "；")
    }
}
