import Foundation

// 解析 + 去重 + 余额逻辑测试
LedgerStore.storageDirectory = URL(fileURLWithPath: "/tmp/7jz-test-data")
try? FileManager.default.removeItem(at: LedgerStore.storageDirectory)

var pass = 0
var fail = 0

func check(_ name: String, _ cond: Bool, _ detail: String = "") {
    if cond { pass += 1; print("  ✅ \(name)") }
    else { fail += 1; print("  ❌ \(name)  \(detail)") }
}

func parse1(_ s: String) -> BillParser.Parsed? {
    let r = BillParser.parse(s)
    return r.first
}

print("\n── 1. 消费识别 ──")
let w1 = parse1("微信支付 你已成功付款25.00元")
check("微信付款 25 元", w1?.amountCents == 2500 && w1?.flow == .expense && w1?.source == .wechat,
      "\(String(describing: w1))")

let a1 = parse1("支付宝 你已成功付款 12.50 元，收款方：瑞幸咖啡")
check("支付宝付款带商户", a1?.amountCents == 1250 && a1?.flow == .expense && a1?.merchant == "瑞幸咖啡",
      "\(String(describing: a1))")

let m1 = parse1("支付宝 美团订单 支付成功 ¥45.90")
check("支付宝/微信通用付款", m1?.amountCents == 4590 && m1?.flow == .expense, "\(String(describing: m1))")

print("\n── 2. 资金内部流动（必须不记账）──")
let t1 = parse1("微信支付 零钱提现到银行卡 100.00元")
check("零钱提现 → 不算消费", t1?.flow == .transfer, "\(String(describing: t1))")

let t2 = parse1("支付宝 余额宝转入 1000.00元")
check("余额宝转入 → 不算消费", t2?.flow == .transfer, "\(String(describing: t2))")

let t3 = parse1("支付宝 花呗还款 500.00元")
check("花呗还款 → 算消费（按需求）", t3?.flow == .expense, "\(String(describing: t3))")

let t4 = parse1("微信支付 信用卡还款成功 ２00元")
check("信用卡还款 → 不算消费", t4?.flow == .transfer, "\(String(describing: t4))")

let t5 = parse1("招商银行 您尾号1234账户转出300.00元")
check("银行转出 → 不算消费", t5?.flow == .transfer, "\(String(describing: t5))")

print("\n── 3. 收入 / 退款（必须不记账）──")
let i1 = parse1("微信支付 收款到账 8.88元")
check("收款到账 → 收入", i1?.flow == .income, "\(String(describing: i1))")

let i2 = parse1("支付宝 退款成功 25.00元")
check("退款 → 收入", i2?.flow == .income, "\(String(describing: i2))")

print("\n── 4. 银行短信解析 ──")
let b1 = parse1("【招商银行】您尾号1234的账户于11月14日12:30消费25.00元，余额1234.56元")
check("银行消费短信金额", b1?.amountCents == 2500, "\(String(describing: b1))")
check("银行短信 → 银行来源", b1?.source == .bank, "\(String(describing: b1?.source))")
check("银行短信提取卡尾号", (b1?.account ?? "").contains("1234"), "\(String(describing: b1?.account))")
check("银行短信标记待确认", b1?.needsReview == true && b1?.flow == .expense, "\(String(describing: b1))")

let b2 = parse1("您尾号5678的信用卡11月14日在星巴克消费32.00元")
check("银行短信带商户", b2?.merchant == "星巴克" && b2?.amountCents == 3200, "\(String(describing: b2))")

print("\n── 5. 话费/加油充值仍算消费 ──")
let e1 = parse1("支付宝 话费充值成功 50.00元")
check("话费充值 → 消费", e1?.flow == .expense, "\(String(describing: e1))")

print("\n── 6. 跨渠道去重（核心）──")
let store = LedgerStore.shared

