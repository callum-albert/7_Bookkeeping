import SwiftUI

/// 余额管理：微信 / 支付宝 / 多张银行卡
struct BalanceManageView: View {
    private var _accounts = State(wrappedValue: Accounts.shared)
    private var accounts: Accounts { _accounts.wrappedValue }
    @Environment(\.dismiss) private var dismiss

    private var _wechat = State(wrappedValue: "")
    private var wechat: String { get { _wechat.wrappedValue } nonmutating set { _wechat.wrappedValue = newValue } }
    private var _alipay = State(wrappedValue: "")
    private var alipay: String { get { _alipay.wrappedValue } nonmutating set { _alipay.wrappedValue = newValue } }

    private var _adding = State(wrappedValue: false)
    private var adding: Bool { get { _adding.wrappedValue } nonmutating set { _adding.wrappedValue = newValue } }
    private var _newBank = State(wrappedValue: "")
    private var newBank: String { get { _newBank.wrappedValue } nonmutating set { _newBank.wrappedValue = newValue } }
    private var _newTail = State(wrappedValue: "")
    private var newTail: String { get { _newTail.wrappedValue } nonmutating set { _newTail.wrappedValue = newValue } }
    private var _newBalance = State(wrappedValue: "")
    private var newBalance: String { get { _newBalance.wrappedValue } nonmutating set { _newBalance.wrappedValue = newValue } }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                totalCard
                walletSection
                cardSection
                hint
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle("余额")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            wechat = accounts.wechat == 0 ? "" : plain(accounts.wechat)
            alipay = accounts.alipay == 0 ? "" : plain(accounts.alipay)
        }
        .onDisappear {
            accounts.setAll(wechat: cents(wechat), alipay: cents(alipay), bank: accounts.bankTotal)
        }
    }

    // MARK: - 合计
    private var totalCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("总计").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            MoneyText(cents: accounts.total, size: 38, weight: .bold)
                .foregroundStyle(LinearGradient(colors: [Theme.brand, Theme.brandSoft],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
            Text("微信 + 支付宝 + \(accounts.cards.count) 张银行卡 · 信贷不计入")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassEffect(.regular.tint(Theme.brand.opacity(0.14)), in: .rect(cornerRadius: 24))
    }

    // MARK: - 钱包
    private var walletSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("零钱与余额")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            moneyRow("微信余额", symbol: "message.fill", tint: Theme.mint, text: _wechat.projectedValue)
            Divider().opacity(0.3)
            moneyRow("支付宝余额", symbol: "a.circle.fill",
                     tint: Color(red: 0.10, green: 0.47, blue: 0.96), text: _alipay.projectedValue)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private func moneyRow(_ title: String, symbol: String, tint: Color, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.14), in: .rect(cornerRadius: 8))
            Text(title).font(.system(size: 14))
            Spacer()
            TextField("0.00", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .frame(width: 120)
        }
    }

    // MARK: - 银行卡
    private var cardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("银行卡")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("合计 \(accounts.bankTotal.moneyText)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if accounts.cards.isEmpty {
                Text("还没有银行卡。记账时识别到尾号会自动添加，也可以在这里手动加。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 10) {
                    ForEach(accounts.cards) { card in
                        cardRow(card)
                    }
                }
            }

            if adding {
                addCardForm
            } else {
                Button {
                    withAnimation { adding = true }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("添加银行卡")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .glassEffect(.regular.tint(Theme.brand.opacity(0.14)).interactive(), in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private func cardRow(_ card: BankCard) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "creditcard.fill")
                .font(.system(size: 12))
                .foregroundStyle(BalanceBucket.bank.tint)
                .frame(width: 26, height: 26)
                .background(BalanceBucket.bank.tint.opacity(0.12), in: .rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 1) {
                Text(card.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if !card.confirmed {
                    Text("余额待设置")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.warm)
                }
            }

            Spacer()

            TextField("0.00", text: cardBinding(card))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .frame(width: 110)

            Button {
                withAnimation { accounts.removeCard(id: card.id) }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.danger.opacity(0.75))
            }
            .buttonStyle(.plain)
        }
    }

    private var addCardForm: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("银行（招商银行）", text: _newBank.projectedValue)
                    .font(.system(size: 12))
                    .padding(9)
                    .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 10))
                TextField("尾号", text: _newTail.projectedValue)
                    .keyboardType(.numberPad)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(9)
                    .frame(width: 76)
                    .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 10))
            }
            TextField("余额", text: _newBalance.projectedValue)
                .keyboardType(.decimalPad)
                .font(.system(size: 12))
                .padding(9)
                .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 10))

            HStack(spacing: 8) {
                Button("取消") {
                    withAnimation { adding = false }
                    newBank = ""; newTail = ""; newBalance = ""
                }
                .font(.system(size: 12))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))

                Button("添加") {
                    accounts.addCard(bankName: newBank, tail: newTail,
                                     balanceCents: cents(newBalance))
                    withAnimation { adding = false }
                    newBank = ""; newTail = ""; newBalance = ""
                }
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .glassEffect(.regular.tint(Theme.brand.opacity(0.25)).interactive(), in: .rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.primary.opacity(0.03), in: .rect(cornerRadius: 14))
    }

    private var hint: some View {
        Text("记账时会按支付渠道自动扣减对应余额：零钱扣微信、余额宝扣支付宝、刷卡扣对应卡号。花呗和信用卡属于信贷，不占余额。")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 工具
    private func cardBinding(_ card: BankCard) -> Binding<String> {
        Binding(
            get: {
                guard let c = accounts.cards.first(where: { $0.id == card.id }) else { return "" }
                return c.balanceCents == 0 ? "" : plain(c.balanceCents)
            },
            set: { accounts.setCardBalance(id: card.id, cents: cents($0)) }
        )
    }

    private func cents(_ s: String) -> Int {
        Int(((Double(s.replacingOccurrences(of: ",", with: "")) ?? 0) * 100).rounded())
    }

    private func plain(_ c: Int) -> String {
        c % 100 == 0 ? "\(c / 100)" : String(format: "%.2f", Double(c) / 100)
    }
}
