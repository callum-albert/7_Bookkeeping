# 7记账

一个运行在 iPhone 上的自动记账 App：原生 SwiftUI，iOS 26+ 液态玻璃设计，支持灵动岛实时活动、多银行卡余额管理、iCloud 同步。

重点解决两件事：**不多记**（跨渠道自动去重、转账/退款不入账）、**不漏记**（信息不全时标「待确认」而不是丢弃）。

---

## 功能

| 模块 | 说明 |
|---|---|
| 自动记账 | 银行短信 / 银行邮件 / 剪贴板，通过「快捷指令」自动化触发，无需打开 App |
| 手动记账 | 侧边按钮一键截图识别、轻点背面、App 内粘贴 / 截图 OCR |
| 解析引擎 | 微信支付、支付宝、花呗、余额宝、银行短信、手机银行、截图 OCR 文本 |
| 去重 | 同一笔消费多渠道来消息只记一次；手动与自动之间也会合并 |
| 余额 | 微信余额 / 支付宝余额 / 多张银行卡（精确到卡号），信贷不计入 |
| 统计 | 日 / 周 / 月 / 年，趋势曲线、分类排行、文字小结 |
| 灵动岛 | 紧凑显示金额，展开显示金额/分类/商户/余额/时间，锁屏完整卡片 |
| iCloud 备份 | 选一个 iCloud Drive 文件夹，自动上传，换机自动合并恢复 |

## 为什么不能直接读微信通知

iOS 沙盒不允许第三方 App 读取其它 App 的通知内容，这是系统级限制（非越狱无解）。所以自动记账基于**通知文本解析**，通过合法的系统入口获取数据：

| 通道 | 覆盖场景 | 需要设置 |
|---|---|---|
| 银行短信自动化 | 微信/支付宝绑卡支付、直接刷卡 | 一次性 |
| 银行邮件自动化 | 同上，且带完整商户名 | 一次性（需银行开通邮件提醒） |
| 剪贴板自动化 | 复制账单通知后自动入账 | 一次性 |
| 侧边按钮截图识别 | 微信零钱、支付宝余额等所有场景 | 一次性（2 个动作） |

微信/支付宝使用银行卡付款时银行也会发消息，所以前两条能覆盖绝大多数真实消费。

## 快捷指令

`tools/make_shortcuts.py` 可生成三个可直接导入的快捷指令文件（不入库，本地生成）：

```bash
python3 tools/make_shortcuts.py
```

| 文件 | 用途 |
|---|---|
| 侧边按钮 | 截屏 → 识别截图记账（设为「操作按钮」即可） |
| 剪贴板记账 | 读剪贴板 → 自动记账 |
| 账单文本记账 | 接收文本输入 → 解析记账（用于「信息」「电子邮件」自动化） |

> 「个人自动化」的触发器（收到短信 / 邮件 / App 关闭）无法通过文件分享，只能在手机上新建一次，
> 但动作直接选上述快捷指令即可，不需要自己搭动作。

## 安装

1. 从 [Releases](https://github.com/callum-albert/7_Bookkeeping/releases) 下载 `7jizhang.ipa`
   （GitHub 会过滤 Release 资产名里的非 ASCII 字符，所以文件名用拼音，App 显示名仍是「7记账」）
2. 用 SideStore / AltStore / 自有开发者证书签名安装
3. 主 App 与 `PlugIns/SevenWidgets.appex` 都需要签名（多数工具会自动递归）
4. 系统要求：iOS 26.0+

> 仓库中的 IPA 为 **ad-hoc 签名**，仅作为结构完整的占位，真机安装前需要用自己的证书重签。

## 从源码构建

构建不依赖 Xcode，只需要 macOS 命令行工具（含 Swift 6.4+）。

```bash
# 1) 下载 iOS SDK（约 53MB，脚本会自动分段加速下载）
./tools/fetch_sdk.sh

# 2) 构建
./build.sh
# 产物：7记账.ipa
```

构建脚本会：

- 编译主程序与灵动岛扩展（`arm64-apple-ios26.0`）
- 生成本地图标（`tools/make_icon.py`，优先使用 `tools/icon-source.png`）
- 写入 Info.plist、本地化名称
- ad-hoc 签名并打包 IPA

### 关于宏

Swift 6 起 `@State` / `@Binding` / `@Environment` 等是**宏**，需要 Xcode 随附的宏插件库，纯命令行环境里没有。本项目把它们展开成等价的属性包装器写法：

```swift
// 宏写法
@State private var count = 0

// 本项目写法（等价）
private var _count = State(wrappedValue: 0)
private var count: Int { get { _count.wrappedValue } nonmutating set { _count.wrappedValue = newValue } }
```

因此无需 Xcode 即可编译，运行时行为与原生一致。`@Observable` 使用了命令行工具自带的 Observation 宏插件，可正常使用。

## 去重规则

自动触发（短信/邮件/剪贴板）合并窗口 5 分钟；手动触发（侧边栏按钮/截图）30 分钟。

| 场景 | 结果 |
|---|---|
| 银行短信已记 → 按按钮截图 | 合并，补上商户名 |
| 按按钮记 → 银行短信后到 | 合并，补上卡尾号 |
| 连按两次按钮 | 只记一次 |
| 同金额、不同商户、都有商户名 | 两笔真实消费，都保留 |
| 提现 / 充值 / 还款 / 收款 / 退款 | 不入账，记入「已忽略」供复核 |

## 项目结构

```
Sources/
  App/            App 入口、URL Scheme
  Model/          数据模型、余额账户、本地存储、去重引擎、同步快照、统计
  Parser/         账单文本解析（微信 / 支付宝 / 银行短信 / OCR）
  Services/       自动记账调度、OCR、iCloud 备份
  Intents/        App Intents（快捷指令 / Siri / 操作按钮）
  LiveActivity/   实时活动数据与控制器
  Views/          首页、统计、记一笔、设置、余额管理、引导页
  Widget/         灵动岛 / 锁屏实时活动 UI
tools/            图标生成、解析测试、SDK 获取
build.sh          一键构建
```

## 测试

解析 / 去重 / 余额 / 同步逻辑有 60 个用例：

```bash
cd /tmp && mkdir -p ptest && cp Sources/Model/{Models,LedgerStore,Accounts,SyncPayload}.swift \
  Sources/Parser/BillParser.swift ptest/ && cp tools/ParserTests.swift ptest/main.swift
cd ptest && swiftc -O Models.swift LedgerStore.swift Accounts.swift SyncPayload.swift \
  BillParser.swift main.swift -o tests && ./tests
```

## License

MIT
