import SwiftUI
import Charts

struct StatsView: View {
    private var _store = State(wrappedValue: LedgerStore.shared)
    private var store: LedgerStore { get { _store.wrappedValue } nonmutating set { _store.wrappedValue = newValue } }
    private var _period = State(wrappedValue: Period.month)
    private var period: Period { get { _period.wrappedValue } nonmutating set { _period.wrappedValue = newValue } }
    private var _anchor = State(wrappedValue: Date())
    private var anchor: Date { get { _anchor.wrappedValue } nonmutating set { _anchor.wrappedValue = newValue } }

    private var range: DateInterval { period.range(containing: anchor) }
    private var prevRange: DateInterval { period.previous(of: anchor) }

    private var summary: LedgerStore.Summary { store.summary(in: range) }
    private var prevSummary: LedgerStore.Summary { store.summary(in: prevRange) }

    private var series: [(Date, Int)] { store.dailySeries(in: range) }

    private var delta: Double? {
        guard prevSummary.total > 0 else { return nil }
        return Double(summary.total - prevSummary.total) / Double(prevSummary.total)
    }

    private var maxDaily: Int { max(series.map(\.1).max() ?? 0, 1) }

    private var creditTotal: Int {
        store.entries(in: range).filter { $0.channel.isCredit }.reduce(0) { $0 + $1.amountCents }
    }

