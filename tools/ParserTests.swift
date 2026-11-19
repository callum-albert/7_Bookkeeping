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
check("银行短信保留内部识别置信度",  b1?.needsReview == true && b1?.flow == .expense, "\(String(describing: b1))")

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
for card in acct.cards { acct.removeCard(id: card.id) }
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
check("⑯ 商户和商品分别保留", bd?.merchant == "上海巷鱼餐饮管理服务有限公司" && bd?.product == "美团收银909700219151774435", bd?.merchant ?? "nil")
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
check("㉘ 商户不取商品或收单机构", fb?.merchant == "上海巷鱼餐饮管理服务有限公司" && fb?.product == "美团收银909700219151774435", fb?.merchant ?? "nil")
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
check("㉚ 商户全称优先，商品单独保存", mf1?.merchant == "杭州知味观餐饮有限公司" && mf1?.product == "美团收银12345678", mf1?.merchant ?? "nil")
check("㉛ 分类为餐饮", mf1?.category == .food, "\(String(describing: mf1?.category))")

let twoFields2 = """
支付宝
-66.00
商户全称 深圳海底捞餐饮管理有限公司
商品 海底捞火锅
支付时间 2026年11月11日12:30:00
"""
let mf2 = BillParser.parse(twoFields2).first
check("㉜ 可读商品也不覆盖商户", mf2?.merchant == "深圳海底捞餐饮管理有限公司" && mf2?.product == "海底捞火锅", mf2?.merchant ?? "nil")

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
check("㉝ 滴滴商户与服务分开", d1?.merchant == "广州启安科技有限公司" && d1?.product == "先乘车后付款", d1?.merchant ?? "nil")
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

print("\n── 20. 支付宝/微信账单详情页模板 ──")
let alipayDetail = """
14:30
交易详情
门店
-27.60
小女当家
当前状态    支付成功
支付时间    2026年11月09日 11:47:09
商品        【POS】_上海互联宝地店_567850
商户全称    当家食力鲜厨（上海）餐饮有限公司
收单机构    财付通支付科技有限公司
支付方式    招商银行储蓄卡(4926)
交易单号    4200003227202611094941731436
商户单号    可在支持的商户扫码退款
T1326517543793922050
交易服务
对订单有疑惑
发起群收款
在此商户的交易
申请电子凭证
"""
let ad = BillParser.parse(alipayDetail).first
check("㊲ 模板：商户独立于POS商品", ad?.merchant == "当家食力鲜厨(上海)餐饮有限公司" && ad?.product == "【POS】_上海互联宝地店_567850", ad?.merchant ?? "nil")
check("㊳ 模板：支付时间正确",
      Calendar.current.component(.day, from: ad?.date ?? Date()) == 9, "\(String(describing: ad?.date))")
check("㊴ 模板：支付时间不被标成记账时间", ad?.hasPaidTime == true, "\(String(describing: ad?.hasPaidTime))")
check("㊵ 模板：支付方式尾号", ad?.account.contains("4926") == true, ad?.account ?? "nil")
check("㊶ 模板：金额", ad?.amountCents == 2760, "\(String(describing: ad?.amountCents))")
check("㊷ 模板：分类餐饮", ad?.category == .food, "\(String(describing: ad?.category))")
check("㊸ 模板：来源不是「交易」", ad?.merchant != "交易", ad?.merchant ?? "nil")

print("\n── 21. 视觉行格式（标签+值在同一行）──")
let visualLines = """
14:30  交易详情  门店
27.60
小女当家
当前状态  支付成功
支付时间  2026年11月09日 11:47:09
商品  【POS】_上海互联宝地店_567850
商户全称  当家食力鲜厨（上海）餐饮有限公司
收单机构  财付通支付科技有限公司
支付方式  招商银行储蓄卡(4926)
交易单号  4200003227202611094941731436
商户单号  可在支持的商户扫码退款
交易服务
对订单有疑惑  发起群收款
在此商户的交易  申请电子凭证
"""
let vl = BillParser.parse(visualLines).first
check("㊹ 视觉行：商户独立于POS商品", vl?.merchant == "当家食力鲜厨(上海)餐饮有限公司" && vl?.product == "【POS】_上海互联宝地店_567850", vl?.merchant ?? "nil")
check("㊺ 视觉行：来源不是「的交易」", (vl?.merchant ?? "").contains("的交易") == false, vl?.merchant ?? "nil")
check("㊻ 视觉行：时间正确", Calendar.current.component(.day, from: vl?.date ?? Date()) == 9,
      "\(String(describing: vl?.date))")
