import Foundation
import AppIntents
import UIKit
import Photos
import UniformTypeIdentifiers

/// 记录 App Intent 的执行结果，便于在 App 内排查「按了按钮却没记上」
enum IntentLog {
    private static let key = "intentLogLines"

    static var lines: [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }
    static var last: String? { lines.last }

    static func record(_ text: String) {
        let stamp = Date().formatted(date: .omitted, time: .standard)
        var arr = lines
        arr.append("[\(stamp)] \(text)")
        if arr.count > 6 { arr = Array(arr.suffix(6)) }
        UserDefaults.standard.set(arr, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

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
        let preview = text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        IntentLog.record("文本记账：\(text.count)字 | \(String(preview.prefix(90)))")
        let entries = AutoBookkeeper.shared.ingest(text, source: "快捷指令", trigger: .automatic)
        IntentLog.record(entries.isEmpty ? "文本记账：未识别到账单" : "文本记账：成功 \(entries.count) 笔")
        let total = entries.reduce(0) { $0 + $1.amountCents }
        return .result(value: entries.isEmpty ? "0" : total.moneyText)
    }
}

/// 当快捷指令编辑器无法把「截屏」结果连接到 IntentFile 时，用字符串传原始图片字节。
/// 这一步只编码图片，不在快捷指令中做 OCR，也不写入相册。
struct RecordFromEncodedImageIntent: AppIntent {
    static var title: LocalizedStringResource = "用编码截图记账"
    static var description = IntentDescription("接收快捷指令 Base64 编码的截图，恢复图片后用 App 内 OCR 记账")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "编码截图", description: "传入「Base64 编码」动作的结果")
    var encodedImage: String

    static var parameterSummary: some ParameterSummary {
        Summary("识别 \(\.$encodedImage)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let input = encodedImage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.count < 20_000_000,
              let data = Data(base64Encoded: input, options: .ignoreUnknownCharacters),
              !data.isEmpty, let image = UIImage(data: data) else {
            IntentLog.record("编码截图解码失败；检查参数是否接到 Base64 编码结果")
            throw NSError(domain: "SevenBookkeeping", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "未收到有效截图；请把编码截图参数设为 Base64 编码结果。"])
        }
        IntentLog.record("编码截图已还原：\(data.count) 字节")
        let entries = await AutoBookkeeper.shared.ingestImage(image, source: "快捷指令·编码截图")
        if entries.isEmpty && BillParser.parse(AutoBookkeeper.shared.lastOCRText).isEmpty {
            throw NSError(domain: "SevenBookkeeping", code: 4,
                userInfo: [NSLocalizedDescriptionKey: "截图中未识别到可靠账单，请打开完整详情页再按按钮。"])
        }
        return .result()
    }
}

// MARK: - 识别剪贴板里的图片（不需要相册权限）
struct RecordFromClipboardImageIntent: AppIntent {
    static var title: LocalizedStringResource = "识别剪贴板图片记账"
    static var description = IntentDescription("读取剪贴板中的截图并识别记账，不访问相册")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        let pb = UIPasteboard.general
        IntentLog.record("剪贴板图片：changeCount=\(pb.changeCount), types=\(pb.types.count)")
        guard let image = pb.image else {
            IntentLog.record("剪贴板读取被拒或没有图片（后台读取剪贴板需要用户授权，通常拿不到）")
            return .result()
        }
        IntentLog.record("剪贴板图片：\(Int(image.size.width))×\(Int(image.size.height))，OCR 中")
        let entries = await AutoBookkeeper.shared.ingestImage(image, source: "剪贴板图片")
        IntentLog.record(entries.isEmpty ? "剪贴板图片：未识别到账单" : "剪贴板图片：成功 \(entries.count) 笔")
        return .result()
    }
}

// MARK: - 用相册最新截图记账（绕过快捷指令的截屏动作）
struct RecordFromLatestScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "用最新截图记账"
    static var description = IntentDescription("读取相册里最新的一张截图，识别其中的账单信息并记账")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentLog.record("最新截图：开始读取相册")
        guard let shot = await ScreenshotReader.latestWithMeta() else {
            IntentLog.record("最新截图：读不到图片（相册权限被拒或相册为空）")
            return .result()
        }
        let image = shot.image
        let age = shot.createdAt.map { "拍摄于 \($0.formatted(date: .omitted, time: .standard))" } ?? "无拍摄时间"
        IntentLog.record("最新截图：\(Int(image.size.width))×\(Int(image.size.height))，\(age)")
        let entries = await AutoBookkeeper.shared.ingestImage(image, source: "最新截图")
        IntentLog.record(entries.isEmpty
            ? "最新截图：OCR 后未识别到账单"
            : "最新截图：记账成功 \(entries.reduce(0) { $0 + $1.amountCents }.moneyText)")

        // 记账成功后删除这张截图（可在设置里关闭）
        if !entries.isEmpty,
           UserDefaults.standard.object(forKey: "deleteScreenshotAfterUse") as? Bool ?? true,
           let asset = shot.asset {
            await ScreenshotReader.delete(asset)
        }
        return .result()
    }
}

/// 读取相册最新截图（排除普通照片）
enum ScreenshotReader {
    struct Shot {
        var image: UIImage
        var createdAt: Date?
        var asset: PHAsset?
    }

    static func latest() async -> UIImage? {
        (await latestWithMeta())?.image
    }

    /// 删除相册里的一张图（首次会弹系统确认）
    static func delete(_ asset: PHAsset) async {
        try? await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets([asset] as NSArray)
        }
    }

    static func latestWithMeta() async -> Shot? {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else { return nil }

        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opts.fetchLimit = 1
        opts.predicate = NSPredicate(format: "(mediaSubtype & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
        guard let asset = PHAsset.fetchAssets(with: .image, options: opts).firstObject else { return nil }
        let created = asset.creationDate


        return await withCheckedContinuation { cont in
            var resumed = false
            let opts = PHImageRequestOptions()
            opts.isNetworkAccessAllowed = true
            opts.deliveryMode = .highQualityFormat
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: opts) { data, _, _, _ in
                guard !resumed else { return }
                resumed = true
                if let data, let img = UIImage(data: data) {
                    cont.resume(returning: Shot(image: img, createdAt: created, asset: asset))
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }
}

// MARK: - 一句话记一笔
struct QuickRecordIntent: AppIntent {
    static var title: LocalizedStringResource = "快速记一笔"
    static var description = IntentDescription("直接记一笔收入或支出，按所选分类确定类型")
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
            date: Date(), kind: (Category(rawValue: category.id) ?? .other).kind
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

    @MainActor static var all: [CategoryEntity] {
        Category.allCases.map { CategoryEntity(id: $0.rawValue, name: $0.title) }
    }
}

struct CategoryQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [CategoryEntity] {
        await MainActor.run { CategoryEntity.all.filter { identifiers.contains($0.id) } }
    }
    func suggestedEntities() async throws -> [CategoryEntity] { await MainActor.run { CategoryEntity.all } }
    func defaultResult() async -> CategoryEntity? { await MainActor.run { CategoryEntity.all.first } }
}

// MARK: - 暴露给「快捷指令」App
struct BookkeepingShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordFromEncodedImageIntent(),
            phrases: ["用 \(.applicationName) 识别编码截图", "让 \(.applicationName) 记这笔"],
            shortTitle: "用编码截图记账",
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
