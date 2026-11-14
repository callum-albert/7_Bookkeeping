import Foundation
import UserNotifications
import Observation

/// 记账完成后的本地通知
/// 覆盖所有场景：短信自动化（后台）、剪贴板、手动、App 内记账
@MainActor
@Observable
final class NotificationService {
    static let shared = NotificationService()

    private(set) var authorized = false
    private var didRequest = false

    var enabled: Bool {
        UserDefaults.standard.object(forKey: "notifyOnRecord") as? Bool ?? true
    }

    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: "notifyOnRecord")
    }

    func refreshStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorized = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    /// 首次进入 App 时请求权限（后台触发记账前必须先有权限）
    func requestIfNeeded() async {
        guard !didRequest else { return }
        didRequest = true
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
        await refreshStatus()
    }

    func notify(entry: Entry, balanceLabel: String, balanceText: String) {
        guard enabled, authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "已记账 \(entry.amountText)"
        var parts = [entry.category.title, entry.merchant]
        if !balanceLabel.isEmpty {
            parts.append("\(balanceLabel) \(balanceText)")
        }
        content.body = parts.joined(separator: " · ")
        content.sound = .default
        if entry.channel.isCredit {
            content.subtitle = "信贷支付"
        }

        let request = UNNotificationRequest(
            identifier: "record-\(entry.id.uuidString)",
            content: content,
            trigger: nil            // 立即送达
        )
        UNUserNotificationCenter.current().add(request)
    }
}