// 场景 A：先微信通知，后银行短信 → 只记 1 笔
_ = store.ingest(BillParser.parse("微信支付 你已成功付款 88.00元").first!)
let beforeA = store.entries.count
let rA = store.ingest(BillParser.parse("【中信银行】您尾号6666账户消费88.00元，余额5000元").first!)
if case .merged(let m) = rA {
    check("微信 + 银行短信 → 合并为 1 笔", store.entries.count == beforeA && m.amountCents == 8800,
          "count=\(store.entries.count) \(m.merchant)")
} else {
    check("微信 + 银行短信 → 合并为 1 笔", false, "outcome=\(rA) count=\(store.entries.count)")
}

// 场景 B：先银行短信，后微信通知 → 仍是 1 笔，且商户/分类被补全
_ = store.ingest(BillParser.parse("【建设银行】您尾号9999账户消费66.00元，余额100元").first!)
let beforeB = store.entries.count
let rB = store.ingest(BillParser.parse("微信支付 你已成功付款 66.00元，收款方：肯德基").first!)
if case .merged(let m) = rB {
    check("银行先到 + 微信后到 → 合并", store.entries.count == beforeB, "count=\(store.entries.count)")
    check("合并后补齐商户", m.merchant.contains("肯德基"), "merchant=\(m.merchant)")
    check("合并后不再是待确认", m.needsReview == false, "review=\(m.needsReview)")
    check("合并后来源升级为微信", m.source == .wechat, "source=\(m.source)")
} else {
    check("银行先到 + 微信后到 → 合并", false, "outcome=\(rB)")
}

// 场景 C：同一平台重复推送 → 丢弃
let beforeC = store.entries.count
_ = store.ingest(BillParser.parse("微信支付 你已成功付款 66.00元，收款方：肯德基").first!)
check("微信重复推送 → 去重", store.entries.count == beforeC, "count=\(store.entries.count)")

// 场景 D：同金额但不同商户 → 必须记两笔
let beforeD = store.entries.count
_ = store.ingest(BillParser.parse("微信支付 你已成功付款 77.00元，收款方：星巴克").first!)
let afterD1 = store.entries.count
_ = store.ingest(BillParser.parse("微信支付 你已成功付款 77.00元，收款方：麦当劳").first!)
check("同金额不同商户 → 记两笔", afterD1 == beforeD + 1 && store.entries.count == beforeD + 2,
      "before=\(beforeD) mid=\(afterD1) after=\(store.entries.count)")

print("\n── 7. 转账/收款不写进账目 ──")
let beforeE = store.entries.count
_ = store.ingest(BillParser.parse("微信支付 零钱提现到银行卡 500.00元").first!)
check("提现不产生账目", store.entries.count == beforeE, "count=\(store.entries.count)")
check("提现事件被记录到待复核", store.ignored.count > 0, "ignored=\(store.ignored.count)")

print("\n── 8. 多笔混合文本 ──")
let multi = """
微信支付 你已成功付款 15.00元
微信支付 你已成功付款 22.00元
微信支付 零钱提现 300.00元
"""
let rs = BillParser.parse(multi)
let expenses = rs.filter { $0.flow == .expense }
check("混合文本只取消费", expenses.count == 2, "all=\(rs.count) expense=\(expenses.count)")

print("\n── 9. 花呗：还款算消费 + 购物单独标记 ──")
let hb1 = parse1("支付宝 花呗还款 500.00元")
check("花呗还款 → 算消费", hb1?.flow == .expense, "\(String(describing: hb1?.flow))")
check("花呗还款 → 分类为「还款」", hb1?.category == .repayment, "\(String(describing: hb1?.category))")
check("花呗还款 → 渠道花呗", hb1?.channel == .huabei, "\(String(describing: hb1?.channel))")

let hb2 = parse1("支付宝 你已成功付款 32.00元，收款方：星巴克，花呗")
check("花呗购物 → 渠道花呗", hb2?.channel == .huabei && hb2?.flow == .expense, "\(String(describing: hb2))")
check("花呗购物 → 分类正常（非还款）", hb2?.category != .repayment, "\(String(describing: hb2?.category))")

