import Foundation

/// 账单解析引擎
/// 处理微信支付、支付宝、银行卡短信/手机银行通知、剪贴板文本、截图 OCR 文本
///
/// 核心原则：
/// 1. 消费记支出，收款/红包/退款记收入，本人账户间流动不计收支
/// 2. 同一笔消费多渠道来消息（微信 + 银行短信 + 手机银行）只记一次
/// 3. 信息不全（只有银行短信，没有商户）时标记「待确认」，绝不漏记
enum BillParser {

    // MARK: - 资金流向
    enum Flow: String {
        case expense     // 消费，要记账
        case transfer    // 资金内部流动：提现/充值/还款/转账/取现 → 不记账
        case income      // 收款/退款/红包/工资 → 收入
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
        var product: String = ""
        var transactionID: String = ""
        var kind: EntryKind { flow == .income ? .income : .expense }
    }

    // MARK: - 模板化解析（微信 / 支付宝账单详情页）
    /// 账单详情页有一块固定结构：
    ///   当前状态 / 支付时间 / 商品 / 商户全称 / 收单机构 / 支付方式 / 交易单号 / 商户单号
    /// 只认这块里的标准字段，其它内容（交易服务、对订单有疑惑…）一律忽略。
    static let detailLabels = [
        "当前状态", "交易状态", "退款时间", "到账时间", "领取时间", "收款时间", "转账时间", "支付时间", "交易时间", "付款时间", "消费时间",
        "创建时间", "订单时间", "交易类型", "商品说明", "商品名称", "商品", "商户全称", "商户名称",
        "商家名称", "付款方", "付款人", "对方户名", "转账说明", "退款说明", "收款方", "收款商户", "收单机构", "收款方式", "支付方式", "付款方式",
        "交易单号", "商户单号", "订单号", "实付金额", "实付款", "实际付款", "支付金额",
        "付款金额", "退款金额", "收款金额", "收入金额", "到账金额", "交易金额", "订单金额", "优惠金额", "优惠", "服务费", "金额"
    ]

    static func detailLabel(_ line: String) -> String? {
        detailLabels.sorted { $0.count > $1.count }.first { line.hasPrefix($0) }
    }

    private static func valueAfterLabel(_ line: String, _ label: String) -> String {
        String(line.dropFirst(label.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: " :：\t>›〉"))
    }

    static func parseDetailTemplate(_ text: String, now: Date = Date()) -> Parsed? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let labels = lines.compactMap { detailLabel($0) }
        let identity = ["当前状态", "交易状态", "商户全称", "商户名称", "商家名称", "支付方式",
                        "付款方式", "收款方式", "退款时间", "到账时间", "收款时间", "转账时间", "付款方", "退款金额", "收款金额", "支付时间", "交易时间", "商品", "商品说明", "商品名称", "交易单号"]
        let successLines = lines.filter { ["支付成功", "付款成功", "支付完成", "收款成功", "已收款", "已收钱", "已领取", "退款成功", "退款完成"].contains($0) }
        let successPage = successLines.count == 1 && lines.contains { receiptAmount($0) != nil }
        guard Set(labels).intersection(identity).count >= 2 || successPage else { return nil }

