import SwiftUI

struct ComposeView: View {
    private var _dismiss = Environment(\.dismiss)
    private var dismiss: DismissAction { _dismiss.wrappedValue }
    private var _bookkeeper = State(wrappedValue: AutoBookkeeper.shared)
    private var bookkeeper: AutoBookkeeper { get { _bookkeeper.wrappedValue } nonmutating set { _bookkeeper.wrappedValue = newValue } }

    private var _kind = State(wrappedValue: EntryKind.expense)
    private var kind: EntryKind { get { _kind.wrappedValue } nonmutating set { _kind.wrappedValue = newValue } }
    private var _accountID = State(wrappedValue: "")
    private var accountID: String { get { _accountID.wrappedValue } nonmutating set { _accountID.wrappedValue = newValue } }
    private var _showCategories = State(wrappedValue: false)
    private var showCategories: Bool { get { _showCategories.wrappedValue } nonmutating set { _showCategories.wrappedValue = newValue } }
    private var _amountText = State(wrappedValue: "")
    private var amountText: String { get { _amountText.wrappedValue } nonmutating set { _amountText.wrappedValue = newValue } }
    private var _category = State(wrappedValue: Category.food)
    private var category: Category { get { _category.wrappedValue } nonmutating set { _category.wrappedValue = newValue } }
    private var _merchant = State(wrappedValue: "")
    private var merchant: String { get { _merchant.wrappedValue } nonmutating set { _merchant.wrappedValue = newValue } }
    private var _note = State(wrappedValue: "")
    private var note: String { get { _note.wrappedValue } nonmutating set { _note.wrappedValue = newValue } }
    private var _date = State(wrappedValue: Date())
    private var date: Date { get { _date.wrappedValue } nonmutating set { _date.wrappedValue = newValue } }
    private var _showDatePicker = State(wrappedValue: false)
    private var showDatePicker: Bool { get { _showDatePicker.wrappedValue } nonmutating set { _showDatePicker.wrappedValue = newValue } }
    private var _amountFocused = FocusState<Bool>()
    private var amountFocused: Bool { get { _amountFocused.wrappedValue } nonmutating set { _amountFocused.wrappedValue = newValue } }

    private var amountCents: Int {
        let cleaned = amountText.replacingOccurrences(of: ",", with: "")
        guard let d = Double(cleaned), d.isFinite, d > 0, d < 100_000_000 else { return 0 }
        return Int((d * 100).rounded())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Picker("收支类型", selection: _kind.projectedValue) {
                        ForEach(EntryKind.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                    amountSection
                    categorySection
                    detailSection
                    Color.clear.frame(height: 80)
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationTitle("记一笔")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(amountCents <= 0)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { amountFocused = false }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button { save() } label: {
                    HStack(spacing: 8) {
                        if amountCents > 0 {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        Text("保存这一笔")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .glassEffect(.regular.tint(Theme.brand.opacity(0.82)).interactive(),
                                 in: .rect(cornerRadius: 22))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(
                                LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.08)],
                                               startPoint: .top, endPoint: .bottom),
                                lineWidth: 0.9
                            )
                    }
                    .shadow(color: Theme.brand.opacity(0.35), radius: 16, y: 8)
                }
                .buttonStyle(.plain)
                .opacity(amountCents > 0 ? 1 : 0.62)
                .animation(.easeOut(duration: 0.2), value: amountCents > 0)
                .disabled(amountCents <= 0)
                .padding(.horizontal, 18)
                .padding(.bottom, 10)
            }
        }
        .onAppear { amountFocused = true }
        .onChange(of: kind) { _, value in category = value == .income ? .otherIncome : .food }
        .onChange(of: CategoryStore.shared.categories) { _, categories in
            if category.isCustom && !categories.contains(category) { category = kind == .income ? .otherIncome : .food }
        }
        .sheet(isPresented: _showCategories.projectedValue) { CategoryManageView(initialKind: kind) }

    }

    // MARK: - 金额
    private var amountSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 2) {
                Text("¥")
                    .font(.system(size: 26, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                TextField("0", text: _amountText.projectedValue)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .keyboardType(.decimalPad)
                    .focused(_amountFocused.projectedValue)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 120)
                    .monospacedDigit()
            }
            Text(date.formatted(.dateTime.month().day().hour().minute()))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .glassEffect(.regular.tint(Theme.brand.opacity(0.14)), in: .rect(cornerRadius: 28))
    }

    // MARK: - 分类
    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("分类").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Button("自定义分类") { showCategories = true }.font(.system(size: 12))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
                ForEach(Category.choices(for: kind)) { c in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { category = c }
                    } label: {
                        VStack(spacing: 6) {
                            CategoryBadge(category: c, size: 42)
                                .overlay {
                                    if category == c {
                                        Circle().stroke(Theme.brand, lineWidth: 2)
                                            .frame(width: 48, height: 48)
                                    }
                                }
                                .scaleEffect(category == c ? 1.06 : 1)
                            Text(c.title)
                                .font(.system(size: 10, weight: category == c ? .bold : .medium))
                                .foregroundStyle(category == c ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    // MARK: - 明细
    private var detailSection: some View {
        VStack(spacing: 0) {
            Picker("收支账户", selection: _accountID.projectedValue) {
                Text("不指定账户").tag("")
                Text("微信零钱").tag("wechat")
                Text("支付宝余额").tag("alipay")
                ForEach(Accounts.shared.cards) { Text($0.displayName).tag($0.id.uuidString) }
            }.padding(16)
            Text("不指定账户时只记收支，不调整余额").font(.system(size: 10)).foregroundStyle(.secondary).padding(.bottom, 8)
            Divider().opacity(0.4)
            HStack(spacing: 12) {
                Image(systemName: "storefront.fill")
                    .font(.system(size: 13)).foregroundStyle(Theme.brand).frame(width: 22)
                TextField("商户 / 概要", text: _merchant.projectedValue)
                    .font(.system(size: 14))
            }
            .padding(.horizontal, 16).padding(.vertical, 14)

            Divider().padding(.leading, 16).opacity(0.4)

            HStack(spacing: 12) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 13)).foregroundStyle(Theme.mint).frame(width: 22)
                TextField("备注", text: _note.projectedValue)
                    .font(.system(size: 14))
            }
            .padding(.horizontal, 16).padding(.vertical, 14)

            Divider().padding(.leading, 16).opacity(0.4)

            Button {
                showDatePicker.toggle()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .font(.system(size: 13)).foregroundStyle(Theme.warm).frame(width: 22)
                    Text("时间").font(.system(size: 14)).foregroundStyle(.primary)
                    Spacer()
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            if showDatePicker {
                DatePicker("", selection: _date.projectedValue)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private func save() {
        guard amountCents > 0 else { return }
        let card = Accounts.shared.cards.first { $0.id.uuidString == accountID }
        let channel: PayChannel = accountID == "wechat" ? .wechatZero : (accountID == "alipay" ? .alipayBalance : (card == nil ? .unknown : .bank))
        let account = card.map { "\($0.bankName)(\($0.tail))" } ?? (accountID == "wechat" ? "零钱" : (accountID == "alipay" ? "余额" : ""))
        bookkeeper.addManual(amountCents: amountCents, category: category,
                             merchant: merchant, note: note, date: date, kind: kind, channel: channel, account: account)
        dismiss()
    }
}