print("\n── 10. 支付渠道识别 ──")
check("零钱支付", parse1("微信支付 你已成功付款 20.00元，支付方式：零钱")?.channel == .wechatZero)
check("银行卡支付", parse1("微信支付 你已成功付款 20.00元，支付方式：招商银行储蓄卡(1234)")?.channel == .bank)
check("银行短信 → 银行卡渠道", b1?.channel == .bank, "\(String(describing: b1?.channel))")
check("信用卡短信 → 信用卡渠道", parse1("您尾号5678的信用卡在星巴克消费32.00元")?.channel == .creditCard)

print("\n── 11. 余额校准 ──")
check("银行短信提取余额", b1?.balanceAfter == 123456, "\(String(describing: b1?.balanceAfter))")
let acct = Accounts.shared
acct.setAll(wechat: 100000, alipay: 50000, bank: 800000)
check("手动设置余额", acct.balance(.wechat) == 100000 && acct.total == 950000, "\(acct.total)")

// 零钱支付 → 扣微信余额
let store2 = LedgerStore.shared
_ = store2.ingest(BillParser.parse("微信支付 你已成功付款 30.00元，支付方式：零钱，收款方：便利店").first!)
check("零钱消费扣微信余额", acct.balance(.wechat) == 97000, "\(acct.balance(.wechat))")

// 花呗消费 → 不动任何余额
let beforeTotal = acct.total
_ = store2.ingest(BillParser.parse("支付宝 你已成功付款 777.00元，收款方：京东自营，花呗").first!)
check("花呗消费不扣余额", acct.total == beforeTotal, "\(acct.total) vs \(beforeTotal)")

// 删除账目 → 余额退回
if let last = store2.entries.last, last.channel == .huabei {
    store2.delete(last)
}
check("花呗账目删除后余额不变", acct.total == beforeTotal, "\(acct.total)")

print("\n── 12. 手动按钮 vs 自动记账 去重 ──")
store2.deleteAll()
let base = Date()
func mk(_ amount: Int, _ source: Source, _ merchant: String, _ channel: PayChannel,
        _ date: Date, _ vague: Bool) -> BillParser.Parsed {
    BillParser.Parsed(amountCents: amount, source: source, category: .food,
                      merchant: merchant, account: "", date: date, raw: "test",
                      flow: .expense, needsReview: vague, channel: channel, balanceAfter: nil)
}

// 场景 1：银行短信先到（自动）→ 2 分钟后按按钮（截图）
_ = store2.ingest(mk(2500, .bank, "", .bank, base, true), trigger: .automatic)
check("① 银行短信先入库", store2.entries.count == 1, "count=\(store2.entries.count)")
let dup1 = store2.ingest(mk(2500, .wechat, "星巴克", .wechatZero, base.addingTimeInterval(120), false), trigger: .manual)
check("① 手动按键不重复记", store2.entries.count == 1, "count=\(store2.entries.count)")
if case .merged(let e) = dup1 {
    check("① 合并后补上商户", e.merchant == "星巴克", e.merchant)
} else {
    check("① 合并结果", false, "\(dup1)")
}

// 场景 2：手动按键先 → 银行短信后到
store2.deleteAll()
_ = store2.ingest(mk(3300, .wechat, "瑞幸咖啡", .wechatZero, base, false), trigger: .manual)
_ = store2.ingest(mk(3300, .bank, "", .bank, base.addingTimeInterval(30), true), trigger: .automatic)
check("② 银行短信后到不重复", store2.entries.count == 1, "count=\(store2.entries.count)")

// 场景 3：连按两次按钮
store2.deleteAll()
_ = store2.ingest(mk(8800, .manual, "肯德基", .unknown, base, false), trigger: .manual)
_ = store2.ingest(mk(8800, .manual, "肯德基", .unknown, base.addingTimeInterval(20), false), trigger: .manual)
check("③ 连按两次只记一笔", store2.entries.count == 1, "count=\(store2.entries.count)")