    /// 信用支付（花呗 / 信用卡）单独统计
    private var creditCard: some View {
        let huabei = store.entries(in: range).filter { $0.channel == .huabei }.reduce(0) { $0 + $1.amountCents }
        let credit = store.entries(in: range).filter { $0.channel == .creditCard }.reduce(0) { $0 + $1.amountCents }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 0.62, green: 0.42, blue: 0.96))
                Text("信用支付")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(creditTotal.moneyText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            HStack(spacing: 16) {
                if huabei > 0 { creditLine("花呗", huabei) }
                if credit > 0 { creditLine("信用卡", credit) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular.tint(Color(red: 0.62, green: 0.42, blue: 0.96).opacity(0.14)), in: .rect(cornerRadius: 24))
    }

    private func creditLine(_ title: String, _ cents: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(cents.moneyText)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    periodPicker
                    totalCard
                    trendCard
                    categoryCard
                    if creditTotal > 0 { creditCard }
                    if !summary.daily.isEmpty { insightCard }
                    Color.clear.frame(height: 90)
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
            }
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - 周期切换
    private var periodPicker: some View {
        VStack(spacing: 12) {
            HStack {
                Text("统计")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Spacer()
                HStack(spacing: 4) {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { shift(-1) }
                    } label: {
                        Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold))
                            .frame(width: 30, height: 30)
                    }
                    Button {
                        withAnimation { anchor = Date() }
                    } label: {
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold))
                            .frame(width: 30, height: 30)
                            .opacity(isCurrent ? 0.3 : 1)
                    }
                    .disabled(isCurrent)
                }
                .foregroundStyle(.primary)
                .glassEffect(.regular.interactive(), in: .capsule)
            }

            HStack(spacing: 6) {
                ForEach(Period.allCases) { p in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            period = p
                            anchor = Date()
                        }
                    } label: {
                        Text(p.title)
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background {
                                if period == p {
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Theme.brand)
                                        .shadow(color: Theme.brand.opacity(0.35), radius: 8, y: 4)
                                }
                            }
                            .foregroundStyle(period == p ? .white : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .glassEffect(.regular, in: .rect(cornerRadius: 18))

            Text(rangeLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)
        }
    }

    private var isCurrent: Bool {
        Calendar.current.isDate(anchor, equalTo: Date(), toGranularity: period == .year ? .year : (period == .month ? .month : (period == .week ? .weekOfYear : .day)))
    }

    private var rangeLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        switch period {
        case .day:
            f.dateFormat = "yyyy年M月d日 EEEE"
            return f.string(from: range.start)
        case .week:
            f.dateFormat = "M月d日"
            let end = range.end.addingTimeInterval(-1)
            return "\(f.string(from: range.start)) - \(f.string(from: end))"
        case .month:
            f.dateFormat = "yyyy年M月"
            return f.string(from: range.start)
        case .year:
            f.dateFormat = "yyyy年"
            return f.string(from: range.start)
        }
    }

    private func shift(_ delta: Int) {
        let step: Calendar.Component = period == .day ? .day : (period == .week ? .weekOfYear : (period == .month ? .month : .year))
        if let d = Calendar.current.date(byAdding: step, value: delta, to: anchor) { anchor = d }
    }

    // MARK: - 总额卡
    private var totalCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(period.label)支出")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let delta {
                    TagView(
                        text: String(format: "%@%.0f%%", delta >= 0 ? "↑" : "↓", abs(delta) * 100),
                        symbol: nil,
                        tint: delta >= 0 ? Theme.danger : Theme.mint
                    )
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                MoneyText(cents: summary.total, size: 42, weight: .bold)
                    .foregroundStyle(
                        LinearGradient(colors: [Theme.brand, Theme.brandSoft],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            }

            HStack(spacing: 0) {
                statPill("笔数", "\(summary.count)")
                statPill("日均", (summary.total / max(daysCount, 1)).moneyText)
                statPill("单笔最高", (summary.daily.map(\.1).max() ?? 0).moneyText)
            }
        }
        .padding(20)
        .glassEffect(.regular.tint(Theme.brand.opacity(0.15)), in: .rect(cornerRadius: 30))
        .shadow(color: Theme.brand.opacity(0.12), radius: 20, y: 10)
    }

    private var daysCount: Int {
        Int(range.duration / 86400) == 0 ? 1 : Int(range.duration / 86400)
    }

    private func statPill(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 趋势
    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("消费趋势").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("最高 \(maxDaily.moneyText)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if series.isEmpty || summary.total == 0 {
                Text("这段时间还没有消费")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                Chart {
                    ForEach(series, id: \.0) { point in
                        AreaMark(
                            x: .value("日期", point.0),
                            y: .value("金额", Double(point.1) / 100)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(colors: [Theme.brand.opacity(0.42), Theme.brand.opacity(0.02)],
                                           startPoint: .top, endPoint: .bottom)
                        )
                        LineMark(
                            x: .value("日期", point.0),
                            y: .value("金额", Double(point.1) / 100)
                        )
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                        .foregroundStyle(Theme.brand)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: .dateTime.month().day(), centered: true)
                            .font(.system(size: 9))
                        AxisGridLine().foregroundStyle(.clear)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                        AxisValueLabel {
                            if let d = v.as(Double.self) {
                                Text("¥\(Int(d))").font(.system(size: 9))
                            }
                        }
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                            .foregroundStyle(.secondary.opacity(0.25))
                    }
                }
                .frame(height: 150)
            }
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    // MARK: - 分类
    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("分类排行").font(.system(size: 13, weight: .semibold))

            if summary.byCategory.isEmpty {
                Text("暂无数据")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ForEach(Array(summary.byCategory.prefix(6).enumerated()), id: \.offset) { _, item in
                    categoryBar(item.0, item.1)
                }
            }
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    private func categoryBar(_ category: Category, _ cents: Int) -> some View {
        let ratio = summary.total == 0 ? 0 : Double(cents) / Double(summary.total)
        return HStack(spacing: 10) {
            CategoryBadge(category: category, size: 32)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(category.title).font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text(cents.moneyText)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(String(format: "%.0f%%", ratio * 100))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.secondary.opacity(0.13))
                        Capsule()
                            .fill(LinearGradient(colors: [category.tint, category.tint.opacity(0.6)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(6, geo.size.width * ratio))
                    }
                }
                .frame(height: 6)
            }
        }
    }

    // MARK: - 洞察
    private var insightCard: some View {
        let top = summary.byCategory.first
        let peak = summary.daily.max { $0.1 < $1.1 }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.warm)
                Text("小结")
                    .font(.system(size: 13, weight: .semibold))
            }
            if let top {
                insightLine("花得最多的是\(top.0.title)，占 \(Int(Double(top.1) / Double(max(summary.total, 1)) * 100))%")
            }
            if let peak {
                insightLine("\(peak.0.formatted(.dateTime.month().day())) 花费最高，共 \(peak.1.moneyText)")
            }
            if summary.count > 0 {
                insightLine("平均每笔 \(summary.average.moneyText)，共 \(summary.count) 笔")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassEffect(.regular.tint(Theme.warm.opacity(0.14)), in: .rect(cornerRadius: 26))
    }

    private func insightLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Circle().fill(.secondary.opacity(0.5)).frame(width: 4, height: 4).padding(.top, 6)
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}
