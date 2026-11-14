import SwiftUI
import PhotosUI

struct HomeView: View {
    private var _showCompose: Binding<Bool>
    private var showCompose: Bool { get { _showCompose.wrappedValue } nonmutating set { _showCompose.wrappedValue = newValue } }

    private var _store = State(wrappedValue: LedgerStore.shared)
    private var store: LedgerStore { get { _store.wrappedValue } nonmutating set { _store.wrappedValue = newValue } }
    private var _bookkeeper = State(wrappedValue: AutoBookkeeper.shared)
    private var bookkeeper: AutoBookkeeper { get { _bookkeeper.wrappedValue } nonmutating set { _bookkeeper.wrappedValue = newValue } }
    private var _photoItem = State<PhotosPickerItem?>(wrappedValue: nil)
    private var photoItem: PhotosPickerItem? { get { _photoItem.wrappedValue } nonmutating set { _photoItem.wrappedValue = newValue } }
    private var _showPasteSheet = State(wrappedValue: false)
    private var _showReviewSheet = State(wrappedValue: false)
    private var _selectedReview = State<Entry?>(wrappedValue: nil)
    private var selectedReview: Entry? { get { _selectedReview.wrappedValue } nonmutating set { _selectedReview.wrappedValue = newValue } }
    private var showReviewSheet: Bool { get { _showReviewSheet.wrappedValue } nonmutating set { _showReviewSheet.wrappedValue = newValue } }
    private var showPasteSheet: Bool { get { _showPasteSheet.wrappedValue } nonmutating set { _showPasteSheet.wrappedValue = newValue } }
    private var _pasteText = State(wrappedValue: "")
    private var pasteText: String { get { _pasteText.wrappedValue } nonmutating set { _pasteText.wrappedValue = newValue } }
    private var _isParsing = State(wrappedValue: false)
    private var isParsing: Bool { get { _isParsing.wrappedValue } nonmutating set { _isParsing.wrappedValue = newValue } }
    private var _appeared = State(wrappedValue: false)
    private var appeared: Bool { get { _appeared.wrappedValue } nonmutating set { _appeared.wrappedValue = newValue } }

    init(showCompose: Binding<Bool>) {
        _showCompose = showCompose
    }

    private var pendingReview: [Entry] {
        store.entries.filter { $0.needsReview }.sorted { $0.date > $1.date }
    }

    private var reviewBanner: some View {
        Button {
            showReviewSheet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.warm)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(pendingReview.count) 笔待确认")
                        .font(.system(size: 13, weight: .semibold))
                    Text("只有银行短信，没有商户信息，点这里补全分类")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .glassEffect(.regular.tint(Theme.warm.opacity(0.16)).interactive(), in: .rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private var today: DateInterval { Period.day.range() }
    private var yesterday: DateInterval { Period.day.previous() }

    private var todayTotal: Int { store.summary(in: today).total }
    private var yesterdayTotal: Int { store.summary(in: yesterday).total }
    private var todayCount: Int { store.summary(in: today).count }

    /// 与昨日同期对比
    private var deltaRatio: Double? {
        guard yesterdayTotal > 0 else { return todayTotal > 0 ? nil : nil }
        return Double(todayTotal - yesterdayTotal) / Double(yesterdayTotal)
    }

    private var groupedEntries: [(Date, [Entry])] {
        let cal = Calendar.current
        let sorted = store.entries.sorted { $0.date > $1.date }
        var buckets: [Date: [Entry]] = [:]
        for e in sorted { buckets[cal.startOfDay(for: e.date), default: []].append(e) }
        return buckets.sorted { $0.key > $1.key }.map { ($0.key, $0.value) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    heroCard
                    BalanceCard()
                    if !pendingReview.isEmpty { reviewBanner }
                    quickActions
                    listSection
                    Color.clear.frame(height: 90)
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
            }
            .scrollIndicators(.hidden)
            .background(alignment: .top) { EmptyView() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { appeared = true }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                isParsing = true
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    _ = await bookkeeper.ingestImage(img, source: "截图识别")
                }
                isParsing = false
                photoItem = nil
            }
        }
        .sheet(isPresented: _showPasteSheet.projectedValue) { pasteSheet }
        .sheet(isPresented: _showReviewSheet.projectedValue) { reviewSheet }
    }

