import Foundation
import AppIntents
import UIKit
import Photos

// MARK: - 解析文本记账（给快捷指令/自动化用）
struct RecordFromTextIntent: AppIntent {
    static var title: LocalizedStringResource = "解析账单文本记账"
    static var description = IntentDescription("把微信/支付宝的账单文本交给 7记账 自动识别并入账")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "账单文本", description: "例如：微信支付 你已成功付款 25.00元")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("解析 \(\.$text)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // 不返回 dialog：避免快捷指令弹出「完成」对话框，结果通过灵动岛/通知呈现
        let entries = AutoBookkeeper.shared.ingest(text, source: "快捷指令", trigger: .manual)
        let total = entries.reduce(0) { $0 + $1.amountCents }
        return .result(value: entries.isEmpty ? "0" : total.moneyText)
    }
}

// MARK: - 读剪贴板记账
struct ParseClipboardIntent: AppIntent {
    static var title: LocalizedStringResource = "从剪贴板自动记账"
    static var description = IntentDescription("读取剪贴板里的微信/支付宝账单并自动入账")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let text = UIPasteboard.general.string ?? ""
        guard !text.isEmpty else { return .result(value: "0", dialog: "剪贴板是空的") }
        let entries = AutoBookkeeper.shared.ingest(text, source: "快捷指令·剪贴板", trigger: .manual)
        guard !entries.isEmpty else { return .result(value: "0", dialog: "剪贴板里没有可识别的账单") }
        let total = entries.reduce(0) { $0 + $1.amountCents }
        return .result(value: total.moneyText, dialog: "已记 \(entries.count) 笔，共 \(total.moneyText)")
    }
}

// MARK: - 识别截图记账（操作按钮 / 轻点背面 / 锁屏小组件）
struct RecordFromImageIntent: AppIntent {
    static var title: LocalizedStringResource = "识别截图记账"
    static var description = IntentDescription("从微信/支付宝付款成功截图中识别金额并自动记账，全程后台完成")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "截图", description: "传入「截屏」动作的结果")
    var image: IntentFile

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let data = image.data as Data?, let ui = UIImage(data: data) else {
            return .result(dialog: "图片读取失败，请重新截屏")
        }

        let text = await OCRService.recognize(ui)
        var entries = AutoBookkeeper.shared.ingest(text, source: "快捷指令·截图", trigger: .manual)

        // 兜底：截图没识别出来时，尝试剪贴板（如果之前复制过通知）
        if entries.isEmpty,
           let clip = UIPasteboard.general.string, clip.count > 6, clip.count < 4000 {
            entries = AutoBookkeeper.shared.ingest(clip, source: "快捷指令·剪贴板", trigger: .manual)
        }

        guard !entries.isEmpty else {
            return .result(dialog: "没识别到金额。请停留在「支付成功」页面再按一次，或先截个图。")
        }
        let total = entries.reduce(0) { $0 + $1.amountCents }
        let first = entries[0]
        return .result(dialog: "已记账 \(total.moneyText) · \(first.merchant)")
    }
}

// MARK: - 用相册最新截图记账（绕过快捷指令的截屏动作）
struct RecordFromLatestScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "用最新截图记账"
    static var description = IntentDescription("读取相册里最新的一张截图，识别其中的账单信息并记账")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let image = await ScreenshotReader.latest() else {
            return .result()
        }
        _ = await AutoBookkeeper.shared.ingestImage(image, source: "最新截图")
        return .result()
    }
}

/// 读取相册最新一张图片
enum ScreenshotReader {
    static func latest() async -> UIImage? {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else { return nil }

        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opts.fetchLimit = 1
        guard let asset = PHAsset.fetchAssets(with: .image, options: opts).firstObject else { return nil }

        return await withCheckedContinuation { cont in
            let req = PHImageRequestOptions()
            req.isSynchronous = false
            req.deliveryMode = .highQualityFormat
            req.resizeMode = .none
            var resumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 1600, height: 1600),
                contentMode: .aspectFit,
                options: req
            ) { img, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if degraded || resumed { return }
                resumed = true
                cont.resume(returning: img)
            }
        }
    }
}

// MARK: - 一句话记一笔
struct QuickRecordIntent: AppIntent {
    static var title: LocalizedStringResource = "快速记一笔"
    static var description = IntentDescription("直接记一笔支出")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "金额（元）")
    var amount: Double

    @Parameter(title: "分类")
    var category: CategoryEntity

    @Parameter(title: "商户/备注", default: "")
    var merchant: String

    static var parameterSummary: some ParameterSummary {
        Summary("记 \(\.$amount) 元 到 \(\.$category)") {
            \.$merchant
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        AutoBookkeeper.shared.addManual(
            amountCents: Int((amount * 100).rounded()),
            category: Category(rawValue: category.id) ?? .other,
            merchant: merchant,
            note: "",
            date: Date()
        )
        return .result(dialog: "已记 \(amount.amountCnyText) · \(category.name)")
    }
}

private extension Double {
    var amountCnyText: String { Int((self * 100).rounded()).moneyText }
}

// MARK: - 分类参数
struct CategoryEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "分类"
    static var defaultQuery = CategoryQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static var all: [CategoryEntity] {
        Category.allCases.map { CategoryEntity(id: $0.rawValue, name: $0.title) }
    }
}

struct CategoryQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [CategoryEntity] {
        CategoryEntity.all.filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [CategoryEntity] { CategoryEntity.all }
    func defaultResult() async -> CategoryEntity? { CategoryEntity.all.first }
}

// MARK: - 暴露给「快捷指令」App
struct BookkeepingShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ParseClipboardIntent(),
            phrases: [
                "用 \(.applicationName) 记一笔",
                "让 \(.applicationName) 记账"
            ],
            shortTitle: "剪贴板自动记账",
            systemImageName: "text.badge.checkmark"
        )
        AppShortcut(
            intent: RecordFromLatestScreenshotIntent(),
            phrases: ["用 \(.applicationName) 识别最新截图", "让 \(.applicationName) 记这张截图"],
            shortTitle: "用最新截图记账",
            systemImageName: "photo.on.rectangle.angled"
        )
        AppShortcut(
            intent: RecordFromImageIntent(),
            phrases: ["用 \(.applicationName) 识别截图记账", "让 \(.applicationName) 记这笔"],
            shortTitle: "识别截图记账",
            systemImageName: "text.viewfinder"
        )
        AppShortcut(
            intent: QuickRecordIntent(),
            phrases: ["替 \(.applicationName) 记一笔"],
            shortTitle: "快速记一笔",
            systemImageName: "plus.circle.fill"
        )
    }
}