check("㊼ 视觉行：支付方式尾号", vl?.account.contains("4926") == true, vl?.account ?? "nil")
check("㊽ 视觉行：分类餐饮", vl?.category == .food, "\(String(describing: vl?.category))")

print("\n── 22. 房租 / 水电分类 ──")
let rentBill = """
微信支付
-3500.00
当前状态  支付成功
支付时间  2026年11月01日 10:00:00
商品  房租
商户全称  链家房屋租赁有限公司
支付方式  招商银行储蓄卡(4926)
"""
let rb = BillParser.parse(rentBill).first
check("㊾ 房租识别", rb?.category == .rent, "\(String(describing: rb?.category))")
check("㊿ 房租保留商户和商品", rb?.merchant == "链家房屋租赁有限公司" && rb?.product == "房租", rb?.merchant ?? "nil")

let utilBill = """
支付宝
-268.50
当前状态  支付成功
支付时间  2026年11月05日 09:30:00
商品  电费
商户全称  国家电网上海市电力公司
支付方式  余额宝
"""
let ub = BillParser.parse(utilBill).first
check("51 水电识别", ub?.category == .utilities, "\(String(describing: ub?.category))")

// 微信账单缺少「当前状态」也要能走模板
let wechatNoStatus = """
微信支付
-35.00
星巴克咖啡（上海）有限公司
支付时间  2026年11月10日 08:05:00
商户全称  星巴克咖啡（上海）有限公司
支付方式  招商银行储蓄卡(4926)
交易单号  4200003227202611094941731436
"""
let wb = BillParser.parse(wechatNoStatus).first
check("52 无「当前状态」也走模板", wb?.merchant == "星巴克咖啡(上海)有限公司", wb?.merchant ?? "nil")
check("53 分类餐饮", wb?.category == .food, "\(String(describing: wb?.category))")
check("54 来源不是银行卡", wb?.merchant != "银行卡", wb?.merchant ?? "nil")

print("\n── 23. 真实错账模式回归（模拟文本，非用户截图）──")
let receipt = """
微信支付
账单详情
-1,234.50
当前状态 支付成功
商户全称 星巴克咖啡上海有限公司
商品名称 咖啡豆礼盒
支付方式 零钱通
支付时间 2026/11/13 11:43:15
交易单号 4200003231202611130744450480
优惠金额 9.00
"""
let r = BillParser.parse(receipt).first
check("千分位金额不被优惠覆盖", r?.amountCents == 123450)
check("零钱通不是转账", r?.flow == .expense && r?.channel == .wechatZero)
check("商品独立保留", r?.product == "咖啡豆礼盒")
check("斜线日期带秒可识别", r?.hasPaidTime == true)
check("字段完整无需确认", r?.needsReview == false)