// 场景 4：15 分钟后手动补记（自动窗口 5 分钟不够，手动窗口 30 分钟够）
store2.deleteAll()
_ = store2.ingest(mk(1200, .bank, "", .bank, base, true), trigger: .automatic)
_ = store2.ingest(mk(1200, .alipay, "便利店", .unknown, base.addingTimeInterval(900), false), trigger: .manual)
check("④ 15 分钟后手动补记 → 合并", store2.entries.count == 1, "count=\(store2.entries.count)")

// 场景 5：同金额不同商户的真实两笔，都要保留
store2.deleteAll()
_ = store2.ingest(mk(5000, .wechat, "星巴克", .wechatZero, base, false), trigger: .manual)
_ = store2.ingest(mk(5000, .wechat, "麦当劳", .wechatZero, base.addingTimeInterval(400), false), trigger: .manual)
check("⑤ 不同商户两笔都保留", store2.entries.count == 2, "count=\(store2.entries.count)")

// 场景 6：余额只扣一次
store2.deleteAll()
acct.setAll(wechat: 100000, alipay: 0, bank: 500000)
_ = store2.ingest(mk(2000, .bank, "", .bank, base, true), trigger: .automatic)
let bankAfterAuto = acct.balance(.bank)
_ = store2.ingest(mk(2000, .wechat, "某商户", .unknown, base.addingTimeInterval(60), false), trigger: .manual)
check("⑥ 手动补记不重复扣余额", acct.balance(.bank) == bankAfterAuto,
      "\(acct.balance(.bank)) vs \(bankAfterAuto)")

print("\n── 13. 跨设备同步合并 ──")
store2.deleteAll()
acct.setAll(wechat: 0, alipay: 0, bank: 0)

let localE = Entry(amountCents: 1000, date: base, category: .food, merchant: "本地店", source: .wechat)
store2.add(localE)

var remoteUpdated = localE
remoteUpdated.merchant = "本地店(已改)"
remoteUpdated.updatedAt = base.addingTimeInterval(100)
let remoteNew = Entry(amountCents: 2000, date: base, category: .shopping, merchant: "远端店", source: .alipay)

let payloadA = SyncPayload(exportedAt: Date(), deviceName: "iPhone A",
                           entries: [remoteUpdated, remoteNew], ignored: [], deletedIDs: [],
                           balances: ["wechat": 50000, "alipay": 100000, "bank": 200000])
let mr = store2.mergeRemote(payloadA)
check("⑦ 合并新增 1 笔", mr.added == 1, "\(mr)")
check("⑦ 合并更新 1 笔", mr.updated == 1, "\(mr)")
check("⑦ 合并后共 2 笔", store2.entries.count == 2, "count=\(store2.entries.count)")
check("⑦ updatedAt 较新者胜出",
      store2.entries.first(where: { $0.id == localE.id })?.merchant == "本地店(已改)",
      store2.entries.first(where: { $0.id == localE.id })?.merchant ?? "nil")

store2.deleteAll()
let delE = Entry(amountCents: 500, date: base, category: .food, merchant: "A店", source: .wechat)
store2.add(delE)
store2.delete(delE)
let payloadB = SyncPayload(exportedAt: Date(), deviceName: "iPhone B",
                           entries: [delE], ignored: [], deletedIDs: [], balances: [:])
store2.mergeRemote(payloadB)
check("⑧ 已删除账目不会被其它设备复活", store2.entries.isEmpty, "count=\(store2.entries.count)")

acct.importBalances(["wechat": 123400, "alipay": 0, "bank": 0])
check("⑨ 余额可从备份导入", acct.balance(.wechat) == 123400, "\(acct.balance(.wechat))")

