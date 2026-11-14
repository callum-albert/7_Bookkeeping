import Foundation
import SwiftUI

// MARK: - 账户来源
enum Source: String, Codable, CaseIterable, Identifiable {
    case wechat, alipay, bank, manual
    var id: String { rawValue }

    var title: String {
        switch self {
        case .wechat: return "微信支付"
        case .alipay: return "支付宝"
        case .bank: return "银行卡"
        case .manual: return "手动"
        }
    }

    var symbol: String {
        switch self {
        case .wechat: return "message.fill"
        case .alipay: return "a.circle.fill"
        case .bank: return "creditcard.fill"
        case .manual: return "square.and.pencil"
        }
    }

    var tint: Color {
        switch self {
        case .wechat: return Color(red: 0.13, green: 0.76, blue: 0.36)
        case .alipay: return Color(red: 0.10, green: 0.47, blue: 0.96)
        case .bank: return Color(red: 0.42, green: 0.46, blue: 0.58)
        case .manual: return .secondary
        }
    }

    /// 信息完整度：微信/支付宝通知通常带商户，银行短信只有金额
    var richness: Int {
        switch self {
        case .wechat, .alipay: return 2
        case .bank: return 1
        case .manual: return 3
        }
    }
}

enum EntryKind: String, Codable, CaseIterable, Identifiable {
    case expense, income
    var id: String { rawValue }
    var title: String { self == .income ? "收入" : "支出" }
}

