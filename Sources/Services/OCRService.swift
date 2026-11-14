import Foundation
import Vision
import UIKit

/// 本机 OCR，银行级隐私：图片不出设备
enum OCRService {
    static func recognize(_ image: UIImage) async -> String {
        guard let cg = image.cgImage else { return "" }
        return await withCheckedContinuation { cont in
            let request = VNRecognizeTextRequest { req, _ in
                let obs = req.results as? [VNRecognizedTextObservation] ?? []
                // 按纵向位置排序，还原阅读顺序
                let lines = obs.compactMap { o -> (CGFloat, String)? in
                    guard let t = o.topCandidates(1).first?.string else { return nil }
                    return (o.boundingBox.midY, t)
                }
                .sorted { $0.0 > $1.0 }
                .map(\.1)
                cont.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = true

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
                } catch {
                    cont.resume(returning: "")
                }
            }
        }
    }
}
