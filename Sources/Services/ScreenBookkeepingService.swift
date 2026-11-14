import Foundation
import Observation
import ScreenCaptureKit
import CoreMedia
import CoreImage
import UIKit
import CryptoKit

/// iOS 27 授权识屏会话。使用系统选择器，不绕过授权，不保存视频，不自动重启。
@available(iOS 27.0, *)
@MainActor
@Observable
final class ScreenBookkeepingService: NSObject {
    static let shared = ScreenBookkeepingService()
    private(set) var running = false
    private(set) var starting = false
    private(set) var status = "尚未开启"
    private(set) var recordedCount = 0
    private var stream: SCStream?
    private var sink: ScreenReceiptOutput?
    private var gate = ScreenReceiptGate()
    private var generation = UUID()
    private var lockObserver: NSObjectProtocol?

    override private init() {
        super.init()
        lockObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataWillBecomeUnavailableNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.stop(message: "锁屏后已停止，请重新开启会话") }
            }
    }

    func requestStart() {
        guard !running, !starting else { return }
        let picker = SCContentSharingPicker.shared
        guard picker.isAvailable else { status = "此设备当前不允许屏幕共享"; return }
        starting = true
        status = "请在系统界面确认共享屏幕"
        picker.add(self)
        var configuration = SCContentSharingPickerConfiguration()
        configuration.showsMicrophoneControl = false
        configuration.showsCameraControl = false
        picker.defaultConfiguration = configuration
        picker.isActive = true
        // 不能用 presentForCurrentApplication；那样只能看到记账 App 自身。
        picker.present(using: .display)
    }

    func stop(message: String = "会话已停止") async {
        generation = UUID()
        let old = stream
        stream = nil
        sink?.stop(); sink = nil
        running = false; starting = false
        gate = ScreenReceiptGate()
        SCContentSharingPicker.shared.remove(self)
        SCContentSharingPicker.shared.isActive = false
        try? await old?.stopCapture()
        status = message
    }

    private func begin(_ filter: SCContentFilter) async {
        guard starting, stream == nil else { return }
        generation = UUID()
        let token = generation
        let config = SCStreamConfiguration()
        config.capturesAudio = false
        config.captureMicrophone = false
        let output = ScreenReceiptOutput { [weak self] receipt in
            Task { @MainActor in
                guard let self, self.running, self.generation == token else { return }
                guard self.gate.accept(receipt.text) else { return }
                let entries = AutoBookkeeper.shared.ingest(receipt.text, source: "自动识屏",
                    trigger: .automatic, forceReview: receipt.needsReview)
                self.recordedCount += entries.count
                self.status = entries.isEmpty ? "正在识屏；已识别的账单交由账本去重" : "本次会话已处理 \(self.recordedCount) 笔"
            }
        }
        let capture = SCStream(filter: filter, configuration: config, delegate: self)
        do {
            try capture.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
            stream = capture; sink = output
            try await capture.startCapture()
            guard generation == token else { try? await capture.stopCapture(); return }
            running = true; starting = false; recordedCount = 0
            gate = ScreenReceiptGate()
            status = "会话运行中：打开微信或支付宝的成功支付页"
            output.start()
        } catch {
            await stop(message: Self.failureMessage(error))
        }
    }

    private static func failureMessage(_ error: Error) -> String {
        let error = error as NSError
        if error.domain == SCStreamErrorDomain && error.code == -3803 {
            return "当前安装签名缺少屏幕采集权限，请使用支持此能力的签名安装；仍可使用短信或截图记账"
        }
        return "屏幕共享不可用：\(error.localizedDescription)"
    }
}

@available(iOS 27.0, *)
extension ScreenBookkeepingService: SCContentSharingPickerObserver, SCStreamDelegate {
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in if !self.running { await self.stop(message: "已取消，未开始识屏") } }
    }
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor in await self.begin(filter) }
    }
    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor in await self.stop(message: Self.failureMessage(error)) }
    }
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            guard self.stream === stream else { return }
            await self.stop(message: Self.failureMessage(error))
        }
    }
}

/// 所有可变状态限于串行队列；OCR 在独立队列执行，永不阻塞系统帧回调。
@available(iOS 27.0, *)
private final class ScreenReceiptOutput: NSObject, SCStreamOutput {
    let queue = DispatchQueue(label: "seven.screen.frames")
    private let worker = DispatchQueue(label: "seven.screen.ocr", qos: .userInitiated)
    private let context = CIContext()
    private let receive: (ReceiptOCR.Receipt) -> Void
    private var timer: DispatchSourceTimer?
    private var latest: CGImage?
    private var lastFrameAt: TimeInterval = 0
    private var busy = false
    private var active = false
    private var cachedHash: Data?
    private var cachedReceipt: ReceiptOCR.Receipt?

    init(receive: @escaping (ReceiptOCR.Receipt) -> Void) { self.receive = receive }

    func start() {
        queue.async { [self] in
            self.active = true
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: 2, leeway: .milliseconds(250))
            timer.setEventHandler { [weak self] in self?.recognizeLatest() }
            self.timer = timer
            timer.resume()
        }
    }
    func stop() {
        queue.async {
            self.active = false
            self.timer?.cancel(); self.timer = nil
            self.latest = nil; self.cachedReceipt = nil; self.cachedHash = nil
        }
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferIsValid(sampleBuffer) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastFrameAt >= 0.8, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrameAt = now
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]]
        if let status = attachments?.first?[.status] as? Int, status != SCFrameStatus.complete.rawValue {
            if status != SCFrameStatus.idle.rawValue {
                latest = nil; cachedReceipt = nil; cachedHash = nil
                receive(ReceiptOCR.Receipt(text: "", needsReview: true))
            }
            return
        }
        let rawOrientation = (attachments?.first?[.videoOrientation] as? NSNumber)?.uint32Value ?? 1
        let ci = CIImage(cvPixelBuffer: buffer).oriented(CGImagePropertyOrientation(rawValue: rawOrientation) ?? .up)
        latest = context.createCGImage(ci, from: ci.extent)
    }
    private func recognizeLatest() {
        guard active, !busy, let image = latest else { return }
        // 对完整像素做摘要，不能用小缩略图判定相同，否则可能漏掉仅单号不同的新消费。
        guard let pixels = image.dataProvider?.data else { return }
        let hash = Data(SHA256.hash(data: pixels as Data))
        if cachedHash == hash, let cachedReceipt { receive(cachedReceipt); return }
        busy = true
        worker.async {
            let receipt = autoreleasepool { ReceiptOCR.recognize(image) }
            self.queue.async {
                self.busy = false
                guard self.active else { return }
                self.cachedHash = hash; self.cachedReceipt = receipt
                self.receive(receipt)
            }
        }
    }
}