        var fields: [String: String] = [:]
        func valid(_ value: String, for label: String) -> Bool {
            guard !value.isEmpty, detailLabel(value) == nil else { return false }
            if label.contains("时间") { return extractFullDateTime(value) != nil }
            if label.contains("方式") {
                return extractChannel(value, source: .manual) != .unknown
                    || ["零钱", "零钱通", "余额", "余额宝"].contains(value)
            }
            if label.contains("状态") { return ["成功", "完成", "关闭", "退款", "待付款", "失败"].contains { value.contains($0) } }
            if label.contains("金额") || ["金额", "实付款", "实际付款"].contains(label) {
                return receiptAmount(value) != nil
            }
            if label.contains("单号") || label == "订单号" { return value.filter(\.isNumber).count >= 8 }
            if label.hasPrefix("商品") {
                return value.count <= 200 && !value.allSatisfy(\.isNumber)
                    && extractFullDateTime(value) == nil && receiptAmount(value) == nil
                    && extractChannel(value, source: .manual) == .unknown
                    && !["支付成功", "交易成功", "付款成功", "账单", "交易服务", "账单服务"].contains(value)
            }
            guard acceptable(value, relaxed: true), looksLikeMerchant(value),
                  extractFullDateTime(value) == nil, receiptAmount(value) == nil,
                  extractChannel(value, source: .manual) == .unknown,
                  !["支付成功", "交易成功", "付款成功", "交易服务", "账单服务"].contains(value) else { return false }
            return true
        }
        // 同行字段最可靠；拆行时按类型约束取值，不再按字符串长度盲选。
        for (index, line) in lines.enumerated() {
            guard let label = detailLabel(line) else { continue }
            var value = valueAfterLabel(line, label)
            if ["商户全称", "商户名称", "商家名称"].contains(label), index + 1 < lines.count {
                let continuation = lines[index + 1]
                // 兼容历史 OCR 文本把公司后缀最后几个字单独换行的情况。
                for suffix in ["有限责任公司", "股份有限公司", "有限公司"] {
                    for split in 1..<suffix.count {
                        if value.hasSuffix(String(suffix.prefix(split))) && continuation == String(suffix.dropFirst(split)) {
                            value += continuation
                        }
                    }
                }
            }
            if !value.isEmpty { fields[label] = value }
        }
        for (i, line) in lines.enumerated() {
            guard let label = detailLabel(line), fields[label] == nil else { continue }
            let candidates = [i + 1, i - 1].filter { lines.indices.contains($0) }
                .map { lines[$0] }.filter { valid($0, for: label) && !fields.values.contains($0) }
            if let value = candidates.max(by: { score($0) < score($1) }) { fields[label] = value }
        }
        func field(_ keys: [String]) -> String {
            keys.compactMap { fields[$0] }.first(where: { !$0.isEmpty }) ?? ""
        }
        // 实付字段 > 顶部独立金额 > 交易金额。优惠、余额、单号不参与候选。
        let explicit = field(["退款金额", "收款金额", "收入金额", "到账金额", "实付金额", "实付款", "实际付款", "支付金额", "付款金额"])
        let firstField = lines.firstIndex { detailLabel($0) != nil } ?? lines.count
        let headerAmounts = lines.prefix(firstField).compactMap { receiptAmount($0) }
        let amount = receiptAmount(explicit, allowInteger: true) ?? headerAmounts.first
            ?? receiptAmount(field(["交易金额", "金额"]), allowInteger: true)
        guard let amount, amount > 0 else { return nil }