let actual = BillParser.parse(receipt + "\n实付金额 1,220.50").first
check("实付优先于原价", actual?.amountCents == 122050)
let integer = BillParser.parse(receipt + "\n实付金额 1200").first
check("显式实付字段支持整数", integer?.amountCents == 120000)
let missingAmount = receipt.replacingOccurrences(of: "-1,234.50\n", with: "")
check("缺主金额时不把优惠记成消费", BillParser.parse(missingAmount).isEmpty)
let missingTime = BillParser.parse(receipt.replacingOccurrences(of: "支付时间 2026/11/13 11:43:15", with: "13:14")).first
check("状态栏时间不冒充支付时间", missingTime?.hasPaidTime == false && missingTime?.needsReview == true)
let refund = BillParser.parse(receipt.replacingOccurrences(of: "当前状态 支付成功", with: "当前状态 已全额退款")).first
check("退款详情不回退为消费", refund?.flow == .income)
check("待付款不入账", BillParser.parse(receipt.replacingOccurrences(of: "支付成功", with: "待付款")).isEmpty)
check("支付失败不入账", BillParser.parse(receipt.replacingOccurrences(of: "支付成功", with: "支付失败")).isEmpty)
let topup = BillParser.parse(receipt.replacingOccurrences(of: "咖啡豆礼盒", with: "零钱充值")).first
check("支付成功的内部充值也不算消费", topup?.flow == .transfer)
let balance = BillParser.parse(receipt.replacingOccurrences(of: "微信支付", with: "支付宝").replacingOccurrences(of: "零钱通", with: "余额")).first
check("支付宝余额渠道", balance?.channel == .alipayBalance && balance?.account == "余额")

let createdFirst = """
支付宝
-26.00
创建时间 2026-11-12 10:00:00
付款时间 2026-11-13 11:43:15
商家名称 瑞幸咖啡
商品说明 生椰拿铁
付款方式 花呗
"""
let cf = BillParser.parse(createdFirst).first
check("付款时间优先于创建时间", Calendar.current.component(.day, from: cf?.date ?? base) == 13)
check("支付宝同义字段", cf?.merchant == "瑞幸咖啡" && cf?.product == "生椰拿铁" && cf?.channel == .huabei)
let alipayOrder = BillParser.parse(createdFirst + "\n商户单号 123456789012").first
check("支付宝不因商户单号误判为微信", alipayOrder?.source == .alipay)
let successOnly = BillParser.parse("微信支付\n支付成功\n¥32.00\n星巴克\n优惠金额 5.00\n完成")
check("简单成功页只记主金额", successOnly.count == 1 && successOnly.first?.amountCents == 3200)
check("简单成功页商户和缺失字段", successOnly.first?.merchant == "星巴克" && successOnly.first?.needsReview == true)

print("\n── 24. OCR 几何行序与多行字段 ──")
func box(_ x: Double, _ y: Double, _ text: String, _ height: Double = 0.018) -> OCRLayout.Item {
    OCRLayout.Item(rect: CGRect(x: x, y: y, width: 0.25, height: height), text: text)
}
let layout = OCRLayout.text(from: [
    box(0.1, 0.85, "-27.60", 0.035),
    box(0.1, 0.70, "商户全称"), box(0.5, 0.695, "上海星巴克"),
    box(0.5, 0.671, "咖啡有限公司"),
    box(0.1, 0.62, "支付方式"), box(0.5, 0.616, "零钱"),
    box(0.1, 0.56, "支付时间"), box(0.5, 0.557, "2026-11-13 11:43:15")
])
let geom = BillParser.parse(layout).first
check("轻微基线偏移仍配对标签和值", layout.contains("商户全称  上海星巴克"), layout)
check("多行商户合并且不串支付方式", geom?.merchant == "上海星巴克 咖啡有限公司", geom?.merchant ?? "nil")
check("几何版式保留支付渠道和日期", geom?.channel == .wechatZero && geom?.hasPaidTime == true)
let closeRows = OCRLayout.text(from: [box(0.1, 0.7, "支付方式", 0.01), box(0.1, 0.69, "支付时间", 0.01)])
check("短行距不会串成一行", closeRows.components(separatedBy: .newlines).count == 2)
let wrappedTime = OCRLayout.text(from: [
    box(0.1, 0.8, "-20.00"), box(0.1, 0.7, "支付时间"),
    box(0.5, 0.7, "2026-11-13"), box(0.5, 0.67, "11:43:15"),
    box(0.1, 0.6, "支付方式"), box(0.5, 0.6, "零钱")
])
check("右栏换行时间可还原", BillParser.parse(wrappedTime).first?.hasPaidTime == true, wrappedTime)

