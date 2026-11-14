import Foundation

/// 账单解析引擎
/// 处理微信支付、支付宝、银行卡短信/手机银行通知、剪贴板文本、截图 OCR 文本
///
/// 核心原则：
/// 1. 只有「真实消费」入账；提现 / 充值 / 还款 / 转账 / 收款 / 退款 一律不入账
/// 2. 同一笔消费多渠道来消息（微信 + 银行短信 + 手机银行）只记一次
/// 3. 信息不全（只有银行短信，没有商户）时标记「待确认」，绝不漏记
enum BillParser {

    // MARK: - 资金流向
    enum Flow: String {
        case expense     // 消费，要记账
        case transfer    // 资金内部流动：提现/充值/还款/转账/取现 → 不记账
        case income      // 收款/退款/红包/工资 → 不记账
    }

    struct Parsed {
        var amountCents: Int
        var source: Source
        var category: Category
        var merchant: String        // 可能为空（银行短信只有金额）
        var account: String         // 「招商银行(1234)」「零钱」「花呗」
        var date: Date
        var raw: String
        var flow: Flow
        var needsReview: Bool
        /// 支付渠道：零钱 / 余额 / 银行卡 / 花呗 / 信用卡
        var channel: PayChannel
        /// 短信里带的「余额」，用于校准账户余额
        var balanceAfter: Int?
        /// date 是否为账单里的支付时间（false 表示用的是记账时刻）
        var hasPaidTime: Bool = false
    }

    // MARK: - 主入口
    static func parse(_ text: String, now: Date = Date()) -> [Parsed] {
        let cleaned = normalize(text)
        guard !cleaned.isEmpty else { return [] }

        // 整体流向判定（决定这笔到底记不记）
        let wholeFlow = classify(cleaned)

        let lines = cleaned
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var out: [Parsed] = []
        for line in lines {
            guard let cents = extractAmount(line), cents > 0, cents < 100_000_000 else { continue }
            // 余额/可用余额行不是交易金额
            if isBalanceLine(line) { continue }
            // 账单汇总行（邮件里常见）：不是单笔消费
            let summaryWords = ["可用额度", "本期账单", "账单金额", "应还金额", "最低还款",
                                "账单周期", "积分余额", "年费", "总欠款"]
            if summaryWords.contains(where: { line.contains($0) }) { continue }

            // 平台标识：OCR 截图里可能缺「微信支付/支付宝」字样，用支付语义兜底
            let source: Source
            if let s1 = detectSource(line) ?? detectSource(cleaned) {
                source = s1
            } else if looksLikePayment(cleaned) {
                source = .manual   // 标为手动，进「待确认」让用户核对渠道
            } else {
                continue
            }

            // 单行可能是收入（列表中混着收款），逐行再判定一次
            let lineFlow = classify(line)
            let flow: Flow = (lineFlow == .expense && wholeFlow != .expense) ? lineFlow : lineFlow

            let merchant = extractMerchant(line, full: cleaned) ?? ""
            var account = extractAccount(line, source: source)
            if account.isEmpty { account = extractAccount(cleaned, source: source) }

            var channel = extractChannel(line, source: source)
            if channel == .unknown { channel = extractChannel(cleaned, source: source) }

            // 花呗还款：用户要求算作消费，单独归类「还款」
            let isHuabeiRepay = cleaned.contains("花呗") && cleaned.contains("还款")
            var category = merchant.isEmpty ? .other : Category.guess(from: cleaned, merchant: merchant)
            if isHuabeiRepay { category = .repayment }

            let paidDate = extractDate(line, now: now)
                ?? extractPaidTime(cleaned)
                ?? extractDate(cleaned, now: now)
            out.append(Parsed(
                amountCents: cents,
                source: source,
                category: category,
                merchant: merchant,
                account: account,
                date: paidDate ?? now,
                raw: cleaned.count > 600 ? String(cleaned.prefix(600)) : cleaned,
                flow: flow,
                needsReview: flow == .expense && (merchant.isEmpty || source == .bank),
                channel: channel,
                balanceAfter: extractBalance(line) ?? extractBalance(cleaned),
                hasPaidTime: paidDate != nil
            ))
        }

        // 同一段文本内的重复行（微信列表常出现标题重复）
        if out.count > 1 {
            var seen = Set<String>()
            out = out.filter {
                let k = "\($0.amountCents)-\($0.merchant)-\($0.source.rawValue)"
                if seen.contains(k) { return false }
                seen.insert(k); return true
            }
        }
        return out
    }

