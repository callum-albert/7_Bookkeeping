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

                // 关键：先按「视觉行」聚类，同一水平线上的文字合成一行
                // 账单页的「标签 + 值」经常被拆成两个 observation，
                // 只有按坐标还原成视觉行，模板解析才能对上。
                var items: [(y: CGFloat, x: CGFloat, text: String)] = []
                for o in obs {
                    guard let t = o.topCandidates(1).first?.string else { continue }
                    items.append((o.boundingBox.midY, o.boundingBox.minX, t))
                }
                items.sort { $0.y > $1.y }

                var lines: [[(x: CGFloat, text: String)]] = []
                var current: [(x: CGFloat, text: String)] = []
                var lastY: CGFloat = -1
                let tolerance: CGFloat = 0.013

                for it in items {
                    if lastY < 0 || abs(it.y - lastY) <= tolerance {
                        current.append((it.x, it.text))
                    } else {
                        if !current.isEmpty { lines.append(current) }
                        current = [(it.x, it.text)]
                    }
                    lastY = it.y
                }
                if !current.isEmpty { lines.append(current) }

                let text = lines
                    .map { row in row.sorted { $0.x < $1.x }.map(\.text).joined(separator: "  ") }
                    .joined(separator: "\n")
                cont.resume(returning: text)
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