print("\n── 25. 商品兼容、去重、持久化 ──")
let saved = Entry(amountCents: 2760, date: base, category: .food, merchant: "咖啡店", source: .wechat, product: "咖啡豆")
let encoded = try! JSONEncoder().encode(saved)
let decoded = try! JSONDecoder().decode(Entry.self, from: encoded)
check("商品字段JSON往返保留", decoded.product == "咖啡豆")
var oldJSON = try! JSONSerialization.jsonObject(with: encoded) as! [String: Any]
oldJSON.removeValue(forKey: "product")
oldJSON.removeValue(forKey: "transactionID")
let legacy = try! JSONDecoder().decode(Entry.self, from: JSONSerialization.data(withJSONObject: oldJSON))
check("旧账本无商品字段也能读取", legacy.product.isEmpty)
check("旧账本无交易单号字段也能读取", legacy.transactionID.isEmpty)
let reviewStore = LedgerStore()
var reviewA = mk(9876, .wechat, "甲咖啡店", .wechatZero, base, true)
reviewA.needsReview = true
var reviewB = mk(9876, .wechat, "乙咖啡店", .wechatZero, base, true)
reviewB.needsReview = true
let beforeReview = reviewStore.entries.count
_ = reviewStore.ingest(reviewA)
_ = reviewStore.ingest(reviewB)
check("低置信度的不同商户不误合并",  reviewStore.entries.count == beforeReview + 2)
var otherPlatform = reviewA
otherPlatform.source = .alipay
_ = reviewStore.ingest(otherPlatform)
check("微信支付宝分别消费不误合并", reviewStore.entries.count == beforeReview + 3)
if let r { _ = reviewStore.ingest(r) }
check("识别商品写入账本", reviewStore.entries.contains { $0.product == "咖啡豆礼盒" })

var txnA = mk(5555, .wechat, "同店咖啡", .wechatZero, base, false)
txnA.transactionID = "transaction0001"
var txnB = txnA
txnB.transactionID = "transaction0002"
let beforeTransactions = reviewStore.entries.count
_ = reviewStore.ingest(txnA)
_ = reviewStore.ingest(txnB)
check("同店同金额但单号不同保留两笔", reviewStore.entries.count == beforeTransactions + 2)
txnA.date = base.addingTimeInterval(86400)
_ = reviewStore.ingest(txnA)
check("同单号隔天重识别也不重复扣款", reviewStore.entries.count == beforeTransactions + 2)
print("\n── 收入、退款、双入口银行卡和自定义分类 ──")
let wageText = "【招商银行】您尾号8201账户于11月15日12:30工资入账5000.00元，余额8000.00元"
let wage = BillParser.parse(wageText, now: base).first!
check("银行入账识别收入及工资分类", wage.flow == .income && wage.category == .salary && wage.amountCents == 500000)
check("入账短信提取银行和尾号", wage.account == "招商银行(8201)")
let incomeStore = LedgerStore()
let wageCount = incomeStore.entries.count
_ = incomeStore.ingest(wage, trigger: .automatic)
check("自动收入短信添加新卡", acct.cards.contains { $0.bankName == "招商银行" && $0.tail == "8201" })
check("入账余额按短信校准", acct.card(tail: "8201", bankName: "招商银行")?.balanceCents == 800000)
_ = incomeStore.ingest(wage, trigger: .manual)
check("收入重复记账不增账不增余额", incomeStore.entries.count == wageCount + 1 && acct.card(tail: "8201", bankName: "招商银行")?.balanceCents == 800000)

let redPacket = """
微信红包
+8.88
当前状态 已领取
收款时间 2026-11-15 12:40:30
付款方 张先生
收款方式 零钱
交易单号 1000000000000000888
"""
let rp = BillParser.parse(redPacket, now: base).first!
check("按键截图文本识别红包收入", rp.kind == .income && rp.category == .redPacket && rp.channel == .wechatZero && rp.amountCents == 888)
let wechatBeforeIncome = acct.wechat
_ = incomeStore.ingest(rp, trigger: .manual)
_ = incomeStore.ingest(rp, trigger: .manual)
check("红包重复识别只加一次余额", acct.wechat == wechatBeforeIncome + 888)
if let entry = incomeStore.entries.first(where: { $0.transactionID == rp.transactionID }) {
    incomeStore.delete(entry)
    check("删除收入撤回余额增加", acct.wechat == wechatBeforeIncome)
} else { check("删除收入撤回余额增加", false) }