        let product = field(["商品说明", "商品名称", "商品", "转账说明", "退款说明"])
        var merchant = field(["付款方", "付款人", "对方户名", "商户全称", "商户名称", "商家名称", "收款方", "收款商户"])
        if merchant.isEmpty {
            merchant = lines.prefix(firstField).first {
                looksLikeMerchant($0) && !["账单", "账单详情", "交易详情", "微信支付", "支付宝", "微信红包", "红包详情", "转账", "转账详情", "收款详情", "退款详情", "支付成功", "付款成功", "支付完成", "收款成功", "已收款", "已收钱", "已领取", "退款成功", "退款完成", "完成", "返回", "更多"].contains($0)
                    && receiptAmount($0) == nil && !$0.contains("交易")
            } ?? ""
        }
        let payment = field(["收款方式", "支付方式", "付款方式"])
        // 详情页出现银行名通常只是付款卡；不能据此把微信账单判为银行卡来源。
        let source: Source
        if text.contains("微信") {
            source = .wechat
        } else if text.contains("支付宝") || text.contains("花呗") {
            source = .alipay
        } else if ["零钱", "零钱通"].contains(payment) { source = .wechat
        } else if payment.contains("余额") || fields["商品说明"] != nil { source = .alipay
        } else if fields["商户单号"] != nil || (fields["当前状态"] != nil && fields["商户全称"] != nil && fields["收单机构"] != nil) { source = .wechat
        } else { source = .manual }
        let time = field(["退款时间", "到账时间", "领取时间", "收款时间", "转账时间", "支付时间", "交易时间", "付款时间", "消费时间"])
        let paidDate = extractDate(time, now: now)
        var channel = extractChannel("支付方式:" + payment, source: source)
        let account = extractAccount(payment, source: source)
        let status = field(["当前状态", "交易状态"])
        let context = status + " " + product + " " + lines.prefix(firstField).joined(separator: " ")
        let productFlow = classify(field(["交易类型"]) + " " + product)
        let flow: Flow = status.contains("退款") || ["收款金额", "收入金额", "到账金额"].contains(where: { fields[$0] != nil }) || lines.prefix(firstField).contains(where: { $0.hasPrefix("+") })
            ? .income : (productFlow == .expense ? classify(context) : productFlow)
        if flow == .income, channel == .unknown {
            if source == .wechat && (text.contains("红包") || text.contains("转账") || text.contains("收款")) { channel = .wechatZero }
            if source == .alipay && (text.contains("收款") || text.contains("转账")) { channel = .alipayBalance }
        }
        let category = flow == .income ? incomeCategory(text, merchant: merchant) : Category.guess(from: merchant + " " + product, merchant: merchant)
        if flow == .income && merchant.isEmpty { merchant = category.title }
        let ambiguous = Set(headerAmounts).count > 1 && explicit.isEmpty
        return Parsed(amountCents: amount, source: source, category: category,
                      merchant: merchant, account: account, date: paidDate ?? now,
                      raw: text, flow: flow,
                      needsReview: merchant.isEmpty || category == .other || channel == .unknown
                          || paidDate == nil || source == .manual || ambiguous,
                      channel: channel, balanceAfter: nil, hasPaidTime: paidDate != nil, product: product,
                      transactionID: firstMatch(#"^[A-Za-z0-9]{10,64}$"#, in: field(["交易单号"])) ?? "")
    }

    /// 只接受独立金额，避免把卡尾号、日期、订单号中的数字当成钱。
    private static func receiptAmount(_ text: String, allowInteger: Bool = false) -> Int? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard let value = firstMatch(#"^(?:[¥￥]\s*)?[-−–+]?\s*(?:[¥￥]\s*)?([0-9]{1,7}(?:,[0-9]{3})*(?:\.[0-9]{1,2})?)\s*(?:元)?$"#, in: t, group: 1),
              let d = Decimal(string: value.replacingOccurrences(of: ",", with: "")), d > 0, d < 1_000_000 else { return nil }
        // 无货币符号/正负号的整数可能是页码、卡号，不能作为顶部金额。
        guard allowInteger || t.contains(".") || t.contains("¥") || t.contains("￥") || t.contains("元") || t.hasPrefix("-") || t.hasPrefix("−") else { return nil }
        return NSDecimalNumber(decimal: d * 100).intValue
    }

    // MARK: - 主入口
    static func parse(_ text: String, now: Date = Date()) -> [Parsed] {
        let cleaned = normalize(text)
        if ["待收款", "待领取", "未领取", "未收款", "收款失败", "入账失败", "转账失败", "退款处理中", "退款申请中", "待入账", "预计入账", "未到账"].contains(where: { cleaned.contains($0) }) { return [] }

        // ① 账单详情页 → 走模板解析（最可靠）
        if cleaned.components(separatedBy: .newlines).contains(where: {
            firstMatch(#"^\s*(?:(?:当前状态|交易状态)\s*:?\s*)?(?:待付款|等待付款|支付失败|交易关闭|交易失败|已关闭)\s*$"#, in: $0) != nil
        }) { return [] }
        if let t = parseDetailTemplate(cleaned, now: now) {
            return [t]
        }
        // 已识别为详情页却找不到可靠交易金额时，不用优惠、余额等数字兜底。
        let receiptLabels = Set(cleaned.components(separatedBy: .newlines).compactMap { detailLabel($0.trimmingCharacters(in: .whitespaces)) })
        if receiptLabels.contains("支付方式") || receiptLabels.contains("付款方式"),
           receiptLabels.contains("商户全称") || receiptLabels.contains("商品说明") || receiptLabels.contains("支付时间") { return [] }
        guard !cleaned.isEmpty else { return [] }

        // 整体流向判定（决定这笔到底记不记）
        let wholeFlow = classify(cleaned)
        let transactionLines = cleaned.components(separatedBy: .newlines).filter { extractAmount($0) != nil }.count

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
            let flow: Flow = transactionLines > 1 || strongExpense.contains(where: { line.contains($0) }) ? lineFlow : wholeFlow

            let merchant = extractMerchant(line, full: transactionLines > 1 ? line : cleaned) ?? ""
            var account = extractAccount(line, source: source)
            if account.isEmpty { account = extractAccount(cleaned, source: source) }

            var channel = extractChannel(line, source: source)
            if channel == .unknown { channel = extractChannel(cleaned, source: source) }

            // 花呗还款：用户要求算作消费，单独归类「还款」
            let isHuabeiRepay = cleaned.contains("花呗") && cleaned.contains("还款")
            var category = flow == .income ? incomeCategory(line, merchant: merchant) : (merchant.isEmpty ? .other : Category.guess(from: line, merchant: merchant))
            if isHuabeiRepay { category = .repayment }

            // 优先账单里的「支付时间」字段；其次金额所在行自身的时间；
            // 不再从全文里抓孤立的 HH:mm（那是状态栏时间，不是支付时间）
            let paidDate = transactionLines > 1 ? extractDate(line, now: now) : (extractPaidTime(cleaned)
                ?? extractFullDateTime(cleaned)
                ?? extractDate(line, now: now))
            out.append(Parsed(
                amountCents: cents,
                source: source,
                category: category,
                merchant: merchant,
                account: account,
                date: paidDate ?? now,
                raw: cleaned.count > 600 ? String(cleaned.prefix(600)) : cleaned,
                flow: flow,
                needsReview: merchant.isEmpty || (flow == .expense && source == .bank) || (flow == .income && (category == .otherIncome || channel == .unknown)),
                channel: channel,
                balanceAfter: extractBalance(line) ?? extractBalance(cleaned),
                hasPaidTime: paidDate != nil
            ))
        }

        // 同一段文本内的重复行（微信列表常出现标题重复）
        if out.count > 1 {
            var seen = Set<String>()
            out = out.filter {
                let k = "\($0.amountCents)-\($0.merchant)-\($0.source.rawValue)-\($0.flow.rawValue)-\($0.hasPaidTime ? String(Int($0.date.timeIntervalSince1970)) : "")"
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
        if s.hasPrefix("【"), s.contains("银行】"), s.contains("尾号") || s.contains("账户") { return .bank }
        // 微信/支付宝优先：普通账单中的支付平台字样优先
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
        let action = ["消费", "支出", "扣款", "转出", "转入", "取现", "存入", "交易", "支付", "付款", "入账", "收入", "到账", "贷记", "汇入", "代发工资"]
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
        // 1) 退款/退还 → 收入
        //    注意：只认明确表述。账单页里「可在支持的商户扫码退款」是提示文案，不是退款
        let refundPhrases = ["退款成功", "退款到账", "已退款", "已退还", "已退回", "原路退回",
                             "退票成功", "退款金额", "退款完成"]
        if refundPhrases.contains(where: { s.contains($0) }) {
            return .income
        }
        if ["本人账户", "本人转账", "自己账户", "零钱提现", "余额提现", "零钱充值", "余额充值", "余额宝转入", "余额宝转出"].contains(where: { s.contains($0) }) { return .transfer }
        if ["收款到账", "收款成功", "已收款", "已收钱", "已存入零钱", "已领取", "红包收入", "红包到账", "收到红包", "入账", "收入", "向你转账", "转入人民币", "转入金额", "到账人民币", "工资到账", "存入人民币", "贷记", "汇入", "代发工资"].contains(where: { s.contains($0) }) { return .income }
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

    static func incomeCategory(_ text: String, merchant: String = "") -> Category {
        if ["退款", "退还", "退回", "退票"].contains(where: { text.contains($0) }) { return .refund }
        if let learned = Category.MerchantMemory.category(for: merchant), learned.kind == .income { return learned }
        if text.contains("红包") { return .redPacket }
        if text.contains("工资") || text.contains("薪资") || text.contains("代发") { return .salary }
        if text.contains("奖金") { return .bonus }
        if text.contains("利息") || text.contains("收益") || text.contains("分红") { return .investment }
        if text.contains("转账") || text.contains("收款") || text.contains("汇入") { return .receivedTransfer }
        return .otherIncome
    }

    // MARK: - 余额行过滤
    private static func isBalanceLine(_ s: String) -> Bool {
        let balanceWords = ["余额", "可用余额", "剩余额度", "总额度", "积分", "额度为"]
        guard balanceWords.contains(where: { s.contains($0) }) else { return false }
        // 「消费25元，余额1000元」这种同一行里既有交易又有余额 → 保留
        let tradeWords = ["消费", "支出", "扣款", "付款", "支付", "转出", "取现", "入账", "收入", "收款", "到账", "存入", "转入"]
        return !tradeWords.contains(where: { s.contains($0) })
    }

    // MARK: - 金额提取
    // 顺序很重要：先找带交易语义的金额，再退回带符号/单位
    private static let amountPatterns: [String] = [
        #"(?:消费|支出|扣款|付款|支付|入账|收入|收款|到账|贷记|汇入|存入|代发工资|转入|转出|转给|交易|金额|合计|总计|实付)(?!时间|日期|单号|编号|方式|卡号)\D{0,6}?¥?\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)(?![0-9.年月日:/])"#,
        #"¥\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)"#,
        #"([0-9][0-9,]*(?:\.[0-9]{1,2})?)\s*元"#,
        #"(?<![0-9.])([0-9]+\.[0-9]{2})(?![0-9.])"#
    ]

    static func extractAmount(_ s: String) -> Int? {
        if let label = detailLabel(s.trimmingCharacters(in: .whitespaces)),
           !label.contains("金额"), !["金额", "实付款", "实际付款"].contains(label) { return nil }
        for p in amountPatterns {
            if let m = firstMatch(p, in: s, group: 1) {
                let digits = m.replacingOccurrences(of: ",", with: "")
                // 金额上限 1 亿元：更长的数字是单号 / 卡号，直接忽略（也避免 Int 溢出崩溃）
                if digits.count <= 9, let d = Double(digits), d > 0, d < 100_000_000 {
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

    /// 在整段文本里按「标签行」取字段值，兼容三种排布：
    ///   「商户全称 上海巷鱼」 / 「商户全称\n上海巷鱼」 / 「上海巷鱼\n商户全称」
    /// - Parameter relaxed: 放宽过滤（用于「商户全称」这类权威字段，只要不是明显噪音就采用）
    private static func fieldValue(in text: String, labels: [String], relaxed: Bool = false) -> String? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // 只看「标签后面紧跟的词」判断是不是其它字段（例如 商户·单号）
        // 不能检查整行——公司名里常有「服务」「科技」等字
        let bannedAfter = ["单号", "编号", "订单号", "流水号", "号：", "号:"]
        func isTargetLine(_ line: String) -> Bool {
            guard let label = labels.first(where: { line.contains($0) }),
                  let r = line.range(of: label) else { return false }
            let after = String(line[r.upperBound...])
                .trimmingCharacters(in: CharacterSet(charactersIn: " :：\t"))
            return !bannedAfter.contains { after.hasPrefix($0) }
        }

        for (i, line) in lines.enumerated() {
            guard isTargetLine(line),
                  let label = labels.first(where: { line.contains($0) }) else { continue }

            // a) 同行带值：只取「标签之后」的内容（标签可能在行首或行中）
            if let r = line.range(of: label) {
                let rest = String(line[r.upperBound...])
                    .trimmingCharacters(in: CharacterSet(charactersIn: " :：·-"))
                if rest.count >= 2, acceptable(rest, relaxed: relaxed) { return rest }
            }

            // b) 上下相邻行都看，取更像商户名的那个
            var candidates: [String] = []
            if i + 1 < lines.count { candidates.append(lines[i + 1]) }
            if i - 1 >= 0 { candidates.append(lines[i - 1]) }
            let valid = candidates.filter { acceptable($0, relaxed: relaxed) }
            if let best = valid.max(by: { score($0) < score($1) }) { return best }
        }
        return nil
    }

    /// 「商品」值是否是可读的门店/商户名
    /// 像「【POS】_上海互联宝地店_567850」「先乘车后付款」「房租」这类不适合当来源
    private static func readableProductName(_ raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespaces)
        guard t.count >= 3, t.count <= 30 else { return false }
        if t.uppercased().contains("POS") { return false }
        if t.contains("_") { return false }
        if t.contains("先乘车") || t.contains("后付款") || t.contains("自动续费") { return false }
        let digits = t.filter { $0.isNumber }.count
        if digits > t.count / 3 { return false }
        let generic = ["房租", "电费", "水费", "燃气费", "物业费", "话费", "宽带费",
                       "商品", "订单", "消费", "收款"]
        if generic.contains(t) { return false }
        return true
    }

    /// 候选值是否可接受
    private static func acceptable(_ t: String, relaxed: Bool) -> Bool {
        guard t.count >= 2, t.count <= 40 else { return false }
        if isFieldLabel(t) { return false }
        if t.allSatisfy({ $0.isNumber }) { return false }          // 纯数字
        if t.contains("单号") || t.contains("退款") || t.contains("扫码") { return false }
        if t.contains("年") && t.contains("月") { return false }    // 日期
        if relaxed { return true }
        return looksLikeMerchant(t)
    }

    /// 商户名特征打分：越像商户分越高
    private static func score(_ t: String) -> Int {
        var s = t.count
        let hints = ["餐厅", "店", "公司", "商行", "超市", "餐饮", "酒店", "科技",
                     "百货", "广场", "中心", "银行", "集团", "工作室", "服务部"]
        if hints.contains(where: { t.contains($0) }) { s += 50 }
        return s
    }

    /// 判断某行是否像商户名（用于 OCR 值/标签错位的取舍）
    private static func looksLikeMerchant(_ t: String) -> Bool {
        guard t.count >= 2, t.count <= 40 else { return false }
        if isFieldLabel(t) || isNoiseMerchant(t) { return false }
        // 排除日期、时间、金额、单号
        if t.contains("年") && t.contains("月") { return false }
        if t.contains(":") || t.contains("：") { return false }
        let digits = t.filter { $0.isNumber }.count
        if digits > t.count / 2 { return false }
        // 排除"招商银行储蓄卡(4926)"这类支付方式
        if t.contains("储蓄卡") || t.contains("信用卡") || t.contains("借记卡") { return false }
        if t.contains("银行") && t.contains("(") { return false }
        // 单号、退款说明、扫码提示等都不是商户名
        let junk = ["单号", "编号", "订单号", "流水号", "退款", "扫码", "可在支持", "账单服务"]
        if junk.contains(where: { t.contains($0) }) { return false }
        return true
    }

    private static func isFieldLabel(_ t: String) -> Bool {
        let labels = ["支付时间", "交易时间", "付款时间", "当前状态", "支付成功", "商品",
                      "商户全称", "商户名称", "收单机构", "支付方式", "交易单号", "商户单号",
                      "账单服务", "全部账单", "账单", "单号", "退款", "扫码"]
        return labels.contains { t == $0 || t.hasPrefix($0) }
    }

    static func extractMerchant(_ line: String, full: String) -> String? {
        // ① 权威字段优先（放宽过滤，只要不是明显噪音就采用）
        if let v = fieldValue(in: full, labels: ["商户全称", "商户名称"], relaxed: true) {
            return v
        }
        if let v = fieldValue(in: full, labels: ["收款方", "收款商户", "支付对象"], relaxed: true) {
            return v
        }
        if let v = fieldValue(in: full, labels: ["商户"]) {
            return v
        }
        // ④ 最后才用商品 / 订单名兜底
        if let v = fieldValue(in: full, labels: ["商品", "订单"]) {
            return v
        }

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
                          "交易单号", "商户单号", "商品", "时间", "状态",
                          "储蓄卡", "借记卡", "信用卡", "银行卡", "零钱", "余额宝", "花呗"]
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
        let words = ["支付成功", "付款成功", "交易成功", "已支付", "支付完成", "收款成功", "已收款", "已收钱", "红包到账", "已领取",
                     "付款完成", "转账成功", "支付金额", "实付", "已付款"]
        return words.contains(where: { s.contains($0) })
    }

    // MARK: - 支付渠道（卡 / 零钱 / 花呗）
    static let bankNames = [
        "招商银行", "中国银行", "工商银行", "建设银行", "农业银行", "交通银行", "邮储银行",
        "邮政储蓄", "中信银行", "浦发银行", "兴业银行", "光大银行", "华夏银行", "民生银行",
        "广发银行", "平安银行", "北京银行", "上海银行", "宁波银行", "江苏银行", "浙商银行",
        "杭州银行", "南京银行", "成都银行", "长沙银行", "苏州银行", "重庆银行", "青岛银行",
        "渤海银行", "恒丰银行", "天津银行", "徽商银行", "厦门银行", "上海农商银行", "深圳农商银行"
    ]

    static func extractAccount(_ s: String, source: Source) -> String {
        var parts: [String] = []

        for name in bankNames where s.contains(name) { parts.append(name); break }

        let tailPatterns = [
            #"(?:尾号|末四位|后四位|最后四位)[^0-9]{0,4}(\d{4})(?![0-9])"#,
            #"\*{2,}\s*(\d{4})(?![0-9])"#,
            #"卡号[^0-9]{0,6}(\d{4})(?![0-9*•xX])"#,
            #"账户[^0-9]{0,6}(\d{4})(?![0-9])"#,
            #"(?:储蓄卡|借记卡|信用卡)[^0-9]{0,6}(\d{4})(?![0-9])"#,
            #"[\(（](\d{4})[\)）]"#,               // 招商银行储蓄卡(4926)
            #"银行[^0-9]{0,4}(\d{4})(?![0-9])"#     // 招商银行4926
        ]
        let compact = s.replacingOccurrences(of: #"(?<=[0-9])[ -](?=[0-9])"#, with: "", options: .regularExpression)
        let fullNumber = firstMatch(#"(?:卡号|账号|账户|储蓄卡|借记卡|信用卡)[^0-9]{0,6}([0-9]{12,19})(?![0-9])"#, in: compact, group: 1)
        if let tail = fullNumber.map({ String($0.suffix(4)) }) ?? tailPatterns.lazy.compactMap({ firstMatch($0, in: s, group: 1) }).first {
            if let last = parts.last, !last.contains("(") {
                parts[parts.count - 1] = "\(last)(\(tail))"
            } else {
                parts.append("卡(\(tail))")
            }
        }

        if s.contains("零钱通") { parts.append("零钱通") }
        else if s.contains("零钱") { parts.append("零钱") }
        if s.contains("余额宝") { parts.append("余额宝") }
        else if source == .alipay && s.contains("余额") { parts.append("余额") }
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
            || (s.contains("余额宝") && s.contains("支付方式"))
            || (source == .alipay && s.contains("余额") && s.contains("支付方式")) {
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
        let formats = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy/MM/dd HH:mm:ss", "yyyy/MM/dd HH:mm",
                       "yyyy年M月d日 HH:mm:ss", "yyyy年M月d日 HH:mm", "yyyy年M月d日HH:mm:ss",
                       "M月d日 HH:mm", "MM-dd HH:mm", "yyyy年M月d日HH:mm"]
        return formats.map { f in
            let df = DateFormatter()
            df.locale = Locale(identifier: "zh_CN")
            df.dateFormat = f
            df.isLenient = false
            df.timeZone = TimeZone(identifier: "Asia/Shanghai")
            return df
        }
    }()

    /// 优先使用「支付时间 / 交易时间」这类明确字段，而不是记账时刻
    /// 注意：OCR 可能把值和标签排成任意顺序（值在上、标签在下很常见），
    /// 所以只要出现标签，就取全文第一个「完整日期 + 时间」。
    static func extractPaidTime(_ s: String) -> Date? {
        let labels = ["支付时间", "交易时间", "付款时间", "消费时间", "扣款时间", "支付日期", "交易日期"]
        guard labels.contains(where: { s.contains($0) }) else { return nil }
        guard let raw = firstMatch(
            #"([0-9]{2,4}[-/年][0-9]{1,2}[-/月][0-9]{1,2}日?\s*[0-9]{1,2}:[0-9]{2}(?::[0-9]{2})?)"#,
            in: s, group: 1) else { return nil }
        for df in dateFormatters {
            if let d = df.date(from: raw) { return fixYearIfNeeded(d, now: Date()) }
        }
        return nil
    }

    /// 全文第一个「完整日期 + 时间」（不要求出现标签）
    static func extractFullDateTime(_ s: String) -> Date? {
        guard let raw = firstMatch(
            #"([0-9]{2,4}[-/年][0-9]{1,2}[-/月][0-9]{1,2}日?\s*[0-9]{1,2}:[0-9]{2}(?::[0-9]{2})?)"#,
            in: s, group: 1) else { return nil }
        for df in dateFormatters {
            if let d = df.date(from: raw) { return fixYearIfNeeded(d, now: Date()) }
        }
        return nil
    }

    static func extractDate(_ s: String, now: Date) -> Date? {
        // 先尝试完整的「日期 + 时间」片段（含秒）
        if let full = firstMatch(#"([0-9]{2,4}[-/年][0-9]{1,2}[-/月][0-9]{1,2}日?\s*[0-9]{1,2}:[0-9]{2}(?::[0-9]{2})?)"#,
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
