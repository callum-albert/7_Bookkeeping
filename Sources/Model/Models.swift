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

// MARK: - 分类
enum Category: String, Codable, CaseIterable, Identifiable {
    case food, transport, shopping, entertainment, home, medical
    case education, digital, social, travel, pet, repayment, other

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
        case .other: return "其他"
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
        case .other: return "ellipsis.circle.fill"
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
        case .other: return Color(red: 0.58, green: 0.60, blue: 0.64)
        }
    }

    /// 关键字自动归类，命中越多越靠前
    static func guess(from text: String, merchant: String?) -> Category {
        let hay = (text + " " + (merchant ?? "")).lowercased()
        var best: (Category, Int) = (.other, 0)

        func score(_ c: Category, _ words: [String]) {
            var s = 0
            for w in words where hay.contains(w) { s += 1 }
            if s > best.1 { best = (c, s) }
        }

        score(.food, ["美团", "饿了么", "肯德基", "麦当劳", "星巴克", "瑞幸", "咖啡", "餐饮", "饭店",
                      "餐厅", "奶茶", "喜茶", "蜜雪", "食堂", "外卖", "烧烤", "火锅", "面包", "便利店",
                      "7-11", "全家", "罗森", "沙县", "兰州", "早餐", "午餐", "晚餐", "超市", "超市便利"])
        score(.transport, ["滴滴", "高德", "曹操", "出租车", "打车", "地铁", "公交", "地铁公交",
                           "加油", "中石化", "中石油", "停车", "高速", "etc", "铁路", "12306", "哈啰", "摩拜"])
        score(.shopping, ["淘宝", "天猫", "京东", "拼多多", "唯品会", "商场", "优衣库", "无印",
                          "服饰", "百货", "小米之家", "苏宁", "盒马", "山姆", "costco", "奥莱"])
        score(.entertainment, ["电影", "影城", "万达", "游戏", "steam", "票务", "大麦", "演唱会",
                               "ktv", "剧本", "密室", "订阅", "视频", "vip", "会员", "网易云", "腾讯视频", "爱奇艺", "b站"])
        score(.home, ["房租", "物业", "水电", "电费", "水费", "燃气", "天然气", "宽带", "话费", "供暖"])
        score(.medical, ["医院", "药房", "药店", "诊所", "医疗", "体检", "挂号", "口腔", "牙科"])
        score(.education, ["学费", "书店", "当当", "课程", "培训", "教育", "考试", "文具", "得到", "知识"])
        score(.digital, ["apple", "app store", "icloud", "数码", "华为", "苹果", "耳机", "电脑", "手机", "充电"])
        score(.social, ["红包", "转账", "礼金", "随礼", "份子", "红包转账"])
        score(.travel, ["携程", "airbnb", "酒店", "机票", "飞猪", "去哪儿", "民宿", "旅行", "景区", "门票"])
        score(.pet, ["宠物", "猫", "狗", "宠物医院", "猫粮", "狗粮"])
        return best.0
    }
}

// MARK: - 一笔账
struct Entry: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var amountCents: Int
    var date: Date
    var category: Category
    var merchant: String        // 概要 / 商户
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

    var amount: Double { Double(amountCents) / 100.0 }

    init(id: UUID = UUID(), amountCents: Int, date: Date, category: Category,
         merchant: String, note: String = "", source: Source, raw: String = "",
         auto: Bool = true, account: String = "", needsReview: Bool = false,
         mergedSources: [String] = [], channel: PayChannel = .unknown,
         updatedAt: Date = Date()) {
        self.id = id
        self.amountCents = amountCents
        self.date = date
        self.category = category
        self.merchant = merchant
        self.note = note
        self.source = source
        self.raw = raw
        self.auto = auto
        self.account = account
        self.needsReview = needsReview
        self.mergedSources = mergedSources
        self.channel = channel
        self.updatedAt = updatedAt
    }

    // 老数据没有 channel 字段时也能读
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        amountCents = try c.decode(Int.self, forKey: .amountCents)
        date = try c.decode(Date.self, forKey: .date)
        category = try c.decode(Category.self, forKey: .category)
        merchant = try c.decode(String.self, forKey: .merchant)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        source = try c.decode(Source.self, forKey: .source)
        raw = try c.decodeIfPresent(String.self, forKey: .raw) ?? ""
        auto = try c.decodeIfPresent(Bool.self, forKey: .auto) ?? true
        account = try c.decodeIfPresent(String.self, forKey: .account) ?? ""
        needsReview = try c.decodeIfPresent(Bool.self, forKey: .needsReview) ?? false
        mergedSources = try c.decodeIfPresent([String].self, forKey: .mergedSources) ?? []
        channel = try c.decodeIfPresent(PayChannel.self, forKey: .channel) ?? .unknown
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? date
    }

    var amountText: String {
        let v = amount
        if v == v.rounded() { return "¥\(Int(v))" }
        return String(format: "¥%.2f", v)
    }
}