    // MARK: - 头部
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("7记账")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Image(systemName: "sparkle")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.brandSoft)
                }
                Text(Date().formatted(.dateTime.month().day().weekday(.wide)))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isParsing {
                ProgressView().controlSize(.small)
            }
            NavigationLink {
                SettingsView()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 今日主卡
    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("今日支出")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                TagView(text: "\(todayCount) 笔", symbol: "list.bullet", tint: Theme.brand)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("¥")
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                MoneyText(cents: todayTotal, size: 46, weight: .bold, showSymbol: false)
                    .foregroundStyle(
                        LinearGradient(colors: [Theme.brand, Theme.brandSoft],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                Spacer()
                if let d = deltaRatio {
                    HStack(spacing: 3) {
                        Image(systemName: d >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                        Text(String(format: "%.0f%%", abs(d) * 100))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(d >= 0 ? Theme.danger : Theme.mint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background((d >= 0 ? Theme.danger : Theme.mint).opacity(0.13), in: .capsule)
                }
            }

            Divider().opacity(0.5)

            HStack(spacing: 0) {
                miniStat(title: "本周", value: store.summary(in: Period.week.range()).total)
                Rectangle().fill(.secondary.opacity(0.16)).frame(width: 1, height: 30)
                miniStat(title: "本月", value: store.summary(in: Period.month.range()).total)
            }
        }
        .padding(20)
        .glassEffect(.regular.tint(Theme.brand.opacity(0.16)), in: .rect(cornerRadius: 30))
        .shadow(color: Theme.brand.opacity(0.14), radius: 22, y: 12)
        .scaleEffect(appeared ? 1 : 0.96)
        .opacity(appeared ? 1 : 0)
    }

    private func miniStat(title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value.moneyText)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, title == "本周" ? 2 : 16)
    }

    // MARK: - 快动作
    private var quickActions: some View {
        HStack(spacing: 10) {
            actionButton(title: "记一笔", symbol: "plus", tint: Theme.brand) {
                showCompose = true
            }
            actionButton(title: "粘贴识别", symbol: "doc.on.clipboard", tint: Theme.mint) {
                pasteText = ""
                showPasteSheet = true
            }
            PhotosPicker(selection: _photoItem.projectedValue, matching: .images) {
                VStack(spacing: 6) {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.warm)
                    Text("截图识别")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
            }
            .buttonStyle(.plain)
        }
    }

    private func actionButton(title: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 账目列表
    private var listSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("最近账目")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if !store.entries.isEmpty {
                    Text("共 \(store.entries.count) 笔")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)

            if store.entries.isEmpty {
                emptyState
            } else {
                ForEach(groupedEntries, id: \.0) { day, items in
                    daySection(day: day, items: items)
                }
            }
        }
    }

    private func daySection(day: Date, items: [Entry]) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(dayLabel(day))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(items.reduce(0) { $0 + $1.amountCents }.moneyText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, entry in
                    EntryRow(entry: entry)
                    if idx < items.count - 1 {
                        Divider().padding(.leading, 62).opacity(0.4)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .contextMenu {
            Button(role: .destructive) {
                items.forEach { store.delete($0) }
            } label: { Label("删除当天全部", systemImage: "trash") }
        }
    }

    private func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "今天" }
        if cal.isDateInYesterday(date) { return "昨天" }
        return date.formatted(.dateTime.month().day().weekday(.abbreviated))
    }

    // MARK: - 空态
    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.brandSoft)
            Text("还没有账目")
                .font(.system(size: 15, weight: .semibold))
            Text("付款后复制通知文本，或直接截图\n7记账 会自动识别金额和分类")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            Button {
                bookkeeper.ingestClipboardNow()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars")
                    Text("试试读剪贴板")
                }
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .glassEffect(.regular.tint(Theme.brand.opacity(0.22)).interactive(), in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    // MARK: - 待确认复核
    private var reviewSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(pendingReview) { entry in
                        Button {
                            selectedReview = entry
                        } label: {
                            EntryRow(entry: entry)
                                .glassEffect(.regular, in: .rect(cornerRadius: 20))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(18)
            }
            .background(AppBackground())
            .navigationTitle("待确认的账目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { showReviewSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(item: Binding(get: { selectedReview }, set: { selectedReview = $0 })) { e in
            EntryDetailView(entry: e)
                .presentationDetents([.medium, .large])
                .presentationBackground(.thinMaterial)
        }
    }

    // MARK: - 粘贴识别
    private var pasteSheet: some View {
        NavigationStack {
            VStack(spacing: 14) {
                TextEditor(text: _pasteText.projectedValue)
                    .font(.system(size: 14, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .frame(minHeight: 200)
                    .glassEffect(.regular, in: .rect(cornerRadius: 20))
                    .overlay(alignment: .topLeading) {
                        if pasteText.isEmpty {
                            Text("粘贴微信支付 / 支付宝的通知或账单文本…")
                                .font(.system(size: 14))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 17)
                                .padding(.vertical, 20)
                                .allowsHitTesting(false)
                        }
                    }

                HStack(spacing: 10) {
                    Button {
                        pasteText = UIPasteboard.general.string ?? ""
                    } label: {
                        Label("读取剪贴板", systemImage: "doc.on.clipboard")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)

                    Button {
                        showPasteSheet = false
                        _ = bookkeeper.ingest(pasteText, source: "手动粘贴", trigger: .manual)
                    } label: {
                        Text("识别记账")
                            .prominentGlassButton(tint: Theme.mint)
                    }
                    .buttonStyle(.plain)
                    .disabled(pasteText.isEmpty)
                    .opacity(pasteText.isEmpty ? 0.5 : 1)
                }
                Spacer()
            }
            .padding(18)
            .background(AppBackground())
            .navigationTitle("粘贴识别")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { showPasteSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.thinMaterial)
    }
}

// MARK: - 账目行
struct EntryRow: View {
    var entry: Entry
    private var _showDetail = State(wrappedValue: false)
    private var showDetail: Bool { get { _showDetail.wrappedValue } nonmutating set { _showDetail.wrappedValue = newValue } }
    private var _store = State(wrappedValue: LedgerStore.shared)
    private var store: LedgerStore { get { _store.wrappedValue } nonmutating set { _store.wrappedValue = newValue } }

    var body: some View {
        Button {
            showDetail = true
        } label: {
            HStack(spacing: 12) {
                CategoryBadge(category: entry.category, size: 38)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(entry.merchant)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if entry.needsReview {
                            Text("待确认")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Theme.warm)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Theme.warm.opacity(0.16), in: .capsule)
                        }
                        if entry.channel.isCredit {
                            Text(entry.channel == .huabei ? "花呗" : "信用卡")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color(red: 0.62, green: 0.42, blue: 0.96))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color(red: 0.62, green: 0.42, blue: 0.96).opacity(0.16), in: .capsule)
                        }
                    }
                    HStack(spacing: 6) {
                        Text(entry.category.title)
                        Text("·")
                        Text(entry.source.title)
                        if !entry.account.isEmpty {
                            Text("·")
                            Text(entry.account).lineLimit(1)
                        }
                        Text("·")
                        Text(entry.date.formatted(date: .omitted, time: .shortened)
                             + (entry.hasPaidTime ? "" : " 记"))
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(entry.amountText)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                    if entry.auto {
                        Text(entry.needsReview ? "待确认" : (entry.mergedSources.isEmpty ? "自动" : "已合并"))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(entry.needsReview ? Theme.warm : Theme.mint)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                withAnimation { store.delete(entry) }
            } label: { Label("删除", systemImage: "trash") }
        }
        .sheet(isPresented: _showDetail.projectedValue) {
            EntryDetailView(entry: entry)
                .presentationDetents([.medium])
                .presentationBackground(.thinMaterial)
        }
    }
}