let alipayReceipt = redPacket.replacingOccurrences(of: "微信红包", with: "支付宝 转账收款").replacingOccurrences(of: "已领取", with: "收款成功").replacingOccurrences(of: "零钱", with: "余额")
let ar = BillParser.parse(alipayReceipt).first!
check("支付宝转账收款识别收入", ar.flow == .income && ar.category == .receivedTransfer && ar.channel == .alipayBalance)
check("付款方不会误匹配付款方式", ar.merchant == "张先生")
check("待领取红包不入账", BillParser.parse(redPacket.replacingOccurrences(of: "已领取", with: "待领取")).isEmpty)
check("未到账提示不入账", BillParser.parse("招商银行 预计入账100.00元，暂未到账").isEmpty)
check("自己账户互转不算收入", BillParser.classify("招商银行 本人账户转入100.00元") == .transfer)

var outgo = mk(2222, .wechat, "退款商户", .wechatZero, base, false)
outgo.transactionID = "sameOrderForRefund"
var moneyBack = outgo
moneyBack.flow = .income; moneyBack.category = .refund
let countBeforeRefund = incomeStore.entries.count
_ = incomeStore.ingest(outgo)
_ = incomeStore.ingest(moneyBack)
_ = incomeStore.ingest(moneyBack)
check("原消费与同单号退款各记一次", incomeStore.entries.count == countBeforeRefund + 2)
check("退款单独标注收入", incomeStore.entries.contains { $0.transactionID == moneyBack.transactionID && $0.kind == .income && $0.category == .refund })

let screenshotCard = """
微信支付
-17.28
当前状态 支付成功
商户全称 咖啡店
商品 咖啡
支付时间 2026-11-15 12:00:00
支付方式 建设银行储蓄卡(8202)
交易单号 44444444444444448202
"""
let sc = BillParser.parse(screenshotCard).first!
_ = incomeStore.ingest(sc, trigger: .manual)
check("手动按键OCR也自动添加银行卡", acct.cards.contains { $0.bankName == "建设银行" && $0.tail == "8202" })
let screenshotCardCount = acct.cards.count
_ = incomeStore.ingest(sc, trigger: .manual)
check("重复按键不会重复添加卡", acct.cards.count == screenshotCardCount)
_ = acct.upsertCard(bankName: "工商银行", tail: "8202")
check("不同银行同尾号不合并", acct.cards.filter { $0.tail == "8202" }.count == 2)
acct.applyBankBalance(45000, tail: "8202", bankName: "工商银行")
check("同尾号校准不串卡", acct.card(tail: "8202", bankName: "工商银行")?.balanceCents == 45000 && acct.card(tail: "8202", bankName: "建设银行")?.balanceCents == -1728)
check("完整卡号只保存正确末四位", BillParser.extractAccount("招商银行储蓄卡 6214 8300 0012 3456", source: .wechat) == "招商银行(3456)")
check("掩码卡号不会取前四位", BillParser.extractAccount("招商银行 卡号6214**** 8203", source: .bank) == "招商银行(8203)")
let duplicateTxn = incomeStore.entries.count
var timedA = mk(1122, .wechat, "相同商户", .wechatZero, base, false)
timedA.hasPaidTime = true
var timedB = timedA; timedB.date = base.addingTimeInterval(10)
timedA.raw = "交易时间 2026-11-15 12:00:01"
timedB.raw = "交易时间 2026-11-15 12:00:11"
_ = incomeStore.ingest(timedA); _ = incomeStore.ingest(timedB)
check("同店同金额不同真实支付时间保留两笔", incomeStore.entries.count == duplicateTxn + 2)

