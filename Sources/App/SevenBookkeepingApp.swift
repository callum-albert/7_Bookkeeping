import SwiftUI

@main
struct SevenBookkeepingApp: App {
    private var _scenePhase = Environment(\.scenePhase)
    private var scenePhase: ScenePhase { _scenePhase.wrappedValue }

    init() {
        // 让浮层玻璃更通透
        UIView.appearance().tintColor = UIColor(Theme.brand)
        // 提前初始化同步服务，保证记账后自动备份生效
        _ = BackupService.shared
        UpdateChecker.shared.checkIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        LiveActivityController.shared.flushPending()
                        BackupService.shared.pullIfNeeded()
                    } else if newPhase == .background {
                        Task { await BackupService.shared.backupNow() }
                    }
                }
                .onOpenURL { url in
                    handle(url)
                }
        }
    }

    /// 快捷指令 / 其他 App 可通过 URL Scheme 直接入账
    /// seven7://record?text=<urlencoded>
    /// seven7://record?amount=25.5&merchant=星巴克&category=food
    private func handle(_ url: URL) {
        guard url.scheme == "seven7" else { return }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = comps?.queryItems ?? []
        func value(_ key: String) -> String? { items.first { $0.name == key }?.value }

        if let text = value("text") {
            _ = AutoBookkeeper.shared.ingest(text, source: "URL")
            return
        }
        if let amountStr = value("amount"), let amount = Double(amountStr) {
            AutoBookkeeper.shared.addManual(
                amountCents: Int((amount * 100).rounded()),
                category: Category(rawValue: value("category") ?? "") ?? .other,
                merchant: value("merchant") ?? "",
                note: value("note") ?? "",
                date: Date()
            )
        }
    }
}