// MARK: - 详情
struct EntryDetailView: View {
    private var _entry: State<Entry>
    private var entry: Entry { get { _entry.wrappedValue } nonmutating set { _entry.wrappedValue = newValue } }
    private var _dismiss = Environment(\.dismiss)
    private var dismiss: DismissAction { _dismiss.wrappedValue }
    private var _store = State(wrappedValue: LedgerStore.shared)
    private var store: LedgerStore { get { _store.wrappedValue } nonmutating set { _store.wrappedValue = newValue } }

    init(entry: Entry) {
        _entry = State(wrappedValue: entry)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 8) {
                    CategoryBadge(category: entry.category, size: 56)
                    Text(entry.amountText)
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(entry.merchant)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 16)

                VStack(spacing: 0) {
                    Menu {
                        ForEach(Category.allCases) { c in
                            Button {
                                entry.category = c
                                entry.needsReview = false
                                store.update(entry)
                            } label: {
                                Label(c.title, systemImage: c.symbol)
                            }
                        }
                    } label: {
                        detailRow("分类", entry.category.title, symbol: "square.grid.2x2")
                    }
                    .buttonStyle(.plain)

                    Divider().padding(.leading, 16)

                    HStack(spacing: 10) {
                        Image(systemName: "storefront")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.brand)
                            .frame(width: 22)
                        TextField("商户 / 概要", text: merchantBinding)
                            .font(.system(size: 14))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)

                    Divider().padding(.leading, 16)
                    detailRow("来源", entry.source.title, symbol: entry.source.symbol)
                    Divider().padding(.leading, 16)
                    detailRow("时间",
                              entry.date.formatted(date: .abbreviated, time: .shortened)
                                + (entry.hasPaidTime ? "" : "（记账时间）"),
                              symbol: "clock")
                }
                .glassEffect(.regular, in: .rect(cornerRadius: 22))

                if !entry.raw.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("识别原文")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(entry.raw)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .glassEffect(.regular, in: .rect(cornerRadius: 18))
                }

                Button {
                    withAnimation {
                        store.delete(entry)
                        dismiss()
                    }
                } label: {
                    Label("删除这笔", systemImage: "trash")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .glassEffect(.regular.tint(Theme.danger.opacity(0.15)).interactive(), in: .rect(cornerRadius: 18))
                }
                .buttonStyle(.plain)
            }
            .padding(18)
            .padding(.top, 4)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationTitle("账目详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var merchantBinding: Binding<String> {
        Binding(
            get: { entry.merchant },
            set: {
                entry.merchant = $0
                entry.needsReview = $0.isEmpty
                store.update(entry)
            }
        )
    }

    private func detailRow(_ title: String, _ value: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(Theme.brand)
                .frame(width: 22)
            Text(title)
                .font(.system(size: 14))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}