let categoryStore = CategoryStore.shared
let custom = categoryStore.add("项目测试收入", kind: .income)!
check("自定义收入分类可添加", Category.choices(for: .income).contains(custom))
Category.MerchantMemory.remember("张先生", custom)
check("收入可沿用用户自定义分类", BillParser.parse(redPacket).first?.category == custom)
check("同类型分类不可重名", categoryStore.add("项目测试收入", kind: .income) == nil)
check("旧分类字符串仍兼容解码", (try? JSONDecoder().decode(Category.self, from: Data("\"food\"".utf8))) == .food)
let categoryJSON = try! JSONEncoder().encode(custom)
check("自定义分类JSON保留名称", (try? JSONDecoder().decode(Category.self, from: categoryJSON))?.title == "项目测试收入")
categoryStore.remove(custom)
check("删除分类同时停止自动沿用", Category.MerchantMemory.category(for: "张先生") == nil)
check("删除后从新账目选择中移除", !Category.allCases.contains(custom))
check("删除分类不改变历史名称", custom.title == "项目测试收入")
categoryStore.merge([custom], deleted: [])
check("旧备份不复活已删除分类", !categoryStore.categories.contains(custom))
let oldEntry = try! JSONDecoder().decode(Entry.self, from: JSONSerialization.data(withJSONObject: oldJSON))
check("旧账目缺收支类型默认支出", oldEntry.kind == .expense)
let range = DateInterval(start: base.addingTimeInterval(-86400 * 370), end: base.addingTimeInterval(86400 * 370))
let expenseSum = incomeStore.entries(in: range).filter { $0.kind == .expense }.reduce(0) { $0 + $1.amountCents }
let incomes = incomeStore.entries(in: range).filter { $0.kind == .income }.reduce(0) { $0 + $1.amountCents }
check("支出统计不混入收入", incomeStore.summary(in: range).total == expenseSum)
check("收入统计独立计算", incomeStore.summary(in: range, kind: .income).total == incomes)
let splitCompanyReceipt = screenshotCard.replacingOccurrences(of: "商户全称 咖啡店", with: "商户全称 示例科技有限公\n司")
check("历史OCR拆行公司后缀可恢复", BillParser.parse(splitCompanyReceipt).first?.merchant == "示例科技有限公司")
let legacyCompanyEntry = Entry(amountCents: 1728, date: base, category: .digital,
    merchant: "示例科技有限公", source: .wechat, raw: splitCompanyReceipt.replacingOccurrences(of: "-17.28\n", with: ""))