// MARK: - 分类
struct Category: RawRepresentable, Codable, CaseIterable, Hashable, Identifiable {
    let rawValue: String
    init?(rawValue: String) { self.rawValue = rawValue }
    init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }
    static let food = Category(rawValue: "food")!
    static let transport = Category(rawValue: "transport")!
    static let shopping = Category(rawValue: "shopping")!
    static let entertainment = Category(rawValue: "entertainment")!
    static let home = Category(rawValue: "home")!
    static let medical = Category(rawValue: "medical")!
    static let education = Category(rawValue: "education")!
    static let digital = Category(rawValue: "digital")!
    static let social = Category(rawValue: "social")!
    static let travel = Category(rawValue: "travel")!
    static let pet = Category(rawValue: "pet")!
    static let repayment = Category(rawValue: "repayment")!
    static let rent = Category(rawValue: "rent")!
    static let utilities = Category(rawValue: "utilities")!
    static let other = Category(rawValue: "other")!
    static let salary = Category(rawValue: "salary")!
    static let bonus = Category(rawValue: "bonus")!
    static let investment = Category(rawValue: "investment")!
    static let receivedTransfer = Category(rawValue: "receivedTransfer")!
    static let redPacket = Category(rawValue: "redPacket")!
    static let refund = Category(rawValue: "refund")!
    static let otherIncome = Category(rawValue: "otherIncome")!
    static let builtIns: [Category] = [.food, .transport, .shopping, .entertainment, .home, .medical, .education, .digital, .social, .travel, .pet, .repayment, .rent, .utilities, .other, .salary, .bonus, .investment, .receivedTransfer, .redPacket, .refund, .otherIncome]
    static var allCases: [Category] { builtIns + CategoryStore.shared.categories }
    static func choices(for kind: EntryKind) -> [Category] { allCases.filter { $0.kind == kind } }
    static func custom(_ name: String, kind: EntryKind) -> Category {
        Category(rawValue: "custom:\(kind.rawValue):\(UUID().uuidString):\(name)")!
    }
    var isCustom: Bool { rawValue.hasPrefix("custom:") }
    var kind: EntryKind {
        if isCustom { return rawValue.hasPrefix("custom:income:") ? .income : .expense }
        return [.salary, .bonus, .investment, .receivedTransfer, .redPacket, .refund, .otherIncome].contains(self) ? .income : .expense
    }


    var id: String { rawValue }

    var title: String {
        switch self {
        case .food: return "餐饮"
        case .transport: return "交通"
        case .shopping: return "购物"
        case .entertainment: return "娱乐"
        case .home: return "居住"
        case .medical: return "医疗"
        case .education: return "学习"
        case .digital: return "数码"
        case .social: return "人情"
        case .travel: return "旅行"
        case .pet: return "宠物"
        case .repayment: return "还款"
        case .rent: return "房租"
        case .utilities: return "水电"
        case .other: return "其他"
        case .salary: return "工资"
        case .bonus: return "奖金"
        case .investment: return "理财收益"
        case .receivedTransfer: return "转账收款"
        case .redPacket: return "红包"
        case .refund: return "退款"
        case .otherIncome: return "其他收入"
        default: return rawValue.split(separator: ":", maxSplits: 3).last.map(String.init) ?? "自定义"
        }
    }

    var symbol: String {
        switch self {
        case .food: return "fork.knife"
        case .transport: return "car.fill"
        case .shopping: return "bag.fill"
        case .entertainment: return "gamecontroller.fill"
        case .home: return "house.fill"
        case .medical: return "cross.case.fill"
        case .education: return "book.fill"
        case .digital: return "desktopcomputer"
        case .social: return "gift.fill"
        case .travel: return "airplane"
        case .pet: return "pawprint.fill"
        case .repayment: return "arrow.triangle.2.circlepath"
        case .rent: return "key.fill"
        case .utilities: return "bolt.fill"
        case .other: return "ellipsis.circle.fill"
        case .salary, .bonus: return "banknote.fill"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .receivedTransfer: return "arrow.down.left.circle.fill"
        case .redPacket: return "gift.fill"
        case .refund: return "arrow.uturn.backward.circle.fill"
        case .otherIncome: return "plus.circle.fill"
        default: return "tag.fill"
        }
    }

    var tint: Color {
        switch self {
        case .food: return Color(red: 1.00, green: 0.45, blue: 0.26)
        case .transport: return Color(red: 0.20, green: 0.62, blue: 0.96)
        case .shopping: return Color(red: 0.96, green: 0.35, blue: 0.55)
        case .entertainment: return Color(red: 0.62, green: 0.42, blue: 0.96)
        case .home: return Color(red: 0.35, green: 0.72, blue: 0.52)
        case .medical: return Color(red: 0.94, green: 0.34, blue: 0.36)
        case .education: return Color(red: 0.28, green: 0.52, blue: 0.88)
        case .digital: return Color(red: 0.42, green: 0.48, blue: 0.98)
        case .social: return Color(red: 0.98, green: 0.55, blue: 0.32)
        case .travel: return Color(red: 0.24, green: 0.72, blue: 0.80)
        case .pet: return Color(red: 0.86, green: 0.60, blue: 0.32)
        case .repayment: return Color(red: 0.55, green: 0.50, blue: 0.85)
        case .rent: return Color(red: 0.45, green: 0.62, blue: 0.88)
        case .utilities: return Color(red: 0.98, green: 0.72, blue: 0.25)
        case .other: return Color(red: 0.58, green: 0.60, blue: 0.64)
        default: return kind == .income ? Color(red: 0.13, green: 0.65, blue: 0.48) : Color(red: 0.62, green: 0.42, blue: 0.96)
        }
    }

    /// 商户 → 分类记忆：用户改过一次，以后同一商户自动沿用
    enum MerchantMemory {
        private static let key = "merchantCategoryMap"

        static var all: [String: String] {
            UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        }

        static func normalize(_ s: String) -> String {
            s.lowercased()
                .replacingOccurrences(of: "有限责任公司", with: "")
                .replacingOccurrences(of: "有限公司", with: "")
                .replacingOccurrences(of: "股份有限公司", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        static func category(for merchant: String) -> Category? {
            let k = normalize(merchant)
            guard k.count >= 2, let raw = all[k] else { return nil }
            guard let category = Category(rawValue: raw) else { return nil }
            return category
        }

        static func remember(_ merchant: String, _ category: Category) {
            let k = normalize(merchant)
            guard k.count >= 2 else { return }
            var m = all
            m[k] = category.rawValue
            if m.count > 300 {
                m = Dictionary(uniqueKeysWithValues: Array(m).suffix(300))
            }
            UserDefaults.standard.set(m, forKey: key)
        }

        static func forget(_ merchant: String) {
            var m = all
            m.removeValue(forKey: normalize(merchant))
            UserDefaults.standard.set(m, forKey: key)
        }

        static func forget(categories: Set<String>) {
            UserDefaults.standard.set(all.filter { !categories.contains($0.value) }, forKey: key)
        }
    }

    /// 关键字自动归类，命中越多越靠前
    static func guess(from text: String, merchant: String?) -> Category {
        // 优先使用用户教过的分类
        if let merchant, let learned = MerchantMemory.category(for: merchant), learned.kind == .expense {
            return learned
        }
        let hay = (text + " " + (merchant ?? "")).lowercased()
        var best: (Category, Int) = (.other, 0)

        func score(_ c: Category, _ words: [String]) {
            var s = 0
            for w in words where hay.contains(w) { s += 1 }
            if s > best.1 { best = (c, s) }
        }

        score(.food, ["美团", "饿了么", "肯德基", "麦当劳", "星巴克", "瑞幸", "咖啡", "餐饮", "饭店",
                      "餐厅", "奶茶", "喜茶", "蜜雪", "食堂", "外卖", "烧烤", "火锅", "面包", "便利店",
                      "7-11", "全家", "罗森", "沙县", "兰州", "早餐", "午餐", "晚餐", "超市", "超市便利", "大米先生", "乡村基"])
        score(.transport, ["滴滴", "高德", "曹操", "出租车", "打车", "地铁", "公交", "地铁公交",
                           "加油", "中石化", "中石油", "停车", "高速", "etc", "铁路", "12306", "哈啰", "摩拜",
                           "乘车", "先乘车", "网约车", "交通卡", "公共交通", "一卡通", "单车",
                           "长途汽车", "客运", "机场", "车费", "过路费", "充电桩", "etc."])
        score(.shopping, ["淘宝", "天猫", "京东", "拼多多", "唯品会", "商场", "优衣库", "无印",
                          "服饰", "百货", "小米之家", "苏宁", "盒马", "山姆", "costco", "奥莱"])
        score(.entertainment, ["电影", "影城", "万达", "游戏", "steam", "票务", "大麦", "演唱会",
                               "ktv", "剧本", "密室", "订阅", "视频", "vip", "会员", "网易云", "腾讯视频", "爱奇艺", "b站"])
        score(.rent, ["房租", "租金", "租房", "押金", "中介费", "自如", "贝壳租房", "公寓租赁"])
        score(.utilities, ["电费", "水费", "燃气费", "天然气", "供暖费", "水电", "暖气",
                           "电网", "供水", "供电", "电力", "燃气缴费", "物业费"])
        score(.home, ["物业", "宽带", "装修", "家具", "家电", "保洁", "维修"])
        score(.medical, ["医院", "药房", "药店", "诊所", "医疗", "体检", "挂号", "口腔", "牙科"])
        score(.education, ["学费", "书店", "当当", "课程", "培训", "教育", "考试", "文具", "得到", "知识"])
        score(.digital, ["apple", "app store", "icloud", "数码", "华为", "苹果", "耳机", "电脑", "手机", "充电",
                         "deepseek", "api服务", "人工智能", "云服务", "云计算", "算力"])
        score(.social, ["红包", "转账", "礼金", "随礼", "份子", "红包转账"])
        score(.travel, ["携程", "airbnb", "酒店", "机票", "飞猪", "去哪儿", "民宿", "旅行", "景区", "门票"])
        score(.pet, ["宠物", "猫", "狗", "宠物医院", "猫粮", "狗粮"])
        return best.0
    }
}

// MARK: - 一笔账
struct Entry: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var kind: EntryKind = .expense
    var amountCents: Int
    var date: Date
    var category: Category
    var merchant: String        // 概要 / 商户
    var product: String = ""   // 商品说明，与商户独立保存
    var transactionID: String = "" // 平台交易单号，区分同店同金额的连续消费
    var note: String = ""
    var source: Source
    var raw: String = ""        // 命中的原始文本
    var auto: Bool = true       // 是否自动识别
    /// 支付渠道，如「招商银行(1234)」「零钱」「花呗」
    var account: String = ""
    /// 信息不全（例如只有银行短信，没有商户），需要用户确认分类
    var needsReview: Bool = false
    /// 融合了多个来源（例如微信付款 + 银行扣款短信）
    var mergedSources: [String] = []
    /// 支付渠道（零钱 / 余额 / 银行卡 / 花呗 / 信用卡）
    var channel: PayChannel = .unknown
    /// 最后修改时间，用于多设备合并时判断新旧
    var updatedAt: Date = Date()
    /// true = date 是账单里的支付时间；false = 没识别到，用的是记账时间
    var hasPaidTime: Bool = false

    var amount: Double { Double(amountCents) / 100.0 }

    init(id: UUID = UUID(), amountCents: Int, date: Date, category: Category,
         merchant: String, note: String = "", source: Source, raw: String = "",
         auto: Bool = true, account: String = "", needsReview: Bool = false,
         mergedSources: [String] = [], channel: PayChannel = .unknown,
         updatedAt: Date = Date(), hasPaidTime: Bool = false, product: String = "", transactionID: String = "", kind: EntryKind = .expense) {
        self.id = id
        self.kind = kind
        self.amountCents = amountCents
        self.date = date
        self.category = category
        self.merchant = merchant
        self.product = product
        self.transactionID = transactionID
        self.note = note
        self.source = source
        self.raw = raw
        self.auto = auto
        self.account = account
        self.needsReview = needsReview
        self.mergedSources = mergedSources
        self.channel = channel
        self.updatedAt = updatedAt
        self.hasPaidTime = hasPaidTime
    }

    // 老数据没有 channel 字段时也能读
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decodeIfPresent(EntryKind.self, forKey: .kind) ?? .expense
        amountCents = try c.decode(Int.self, forKey: .amountCents)
        date = try c.decode(Date.self, forKey: .date)
        category = try c.decode(Category.self, forKey: .category)
        merchant = try c.decode(String.self, forKey: .merchant)
        product = try c.decodeIfPresent(String.self, forKey: .product) ?? ""
        transactionID = try c.decodeIfPresent(String.self, forKey: .transactionID) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        source = try c.decode(Source.self, forKey: .source)
        raw = try c.decodeIfPresent(String.self, forKey: .raw) ?? ""
        auto = try c.decodeIfPresent(Bool.self, forKey: .auto) ?? true
        account = try c.decodeIfPresent(String.self, forKey: .account) ?? ""
        needsReview = try c.decodeIfPresent(Bool.self, forKey: .needsReview) ?? false
        mergedSources = try c.decodeIfPresent([String].self, forKey: .mergedSources) ?? []
        channel = try c.decodeIfPresent(PayChannel.self, forKey: .channel) ?? .unknown
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? date
        hasPaidTime = try c.decodeIfPresent(Bool.self, forKey: .hasPaidTime) ?? false
    }

    var amountText: String {
        let v = amount
        let prefix = kind == .income ? "+" : ""
        if v == v.rounded() { return "\(prefix)¥\(Int(v))" }
        return prefix + String(format: "¥%.2f", v)
    }
}
