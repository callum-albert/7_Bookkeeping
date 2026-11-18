import SwiftUI

struct BalanceAuditView: View {
    private var store: LedgerStore { LedgerStore.shared }
    private var _confirming = State(wrappedValue: false)
    private var confirming: Bool { get { _confirming.wrappedValue } nonmutating set { _confirming.wrappedValue = newValue } }

    var body: some View {
        List {
            Section("余额检查") {
                if store.balanceWarnings.isEmpty {
                    Label("当前余额与本机基准后的变动一致", systemImage: "checkmark.circle")
                }
                ForEach(store.balanceWarnings, id: \.self) { Text($0) }
                Text("首次升级以现有余额为基准，不推测历史期初余额。检查不能代替银行对账，也不能发现未收到通知的漏账。发现差异请先核对账单和真实余额，再手动修改余额。")
                    .font(.subheadline).foregroundStyle(.secondary)
                NavigationLink("修改账户余额") { BalanceManageView() }
                Button("已核对真实余额，设为新基准") { confirming = true }
            }
            Section("本人账户流转记录（不计收支）") {
                if store.transfers.isEmpty { Text("暂无转账记录").foregroundStyle(.secondary) }
                ForEach(store.transfers) { transfer in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(Accounts.shared.accountTitle(transfer.from)) → \(Accounts.shared.accountTitle(transfer.to))")
                        Text("\(transfer.amountCents.moneyText) · 手续费 \(transfer.feeCents.moneyText)")
                        Text(transfer.date.formatted()).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("余额与账单核对")
        .onAppear { store.checkBalances() }
        .confirmationDialog("确认所有账户余额已与真实余额核对？", isPresented: _confirming.projectedValue, titleVisibility: .visible) {
            Button("确认并建立新基准") { store.confirmBalanceBaseline() }
        } message: { Text("这不会补记遗漏账单，也不会修改账单金额。") }
    }
}

struct TransferView: View {
    @Environment(\.dismiss) private var dismiss
    private var _from = State(wrappedValue: "wechat")
    private var from: String { get { _from.wrappedValue } nonmutating set { _from.wrappedValue = newValue } }
    private var _to = State(wrappedValue: "alipay")
    private var to: String { get { _to.wrappedValue } nonmutating set { _to.wrappedValue = newValue } }
    private var _amount = State(wrappedValue: "")
    private var amount: String { get { _amount.wrappedValue } nonmutating set { _amount.wrappedValue = newValue } }
    private var _fee = State(wrappedValue: "")
    private var fee: String { get { _fee.wrappedValue } nonmutating set { _fee.wrappedValue = newValue } }
    private var _saved = State(wrappedValue: false)
    private var saved: Bool { get { _saved.wrappedValue } nonmutating set { _saved.wrappedValue = newValue } }
    private var accounts: Accounts { Accounts.shared }
    private func cents(_ text: String) -> Int {
        guard let value = Double(text), value.isFinite, value >= 0, value < 100_000_000 else { return 0 }
        return Int((value * 100).rounded())
    }
    private var validFee: Bool {
        if fee.isEmpty { return true }
        guard let value = Double(fee) else { return false }
        return value.isFinite && value >= 0 && value < 100_000_000
    }
    private func options() -> some View {
        Group {
            Text("微信余额").tag("wechat")
            Text("支付宝余额").tag("alipay")
            ForEach(accounts.cards) { Text($0.displayName).tag($0.id.uuidString) }
        }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("本人账户之间流转") {
                    Picker("转出账户", selection: _from.projectedValue) { options() }
                    Picker("转入账户", selection: _to.projectedValue) { options() }
                    TextField("到账金额（元）", text: _amount.projectedValue).keyboardType(.decimalPad)
                    TextField("手续费（元，无则留空）", text: _fee.projectedValue).keyboardType(.decimalPad)
                    Text("转出方扣除到账金额和手续费，转入方增加到账金额。不计入收入或消费；手续费在流转记录中单独留存。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Button("确认转账并更新余额") {
                    guard !saved, validFee else { return }
                    saved = LedgerStore.shared.transfer(from: from, to: to, cents: cents(amount), fee: cents(fee))
                    if saved { dismiss() }
                }
                .disabled(saved || from == to || cents(amount) <= 0 || !validFee)
            }
            .navigationTitle("本人账户转账")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
}