print("\n── 14. 银行卡细化到卡号 ──")
acct.setAll(wechat: 0, alipay: 0, bank: 0)
for c in acct.cards { acct.removeCard(id: c.id) }
acct.addCard(bankName: "招商银行", tail: "1234", balanceCents: 100000)
acct.addCard(bankName: "建设银行", tail: "5678", balanceCents: 50000)
check("⑩ 两张卡合计正确", acct.bankTotal == 150000, "\(acct.bankTotal)")

acct.charge(2000, channel: .bank, tail: "1234")
check("⑪ 扣减命中指定卡",
      acct.cards.first(where: { $0.tail == "1234" })?.balanceCents == 98000,
      "\(acct.cards.first(where: { $0.tail == "1234" })?.balanceCents ?? -1)")
check("⑫ 其它卡不受影响",
      acct.cards.first(where: { $0.tail == "5678" })?.balanceCents == 50000)

acct.applyBankBalance(88888, tail: "5678")
check("⑬ 短信余额只校准对应卡",
      acct.cards.first(where: { $0.tail == "5678" })?.balanceCents == 88888,
      "\(acct.cards.first(where: { $0.tail == "5678" })?.balanceCents ?? -1)")

acct.upsertCard(bankName: "工商银行", tail: "9999")
check("⑭ 自动登记新卡", acct.cards.count == 3, "count=\(acct.cards.count)")
let firstCardID = acct.cards[0].id
acct.removeCard(id: firstCardID)
check("⑮ 删除银行卡", acct.cards.count == 2, "count=\(acct.cards.count)")

print("\n── 15. 账单详情页（商户全称 / 支付时间）──")
let billDetail = """
支付成功
商户全称 上海巷鱼餐饮管理服务有限公司
商品 美团收银909700219151774435
支付方式 招商银行储蓄卡(4926)
支付时间 2026年11月13日 11:43:15
金额 ¥31.68
"""
let bd = BillParser.parse(billDetail).first
check("⑯ 商户取「商户全称」", bd?.merchant == "上海巷鱼餐饮管理服务有限公司", bd?.merchant ?? "nil")
check("⑰ 不会把字段名当商户", bd?.merchant != "全称" && bd?.merchant != "商户全称", bd?.merchant ?? "nil")
check("⑱ 使用支付时间而非当前时间",
      Calendar.current.component(.day, from: bd?.date ?? Date()) == 13,
      "\(String(describing: bd?.date))")
check("⑲ 尾号识别（储蓄卡(4926)）", bd?.account.contains("4926") == true, bd?.account ?? "nil")
check("⑳ 标记为支付时间", bd?.hasPaidTime == true, "\(String(describing: bd?.hasPaidTime))")

// 没有时间信息 → 用记账时间，标记 hasPaidTime = false
let noTime = BillParser.parse("微信支付 你已成功付款 18.00元").first
check("㉑ 无支付时间时用记账时间并标记", noTime?.hasPaidTime == false,
      "\(String(describing: noTime?.hasPaidTime))")

print("\n── 16. OCR 行序颠倒（值在标签上方）──")
// Vision 实际输出顺序：值在上、标签在下，且带状态栏时间
let ocrOrder = """
13:14
账单
美团
稻花驿时尚智选餐厅（黄兴路店）
-31.68
当前状态
支付成功
2026年11月13日11:43:15
支付时间
商户全称
上海巷鱼餐饮管理服务有限公司
支付方式
招商银行储蓄卡（4926）
"""
let oc = BillParser.parse(ocrOrder).first
check("㉒ 值在标签上方也能取到支付时间",
      Calendar.current.component(.day, from: oc?.date ?? Date()) == 13,
      "\(String(describing: oc?.date))")
check("㉓ 标记为支付时间", oc?.hasPaidTime == true, "\(String(describing: oc?.hasPaidTime))")
check("㉔ 不抓状态栏时间", Calendar.current.component(.hour, from: oc?.date ?? Date()) == 11,
      "\(String(describing: oc?.date))")

