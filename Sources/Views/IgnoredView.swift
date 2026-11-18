import SwiftUI

/// 被判定为「转账 / 收款 / 退款」而忽略的事件
/// 目的：让用户能复核，防止误判导致漏记
struct IgnoredListView: View {
    private var _store = State(wrappedValue: LedgerStore.shared)
    private var store: LedgerStore { _store.wrappedValue }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                NavigationLink("本人账户互转：指定两端并调整余额") { TransferView() }
                    .font(.subheadline)
                Text("完成转账后请忽略对应待核对事件，避免再次处理。不要把本人互转重新识别为消费。")
                    .font(.subheadline).foregroundStyle(.secondary)

                if store.ignored.isEmpty {
                    empty
                } else {
                    ForEach(store.ignored) { ev in
                        row(ev)
                    }
                }
                Color.clear.frame(height: 60)
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("已忽略的资金流动")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("这些资金流动暂未计入收支")
                .font(.system(size: 13, weight: .semibold))
            Text("本人账户互转等不计收支。旧版本被忽略的收款和退款，可点击「重新识别入账」记录为收入；确认需要计账的其他事件也可补记。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular.tint(Theme.warm.opacity(0.14)), in: .rect(cornerRadius: 22))
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.mint)
            Text("还没有被忽略的事件")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private func row(_ ev: LedgerStore.IgnoredEvent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: ev.source.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ev.source.tint)
                    .frame(width: 26, height: 26)
                    .background(ev.source.tint.opacity(0.14), in: .circle)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(ev.reason)
                            .font(.system(size: 13, weight: .semibold))
                        if let cents = ev.amountCents {
                            Text(cents.moneyText)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                        }
                    }
                    Text(ev.text)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    Text(ev.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }

            if ev.amountCents != nil {
                HStack(spacing: 8) {
                    Button {
                        withAnimation { store.restoreIgnored(ev) }
                    } label: {
                        Label("重新识别入账", systemImage: "plus.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .glassEffect(.regular.tint(Theme.mint.opacity(0.2)).interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation { store.dismissIgnored(ev) }
                    } label: {
                        Text("忽略")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}
