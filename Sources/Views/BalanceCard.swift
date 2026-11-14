import SwiftUI

/// 三大余额：微信 / 支付宝 / 银行卡（信贷不计入）
struct BalanceCard: View {
    private var _accounts = State(wrappedValue: Accounts.shared)
    private var accounts: Accounts { _accounts.wrappedValue }
    private var _editing = State(wrappedValue: false)
    private var editing: Bool { get { _editing.wrappedValue } nonmutating set { _editing.wrappedValue = newValue } }

    var body: some View {
        Button {
            editing = true
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("余额")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if accounts.configured {
                        Text("合计 \(accounts.total.moneyText)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                }

                if accounts.configured {
                    HStack(spacing: 8) {
                        ForEach(BalanceBucket.allCases) { bucket in
                            bucketCell(bucket)
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.dashed")
                            .font(.system(size: 16))
                            .foregroundStyle(.tertiary)
                        Text("设置微信 / 支付宝 / 银行卡余额")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
            }
            .padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: _editing.projectedValue) {
            NavigationStack {
                BalanceManageView()
            }
            .presentationDetents([.large])
            .presentationBackground(.thinMaterial)
        }
    }

    private func bucketCell(_ bucket: BalanceBucket) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: bucket.symbol)
                    .font(.system(size: 9))
                    .foregroundStyle(bucket.tint)
                Text(bucket == .bank && !accounts.cards.isEmpty
                     ? "\(bucket.shortTitle)·\(accounts.cards.count)张"
                     : bucket.shortTitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(accounts.balance(bucket).amountOnly)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .background(bucket.tint.opacity(0.09), in: .rect(cornerRadius: 14))
    }
}
