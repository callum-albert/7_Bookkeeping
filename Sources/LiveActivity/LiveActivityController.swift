import Foundation
import ActivityKit
import UIKit
import Observation

/// 记账完成后点亮灵动岛
/// 注意：失败时不再静默，而是记录原因，设置页可查看诊断
@MainActor
@Observable
final class LiveActivityController {
    static let shared = LiveActivityController()

    private var current: Activity<BookkeepingAttributes>?

    /// 最近一次失败原因（给诊断用）
    private(set) var lastError: String?
    private(set) var lastResult: String?
    private(set) var lastAttempt: Date?

    private var userEnabled: Bool {
        UserDefaults.standard.object(forKey: "liveActivityEnabled") as? Bool ?? true
    }

    // MARK: - 诊断
    struct Diagnostics {
        var userEnabled: Bool
        var systemEnabled: Bool
        var appBundleID: String
        var widgetBundleIDs: [String]
        var activeCount: Int
        var lastError: String?
        var lastResult: String?

        var extensionInstalled: Bool { !widgetBundleIDs.isEmpty }

        /// 扩展 bundle id 必须是主 App 的前缀，否则系统不会加载它
        var prefixMatched: Bool {
            guard !widgetBundleIDs.isEmpty else { return false }
            return widgetBundleIDs.allSatisfy { $0.hasPrefix(appBundleID) }
        }

        var verdict: String {
            if !userEnabled { return "App 内「实时活动」开关被关闭" }
            if !systemEnabled { return "系统未允许实时活动（设置 → 7记账 → 实时活动）" }
            if !extensionInstalled { return "当前安装的包没有灵动岛扩展（可能装的是 LiveContainer 精简版）" }
            if !prefixMatched { return "扩展 bundle id 与主 App 不匹配，签名工具可能只改了主 App 的 id" }
            if let lastError { return lastError }
            return "配置正常"
        }
    }

    func diagnostics() -> Diagnostics {
        Diagnostics(
            userEnabled: userEnabled,
            systemEnabled: ActivityAuthorizationInfo().areActivitiesEnabled,
            appBundleID: Bundle.main.bundleIdentifier ?? "unknown",
            widgetBundleIDs: Self.widgetBundleIDs(),
            activeCount: Activity<BookkeepingAttributes>.activities.count,
            lastError: lastError,
            lastResult: lastResult
        )
    }

    static func widgetBundleIDs() -> [String] {
        guard let url = Bundle.main.builtInPlugInsURL,
              let items = try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: nil) else { return [] }
        return items
            .filter { $0.pathExtension == "appex" }
            .compactMap { Bundle(url: $0)?.bundleIdentifier }
    }

    static func infoValue(_ key: String) -> String? {
        guard let url = Bundle.main.builtInPlugInsURL,
              let items = try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: nil),
              let appex = items.first(where: { $0.pathExtension == "appex" }),
              let dict = NSDictionary(contentsOf: appex.appendingPathComponent("Info.plist"))
        else { return nil }
        return dict[key] as? String
    }

    // MARK: - 点亮
    @discardableResult
    func start(for entry: Entry, todayTotal: Int, auto: Bool) -> Bool {
        let balance = Self.balanceInfo(for: entry)
        lastAttempt = Date()

        guard userEnabled else {
            lastError = "App 内「实时活动」开关已关闭"
            return false
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastError = "系统未允许实时活动：设置 → 7记账 → 实时活动 → 允许"
            return false
        }
        let widgets = Self.widgetBundleIDs()
        guard !widgets.isEmpty else {
            lastError = "没有灵动岛扩展：当前安装的是无扩展版本"
            return false
        }

        if let current { Task { await current.end(nil, dismissalPolicy: .immediate) } }

        let state = BookkeepingAttributes.ContentState(
            amountText: entry.amountText,
            categoryTitle: entry.category.title,
            categorySymbol: entry.category.symbol,
            merchant: entry.merchant,
            sourceTitle: entry.source.title,
            totalTodayText: todayTotal.moneyText,
            timeText: entry.date.formatted(date: .omitted, time: .shortened),
            balanceText: balance.text,
            balanceLabel: balance.label,
            howText: auto ? "自动记账" : "手动记账"
        )

        // 后台（快捷指令触发）时保活，保证请求能完成
        var bgTask: UIBackgroundTaskIdentifier = .invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "LiveActivity") {
            if bgTask != .invalid { UIApplication.shared.endBackgroundTask(bgTask) }
        }
        defer {
            if bgTask != .invalid { UIApplication.shared.endBackgroundTask(bgTask) }
        }

        do {
            let activity = try Activity.request(
                attributes: BookkeepingAttributes(entryID: entry.id.uuidString),
                content: .init(state: state, staleDate: Date().addingTimeInterval(60)),
                pushType: nil
            )
            current = activity
            lastError = nil
            lastResult = "已创建（id 尾号 \(activity.id.suffix(6))）"

            // 锁屏横幅：手机上立刻能看到完整信息（灵动岛本体不会自动展开）
            Task {
                await activity.update(
                    ActivityContent(state: state, staleDate: Date().addingTimeInterval(70)),
                    alertConfiguration: AlertConfiguration(
                        title: "已记账 \(entry.amountText)",
                        body: "\(entry.category.title) · \(entry.merchant) · \(balance.label) \(balance.text)",
                        sound: .default
                    )
                )
            }
            if auto { UINotificationFeedbackGenerator().notificationOccurred(.success) }

            Task {
                try? await Task.sleep(for: .seconds(5))
                await activity.end(nil, dismissalPolicy: .after(.now + 1))
            }
            return true
        } catch {
            lastError = "创建失败：\(error.localizedDescription)"
            return false
        }
    }

    /// 这笔钱从哪个账户扣的、扣完还剩多少
    static func balanceInfo(for entry: Entry) -> (label: String, text: String) {
        let a = Accounts.shared
        switch entry.channel {
        case .wechatZero:
            return ("微信余额", a.wechat.moneyText)
        case .alipayBalance:
            return ("支付宝余额", a.alipay.moneyText)
        case .wechatCard, .alipayCard, .bank:
            let tail = Self.tail(from: entry.account)
            if let card = a.card(tail: tail), !card.tail.isEmpty {
                return (card.displayName, card.balanceCents.moneyText)
            }
            return ("银行卡", a.bankTotal.moneyText)
        case .huabei:
            return ("花呗", "信用消费")
        case .creditCard:
            return ("信用卡", "信用消费")
        case .unknown:
            return ("总余额", a.total.moneyText)
        }
    }

    private static func tail(from account: String) -> String {
        guard let r = account.range(of: #"\((\d{4})\)"#, options: .regularExpression) else { return "" }
        return String(account[r]).trimmingCharacters(in: CharacterSet(charactersIn: "()"))
    }

    func endAll() {
        Task {
            for a in Activity<BookkeepingAttributes>.activities {
                await a.end(nil, dismissalPolicy: .immediate)
            }
        }
        lastResult = nil
    }
}