incomeStore.add(legacyCompanyEntry)
let reloadedIncomeStore = LedgerStore()
check("旧账目按原始文本恢复公司名", reloadedIncomeStore.entries.first { $0.id == legacyCompanyEntry.id }?.merchant == "示例科技有限公司")
let partialRefund = screenshotCard.replacingOccurrences(of: "当前状态 支付成功", with: "当前状态 退款成功") + "\n退款金额 2.28\n退款时间 2026-11-15 13:10:20"
let pr = BillParser.parse(partialRefund).first
check("部分退款取退款金额而非原消费额", pr?.amountCents == 228 && pr?.kind == .income && pr?.category == .refund)
var incomplete = mk(1231, .wechat, "某商户", .unknown, base, true)
incomplete.transactionID = "enrichment0000001"
_ = incomeStore.ingest(incomplete)
let beforeEnrichment = incomeStore.entries.count
var improved = incomplete
improved.merchant = "某商户有限公司"; improved.account = "杭州银行(8210)"; improved.channel = .bank; improved.needsReview = false
_ = incomeStore.ingest(improved, trigger: .manual)
check("相同单号补全信息不重复新增", incomeStore.entries.count == beforeEnrichment && incomeStore.entries.first { $0.transactionID == improved.transactionID }?.merchant == improved.merchant)
check("判重分支也添加新识别的卡", acct.card(tail: "8210", bankName: "杭州银行") != nil)
let backedCategory = categoryStore.add("专项报销", kind: .income)!
let snapshotWithCategory = incomeStore.exportPayload()
check("自定义分类包含在同步快照", snapshotWithCategory.customCategories?.contains(backedCategory) == true)
categoryStore.remove(backedCategory)
_ = incomeStore.mergeRemote(snapshotWithCategory)
check("同步旧快照不复活已删分类", !categoryStore.categories.contains(backedCategory))
let beforePrefixMerchants = incomeStore.entries.count
let prefixMerchantA = mk(4321, .bank, "上海巷鱼餐厅", .bank, base, true)
let prefixMerchantB = mk(4321, .bank, "上海巷鱼超市", .bank, base, true)
_ = incomeStore.ingest(prefixMerchantA); _ = incomeStore.ingest(prefixMerchantB)
check("同银行同金额商户前四字相同不误合并", incomeStore.entries.count == beforePrefixMerchants + 2)
let midnightEntry = Entry(amountCents: 123, date: range.end, category: .food, merchant: "边界测试", source: .manual)
incomeStore.add(midnightEntry)
check("日期区间不重复统计下个周期零点", !incomeStore.entries(in: range).contains { $0.id == midnightEntry.id })
let beforeBankTimes = incomeStore.entries.count
var bankTimeA = timedA; bankTimeA.source = .bank; bankTimeA.amountCents = 6789
var bankTimeB = timedB; bankTimeB.source = .bank; bankTimeB.amountCents = 6789
_ = incomeStore.ingest(bankTimeA); _ = incomeStore.ingest(bankTimeB)
check("银行同商户同金额但秒级时间不同保留两笔", incomeStore.entries.count == beforeBankTimes + 2)
let minuteStart = Calendar.current.dateInterval(of: .minute, for: base)!.start
var minuteBill = mk(6790, .bank, "同一分钟商户", .bank, minuteStart, false)
minuteBill.hasPaidTime = true; minuteBill.raw = "交易时间 12:00"
var secondBill = minuteBill; secondBill.date = minuteStart.addingTimeInterval(30); secondBill.raw = "交易时间 12:00:30"
let beforeMinuteMerge = incomeStore.entries.count
_ = incomeStore.ingest(minuteBill); _ = incomeStore.ingest(secondBill)
check("缺秒的短信与同分钟截图仍合并", incomeStore.entries.count == beforeMinuteMerge + 1)
check("收款时间不被当作收入金额", BillParser.extractAmount("收款时间2026年11月15日12:30:00") == nil)
check("支付方式卡尾号不被当作金额", BillParser.extractAmount("支付方式 卡(4926)") == nil)
check("入账日期不被当作金额", BillParser.extractAmount("招商银行入账于11月15日，金额100元") == 10000)
check("点号日期不是小数金额", BillParser.extractAmount("2026.11.15") == nil)
let simpleIncome = BillParser.parse("支付宝\n收款成功\n+20.00\n张先生\n收款时间 2026-11-15 13:30:10").first
check("简化收款成功页也记为收入", simpleIncome?.kind == .income && simpleIncome?.amountCents == 2000 && simpleIncome?.merchant == "张先生")