// 商户「值在标签上方」——系统 OCR 常见排布
let merchantAbove = """
13:14
账单
稻花驿时尚智选餐厅（黄兴路店）
-31.68
支付成功
2026年11月13日11:43:15
支付时间
上海巷鱼餐饮管理服务有限公司
商户全称
招商银行储蓄卡（4926）
支付方式
"""
let ma = BillParser.parse(merchantAbove).first
check("㉕ 商户值在上方也能取到", ma?.merchant == "上海巷鱼餐饮管理服务有限公司", ma?.merchant ?? "nil")
check("㉖ 分类推断为餐饮", ma?.category == .food, "\(String(describing: ma?.category))")
check("㉗ 支付方式尾号", ma?.account.contains("4926") == true, ma?.account ?? "nil")

print("\n── 17. 完整账单（含单号、退款说明）──")
let fullBill = """
账单
美团
稻花驿时尚智选餐厅（黄兴路店）
-31.68
当前状态
支付成功
2026年11月13日11:43:15
支付时间
商品
美团收银909700219151774435
上海巷鱼餐饮管理服务有限公司
商户全称
北京钱袋宝支付技术有限公司
收单机构
支付方式
招商银行储蓄卡（4926）
交易单号
4200003231202611130744450480
商户单号
可在支持商户扫码退款
"""
let fb = BillParser.parse(fullBill).first
check("㉘ 商户不取单号/退款说明", fb?.merchant == "上海巷鱼餐饮管理服务有限公司", fb?.merchant ?? "nil")
check("㉙ 分类为餐饮", fb?.category == .food, "\(String(describing: fb?.category))")

print("\n── 18. 同时有「商品」和「商户全称」时优先商户全称 ──")
let twoFields1 = """
支付宝 账单
-88.00
商品
美团收银12345678
商户全称
杭州知味观餐饮有限公司
支付时间
2026年11月12日18:20:05
"""
let mf1 = BillParser.parse(twoFields1).first
check("㉚ 商品在前也优先商户全称", mf1?.merchant == "杭州知味观餐饮有限公司", mf1?.merchant ?? "nil")
check("㉛ 分类为餐饮", mf1?.category == .food, "\(String(describing: mf1?.category))")

let twoFields2 = """
支付宝
-66.00
商户全称 深圳海底捞餐饮管理有限公司
商品 海底捞火锅
支付时间 2026年11月11日12:30:00
"""
let mf2 = BillParser.parse(twoFields2).first
check("㉜ 同行格式优先商户全称", mf2?.merchant == "深圳海底捞餐饮管理有限公司", mf2?.merchant ?? "nil")

print("\n── 19. 新场景：滴滴 / 交通卡 ──")
let didi = """
支付宝
-23.50
商品
先乘车后付款
商户全称
广州启安科技有限公司
支付时间
2026年11月12日08:15:00
"""
let d1 = BillParser.parse(didi).first
check("㉝ 滴滴商户取公司名", d1?.merchant == "广州启安科技有限公司", d1?.merchant ?? "nil")
check("㉞ 靠「乘车」判为交通", d1?.category == .transport, "\(String(describing: d1?.category))")

let metroCard = """
支付宝
-50.00
商品
上海交通卡自动续费
商户全称
上海公共交通卡股份有限公司
支付时间
2026年11月10日09:00:00
"""
let d2 = BillParser.parse(metroCard).first
check("㉟ 交通卡自动续费判为交通", d2?.category == .transport, "\(String(describing: d2?.category))")

// 商户记忆：用户教一次后自动沿用
Category.MerchantMemory.remember("广州启安科技有限公司", .transport)
check("㊱ 商户记忆生效",
      Category.guess(from: "随便什么文本", merchant: "广州启安科技有限公司") == .transport,
      "\(Category.guess(from: "x", merchant: "广州启安科技有限公司"))")

print("\n─────────────────────────────")
print("通过 \(pass) / \(pass + fail)")
exit(fail == 0 ? 0 : 1)