    static func parseFirst(_ text: String) -> Parsed? { parse(text).first }

    // MARK: - 文本规整
    private static func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "￥", with: "¥")
            .replacingOccurrences(of: "（）", with: "()")
            .applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? s
    }

    // MARK: - 平台识别
    static func detectSource(_ s: String) -> Source? {
        // 微信/支付宝优先：银行短信里也可能出现「微信」字样
        if s.contains("微信") { return .wechat }
        if s.contains("支付宝") || s.contains("花呗") || s.contains("余额宝") || s.contains("alipay") { return .alipay }
        if isBankText(s) { return .bank }
        return nil
    }

    private static let bankHints = [
        "银行", "信用卡", "储蓄卡", "借记卡", "尾号", "账户", "人民币", "转账", "余额",
        "中信", "招商", "工商", "建设", "农业", "交通银行", "中国银行", "邮储", "民生",
        "浦发", "兴业", "光大", "华夏", "广发", "平安银行", "北京银行", "上海银行"
    ]

    static func isBankText(_ s: String) -> Bool {
        // 必须有金融动作词，避免把普通文本误判成银行
        let action = ["消费", "支出", "扣款", "转出", "转入", "取现", "存入", "交易", "支付", "付款"]
        guard action.contains(where: { s.contains($0) }) else { return false }
        return bankHints.contains(where: { s.contains($0) })
    }

    // MARK: - 资金流向判定
    private static let strongExpense = [
        "付款成功", "支付成功", "已成功付款", "已成功支付", "已支付", "扣款成功",
        "消费", "支出", "已付款", "交易成功", "支付完成", "扣费"
    ]

    private static let transferWords = [
        "提现", "零钱充值", "余额充值", "钱包充值", "充值到", "转入零钱", "转入余额",
        "余额宝转入", "余额宝转出", "余利宝", "零钱通", "还款", "信用卡还款", "花呗还款",
        "转账给", "转账到", "向他转账", "向你转账", "转账成功", "转出", "转入",
        "取现", "存款", "存入", "网商银行转入", "自动转入", "定期转入", "贵金属"
    ]

    private static let incomeWords = [
        "收款到账", "收到一笔", "收款成功", "已收钱", "红包到账", "收到红包",
        "劳务报酬", "报销到账", "工资到账", "入账成功", "别人给你", "向你转账",
        "红包收入", "余额提现到账"
    ]

    static func classify(_ s: String) -> Flow {
        // 1) 退款/退还 → 收入（"支付成功已退还"）
        if s.contains("退款") || s.contains("已退还") || s.contains("退票") || s.contains("已退回") {
            return .income
        }
        // 1.5) 花呗还款：按需求算作消费（其余还款仍视为资金转移）
        if s.contains("花呗") && (s.contains("还款") || s.contains("已还")) { return .expense }
        // 2) 强消费信号最优先：「付款成功 / 支付成功 / 消费 / 支出」
        //    避免 "收款方：瑞幸咖啡" 这类字段名把消费误判成收入
        if strongExpense.contains(where: { s.contains($0) }) { return .expense }
        // 3) 转账 / 提现 / 充值 / 还款：资金内部流动，不记账
        if transferWords.contains(where: { s.contains($0) }) {
            // 例外：「话费充值」「加油充值」属于真实消费
            let realSpend = ["话费充值", "流量充值", "加油充值", "会员充值", "游戏充值", "充值话费", "话费"]
            if !realSpend.contains(where: { s.contains($0) }) {
                return .transfer
            }
            return .expense
        }
        // 4) 收入关键词
        if incomeWords.contains(where: { s.contains($0) }) { return .income }
        // 5) 默认：有金额算消费（微信/支付宝付款通知）
        return .expense
    }

    // MARK: - 余额行过滤
    private static func isBalanceLine(_ s: String) -> Bool {
        let balanceWords = ["余额", "可用余额", "剩余额度", "总额度", "积分", "额度为"]
        guard balanceWords.contains(where: { s.contains($0) }) else { return false }
        // 「消费25元，余额1000元」这种同一行里既有交易又有余额 → 保留
        let tradeWords = ["消费", "支出", "扣款", "付款", "支付", "转出", "取现"]
        return !tradeWords.contains(where: { s.contains($0) })
    }

    // MARK: - 金额提取
    // 顺序很重要：先找带交易语义的金额，再退回带符号/单位
    private static let amountPatterns: [String] = [
        #"(?:消费|支出|扣款|付款|支付|转出|转给|交易|金额|合计|总计|实付)\D{0,6}?¥?\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)"#,
        #"¥\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)"#,
        #"([0-9][0-9,]*(?:\.[0-9]{1,2})?)\s*元"#,
        #"(?<![0-9.])([0-9]+\.[0-9]{2})(?![0-9])"#
    ]

    static func extractAmount(_ s: String) -> Int? {
        for p in amountPatterns {
            if let m = firstMatch(p, in: s, group: 1) {
                let digits = m.replacingOccurrences(of: ",", with: "")
                if let d = Double(digits), d > 0 {
                    return Int((d * 100).rounded())
                }
            }
        }
        return nil
    }

    // MARK: - 商户 / 概要
    private static let merchantPatterns: [String] = [
        // 「商户全称」「商户名称」优先，值可能在下一行
        #"商户(?:全称|名称)[\s:：]*([^\n,。]{2,40})"#,
        #"收款方\s*:?\s*([^\n,。]+)"#,
        #"商户\s*:?\s*([^\n,。]+)"#,
        #"支付对象\s*:?\s*([^\n,。]+)"#,
        #"收款商户\s*:?\s*([^\n,。]+)"#,
        #"向\s*([^\n,。]+?)\s*(?:付款|支付|转账)"#,
        #"(?:付款给|支付给)\s*([^\n,。]+)"#,
        #"在\s*([^\n,。]+?)\s*(?:消费|付款|支付|下单|购买)"#,
        #"(?:商品|订单|消费项目)\s*:?\s*([^\n,。]+)"#,
        #"【([^】]{2,20})】"#,
        #"\|\s*([^\|\n]{2,20})\s*\|"#
    ]

    static func extractMerchant(_ line: String, full: String) -> String? {
        for p in merchantPatterns {
            if let m = firstMatch(p, in: line, group: 1) {
                let t = clean(m)
                if t.count >= 2 && !isNoiseMerchant(t) { return t }
            }
        }
        for p in merchantPatterns {
            if let m = firstMatch(p, in: full, group: 1) {
                let t = clean(m)
                if t.count >= 2 && !isNoiseMerchant(t) { return t }
            }
        }
        return nil
    }

    private static func isNoiseMerchant(_ t: String) -> Bool {
        let fieldNames = ["全称", "名称", "商户", "商户全称", "商户名称", "支付方式", "收单机构",
                          "交易单号", "商户单号", "商品", "时间", "状态"]
        if fieldNames.contains(t) { return true }
        let noise = ["微信支付", "支付宝", "通知", "服务", "银行", "消费", "支付成功", "付款成功",
                     "交易提醒", "账户", "中国银行", "工商银行", "招商银行", "建设银行", "农业银行"]
        return noise.contains { t == $0 || (t.contains($0) && t.count <= $0.count + 3) }
    }

    private static func clean(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        for w in ["元", "笔", "-", "·", "的"] where t.hasSuffix(w) { t = String(t.dropLast(w.count)) }
        t = t.replacingOccurrences(of: "微信支付", with: "")
        t = t.replacingOccurrences(of: "支付宝", with: "")
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 没有任何平台字样，但有明确的「支付成功 + 金额」 → 仍然记账（宁可待确认，也不漏记）
    private static func looksLikePayment(_ s: String) -> Bool {
        let words = ["支付成功", "付款成功", "交易成功", "已支付", "支付完成",
                     "付款完成", "转账成功", "支付金额", "实付", "已付款"]
        return words.contains(where: { s.contains($0) })
    }

    // MARK: - 支付渠道（卡 / 零钱 / 花呗）
    private static let bankNames = [
        "招商银行", "中国银行", "工商银行", "建设银行", "农业银行", "交通银行", "邮储银行",
        "邮政储蓄", "中信银行", "浦发银行", "兴业银行", "光大银行", "华夏银行", "民生银行",
        "广发银行", "平安银行", "北京银行", "上海银行", "宁波银行", "江苏银行", "浙商银行"
    ]

    static func extractAccount(_ s: String, source: Source) -> String {
        var parts: [String] = []

        for name in bankNames where s.contains(name) { parts.append(name); break }

        let tailPatterns = [
            #"(?:尾号|末四位|后四位|最后四位)[^0-9]{0,4}(\d{4})"#,
            #"卡号[^0-9]{0,6}(\d{4})"#,
            #"\*{2,}(\d{4})"#,
            #"账户[^0-9]{0,6}(\d{4})"#,
            #"(?:储蓄卡|借记卡|信用卡)[^0-9]{0,6}(\d{4})"#,
            #"[\(（](\d{4})[\)）]"#,               // 招商银行储蓄卡(4926)
            #"银行[^0-9]{0,4}(\d{4})(?![0-9])"#     // 招商银行4926
        ]
        if let tail = tailPatterns.lazy.compactMap({ firstMatch($0, in: s, group: 1) }).first {
            if let last = parts.last, !last.contains("(") {
                parts[parts.count - 1] = "\(last)(\(tail))"
            } else {
                parts.append("卡(\(tail))")
            }
        }

        if s.contains("零钱通") { parts.append("零钱通") }
        else if s.contains("零钱") { parts.append("零钱") }
        if s.contains("余额宝") { parts.append("余额宝") }
        if s.contains("花呗") { parts.append("花呗") }
        if s.contains("信用卡") && !parts.contains(where: { $0.contains("银行") }) { parts.append("信用卡") }

        return parts.joined(separator: " · ")
    }

    // MARK: - 支付渠道
    static func extractChannel(_ s: String, source: Source) -> PayChannel {
        // 花呗 / 信用卡：支付页通常会明确标注
        if s.contains("花呗") { return .huabei }
        // 「零钱」「余额」在付款成功页可能是余额显示，必须带支付语义才算
        if s.contains("零钱通") || s.contains("零钱支付")
            || s.contains("支付方式:零钱") || s.contains("微信零钱")
            || (s.contains("零钱") && s.contains("支付方式")) {
            return .wechatZero
        }
        if s.contains("余额宝支付") || s.contains("支付方式:余额")
            || (s.contains("余额宝") && s.contains("支付方式")) {
            return .alipayBalance
        }
        if s.contains("信用卡") { return .creditCard }
        if s.contains("借记卡") || s.contains("储蓄卡") || s.contains("银行卡") { return .bank }
        if bankNames.contains(where: { s.contains($0) }) { return .bank }
        if source == .bank { return .bank }
        return .unknown
    }

    // MARK: - 余额（短信里带的）
    static func extractBalance(_ s: String) -> Int? {
        // 「余额1234.56元」「可用余额：¥1,234.56」；排除「余额宝」
        guard let m = firstMatch(#"(?:可用余额|账户余额|余额)(?!宝)[^0-9¥]{0,6}¥?\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)"#,
                                 in: s, group: 1) else { return nil }
        let digits = m.replacingOccurrences(of: ",", with: "")
        guard let d = Double(digits) else { return nil }
        return Int((d * 100).rounded())
    }

    // MARK: - 时间提取
    private static let dateFormatters: [DateFormatter] = {
        let formats = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy/MM/dd HH:mm",
                       "yyyy年M月d日 HH:mm:ss", "yyyy年M月d日 HH:mm", "yyyy年M月d日HH:mm:ss",
                       "M月d日 HH:mm", "MM-dd HH:mm", "yyyy年M月d日HH:mm"]
        return formats.map { f in
            let df = DateFormatter()
            df.locale = Locale(identifier: "zh_CN")
            df.dateFormat = f
            return df
        }
    }()

    /// 优先使用「支付时间 / 交易时间」这类明确字段，而不是记账时刻
    static func extractPaidTime(_ s: String) -> Date? {
        let pattern = #"(?:支付时间|交易时间|付款时间|消费时间|扣款时间)[\s:：]*([0-9]{2,4}[-/年][0-9]{1,2}[-/月][0-9]{1,2}日?\s*[0-9]{1,2}:[0-9]{2}(?::[0-9]{2})?)"#
        guard let raw = firstMatch(pattern, in: s, group: 1) else { return nil }
        for df in dateFormatters {
            if let d = df.date(from: raw) { return fixYearIfNeeded(d, now: Date()) }
        }
        return nil
    }

    static func extractDate(_ s: String, now: Date) -> Date? {
        // 先尝试完整的「日期 + 时间」片段（含秒）
        if let full = firstMatch(#"([0-9]{2,4}[-/年][0-9]{1,2}[-/月][0-9]{1,2}日?\s+[0-9]{1,2}:[0-9]{2}(?::[0-9]{2})?)"#,
                                 in: s, group: 1) {
            for df in dateFormatters {
                if let d = df.date(from: full) { return fixYearIfNeeded(d, now: now) }
            }
        }
        for df in dateFormatters {
            let comps = s.components(separatedBy: CharacterSet(charactersIn: " ,|｜"))
            for c in comps {
                let t = c.trimmingCharacters(in: .whitespaces)
                if t.count >= 6, let d = df.date(from: t) { return fixYearIfNeeded(d, now: now) }
            }
        }
        if let m = firstMatch(#"(\d{1,2}:\d{2}(?::\d{2})?)"#, in: s, group: 1) {
            let df = DateFormatter()
            df.locale = Locale(identifier: "zh_CN")
            df.dateFormat = m.count > 5 ? "HH:mm:ss" : "HH:mm"
            if let t = df.date(from: m) {
                let cal = Calendar.current
                var c = cal.dateComponents([.year, .month, .day], from: now)
                let tc = cal.dateComponents([.hour, .minute, .second], from: t)
                c.hour = tc.hour; c.minute = tc.minute; c.second = tc.second
                if let d = cal.date(from: c) { return d }
            }
        }
        return nil
    }

    private static func fixYearIfNeeded(_ d: Date, now: Date) -> Date {
        let cal = Calendar.current
        if cal.component(.year, from: d) < 2000 {
            var c = cal.dateComponents([.month, .day, .hour, .minute], from: d)
            c.year = cal.component(.year, from: now)
            return cal.date(from: c) ?? now
        }
        return d
    }

    // MARK: - 正则工具
    private static func firstMatch(_ pattern: String, in text: String, group: Int = 0) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)) else { return nil }
        guard group < m.numberOfRanges else { return nil }
        let r = m.range(at: group)
        guard r.location != NSNotFound else { return nil }
        return ns.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
