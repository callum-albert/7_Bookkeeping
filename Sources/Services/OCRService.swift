import Foundation
import UIKit
import CoreImage
import ImageIO

/// UIKit 入口；识别流程与本机图片验收工具复用 ReceiptOCR。
enum OCRService {
    static func recognize(_ image: UIImage) async -> String {
        await recognizeReceipt(image).text
    }

    static func recognizeReceipt(_ image: UIImage) async -> ReceiptOCR.Receipt {
        let cg: CGImage
        if let pixels = image.cgImage { cg = pixels }
        else if let ci = image.ciImage, let pixels = CIContext().createCGImage(ci, from: ci.extent) { cg = pixels }
        else { return ReceiptOCR.Receipt(text: "", needsReview: true) }
        let orientation: CGImagePropertyOrientation
        switch image.imageOrientation {
        case .up: orientation = .up
        case .down: orientation = .down
        case .left: orientation = .left
        case .right: orientation = .right
        case .upMirrored: orientation = .upMirrored
        case .downMirrored: orientation = .downMirrored
        case .leftMirrored: orientation = .leftMirrored
        case .rightMirrored: orientation = .rightMirrored
        @unknown default: orientation = .up
        }
        return await Task.detached(priority: .userInitiated) {
            ReceiptOCR.recognize(cg, orientation: orientation)
        }.value
    }
}