// 余额回归：统一 CRUD、负数可逆、转账守恒和持久化基准。
let auditStore = LedgerStore()
acct.setAll(wechat: 10000, alipay: 20000, bank: acct.cards.first?.balanceCents ?? 0)
for card in acct.cards where card.balanceCents < 0 { acct.setCardBalance(id: card.id, cents: 0) }
auditStore.confirmBalanceBaseline()
let beforeTransferTotal = acct.total
check("本人转账成功", auditStore.transfer(from: "wechat", to: "alipay", cents: 3000, fee: 10, reference: "test-transfer"))
check("转账两端余额及手续费", acct.wechat == 6990 && acct.alipay == 23000 && acct.total == beforeTransferTotal - 10)
check("转账不计入收支", !auditStore.entries.contains { $0.transactionID == "test-transfer" })
check("重复转账不重复扣款", !auditStore.transfer(from: "wechat", to: "alipay", cents: 3000, reference: "test-transfer") && acct.wechat == 6990)
check("拒绝同账户转账", !auditStore.transfer(from: "wechat", to: "wechat", cents: 100))
check("拒绝不存在账户", !auditStore.transfer(from: "wechat", to: "missing", cents: 100))
check("转账后核对无差异", auditStore.balanceWarnings.isEmpty)
var editable = Entry(amountCents: 8000, date: Date(), category: .food, merchant: "余额回归", source: .manual, needsReview: true, channel: .wechatZero)
auditStore.add(editable)
check("扣款不截零掩盖负余额", acct.wechat == -1010 && !auditStore.balanceWarnings.isEmpty)
editable.amountCents = 1000
editable.channel = .alipayBalance
auditStore.update(editable)
check("修改金额及账户正确还原旧余额", acct.wechat == 6990 && acct.alipay == 22000)
check("信息不全的账目直接入账且不要求确认", auditStore.entries.contains { $0.id == editable.id && !$0.needsReview })
editable.needsReview = false
auditStore.update(editable)
check("编辑账目不会创建确认状态", auditStore.entries.first { $0.id == editable.id }?.needsReview == false)
auditStore.delete(editable)
auditStore.delete(editable)
check("重复删除不会多退余额", acct.wechat == 6990 && acct.alipay == 23000)
acct.setBalance(9999, for: .wechat)
auditStore.checkBalances()
check("手动余额差异保留异常提示",  auditStore.balanceWarnings.contains { $0.contains("差额") })
// 模拟旧版本已落盘的待确认状态，升级后必须清除且不改变账单或余额。
var legacyEntries = auditStore.entries
legacyEntries[0].needsReview = true
try! JSONEncoder().encode(legacyEntries).write(to: LedgerStore.storageDirectory.appendingPathComponent("ledger.json"))
let beforeMigrationBalance = acct.total
let auditReload = LedgerStore()
check("升级清除旧账单确认状态且不改变余额", auditReload.entries.allSatisfy { !$0.needsReview } && acct.total == beforeMigrationBalance)
var remoteReviewEntry = Entry(amountCents: 55, date: Date(), category: .other, merchant: "旧备份测试", source: .bank, needsReview: true)
var reviewPayload = auditReload.exportPayload()
reviewPayload.entries = [remoteReviewEntry]
_ = auditReload.mergeRemote(reviewPayload)
check("旧备份不会恢复账单确认机制", auditReload.entries.first { $0.id == remoteReviewEntry.id }?.needsReview == false)
check("冷启动恢复转账及差异基准", auditReload.transfers.contains { $0.reference == "test-transfer" } && !auditReload.balanceWarnings.isEmpty)
auditReload.confirmBalanceBaseline()
check("核对后新基准清除差异", auditReload.balanceWarnings.isEmpty)

var withdrawal = mk(500, .wechat, "零钱提现", .wechatZero, Date(), false)
withdrawal.flow = .transfer
withdrawal.raw = "微信零钱提现 招商银行(8201) 到账金额5.00元"
withdrawal.account = "招商银行(8201)"
withdrawal.transactionID = "withdrawal-regression"
let walletBeforeWithdrawal = acct.wechat
let cardBeforeWithdrawal = acct.card(tail: "8201", bankName: "招商银行")!.balanceCents
_ = auditReload.ingest(withdrawal)
check("明确提现自动调整两端", acct.wechat == walletBeforeWithdrawal - 500 && acct.card(tail: "8201", bankName: "招商银行")?.balanceCents == cardBeforeWithdrawal + 500)
_ = auditReload.ingest(withdrawal)
check("重复提现不重复调整余额", acct.wechat == walletBeforeWithdrawal - 500)
withdrawal.transactionID = "withdrawal-fee-regression"
withdrawal.raw += " 手续费0.10元"
let unresolvedCount = auditReload.ignored.count
_ = auditReload.ingest(withdrawal)
check("手续费不明确转待核对不猜金额", acct.wechat == walletBeforeWithdrawal - 500 && auditReload.ignored.count == unresolvedCount + 1)
_ = auditReload.ingest(withdrawal)
check("重复未处理资金流动去重", auditReload.ignored.count == unresolvedCount + 1)

print("\n─────────────────────────────")
print("通过 \(pass) / \(pass + fail)")
exit(fail == 0 ? 0 : 1)
