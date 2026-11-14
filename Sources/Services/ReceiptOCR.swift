import Foundation
import Vision
import CoreImage
import ImageIO

/// iOS 与 macOS 验收工具共用的图片识别管线；只使用设备端 Vision。
enum ReceiptOCR {
    struct Receipt {
        var text: String
        var needsReview: Bool
    }

    static func recognize(_ image: CGImage, orientation: CGImagePropertyOrientation = .up) -> Receipt {
        let oriented = CIImage(cgImage: image).oriented(orientation)
        let factor = min(1, 3000 / max(oriented.extent.width, oriented.extent.height))
        let scaled = oriented.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else {
            return Receipt(text: "", needsReview: true)
        }
        let firstPass = run(cg)
        let original = firstPass.text
        let parsed = BillParser.parse(original).first
        if let parsed, !parsed.needsReview, !firstPass.needsReview { return Receipt(text: original, needsReview: false) }
        let input = CIImage(cgImage: cg)
        let enhanced = input.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0, kCIInputContrastKey: 1.25
        ])
        guard let secondImage = CIContext().createCGImage(enhanced, from: input.extent) else {
            return Receipt(text: original, needsReview: firstPass.needsReview || (parsed?.needsReview ?? true))
        }
        let secondPass = run(secondImage)
        let second = secondPass.text
        let retry = BillParser.parse(second).first
        func score(_ p: BillParser.Parsed?) -> Int {
            guard let p else { return -1 }
            return (p.merchant.isEmpty ? 0 : 3) + (p.product.isEmpty ? 0 : 1)
                + (p.hasPaidTime ? 3 : 0) + (p.channel == .unknown ? 0 : 2)
                + (p.source == .manual ? 0 : 1) + (p.needsReview ? 0 : 3)
        }
        let conflict = parsed != nil && retry != nil && parsed?.amountCents != retry?.amountCents
        let useRetry = score(retry) - (secondPass.needsReview ? 2 : 0) > score(parsed) - (firstPass.needsReview ? 2 : 0)
        return Receipt(text: useRetry ? second : original,
                       needsReview: conflict || (useRetry ? secondPass.needsReview : firstPass.needsReview)
                         || ((useRetry ? retry?.needsReview : parsed?.needsReview) ?? true))
    }

    private static func run(_ image: CGImage) -> Receipt {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        // 金额、卡尾号、商户专名不能用自然语言纠错猜写。
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.005
        request.customWords = BillParser.detailLabels + ["零钱通", "余额宝", "花呗", "财付通"]
        do {
            try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
            var items = (request.results ?? []).compactMap { observation -> OCRLayout.Item? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return OCRLayout.Item(rect: observation.boundingBox, text: candidate.string,
                                      confidence: candidate.confidence)
            }
            items = refineFields(items, image: image)
            let labels = items.filter { BillParser.detailLabel($0.text) != nil && $0.rect.minX < 0.3 }
            let top = labels.map { $0.rect.maxY }.max() ?? 1
            let bottom = labels.map { $0.rect.minY }.min() ?? 0
            let uncertain = items.contains {
                $0.rect.midY <= top && $0.rect.midY >= bottom && $0.confidence < 0.45
            }
            return Receipt(text: OCRLayout.text(from: items), needsReview: uncertain)
        } catch { return Receipt(text: "", needsReview: true) }
    }

    /// 长商户名、商品说明用字段区域复读。裁切边界来自标签坐标，不依赖商户白名单。
    private static func refineFields(_ original: [OCRLayout.Item], image: CGImage) -> [OCRLayout.Item] {
        let labels = original.filter { BillParser.detailLabels.contains($0.text) && $0.rect.minX < 0.3 }
        let targets = ["商户全称", "商户名称", "商家名称", "商品", "商品说明", "商品名称"]
        var removed = Set<Int>()
        var replacements: [OCRLayout.Item] = []
        for label in labels where targets.contains(label.text) {
            let next = labels.filter { $0.rect.midY < label.rect.midY - label.rect.height * 0.7 }
                .max { $0.rect.midY < $1.rect.midY }
            let bottom = (next?.rect.maxY ?? max(0, label.rect.minY - 0.12)) + 0.003
            let top = min(1, label.rect.maxY + 0.008)
            let indices = original.indices.filter {
                original[$0].rect.minX > label.rect.maxX + 0.025
                    && original[$0].rect.midY <= top && original[$0].rect.midY > bottom
            }
            guard let left = indices.map({ original[$0].rect.minX }).min(),
                  let right = indices.map({ original[$0].rect.maxX }).max(), bottom < top else { continue }
            let x = max(label.rect.maxX + 0.015, left - 0.018)
            let pixelRect = CGRect(x: x * CGFloat(image.width), y: (1 - top) * CGFloat(image.height),
                                   width: (min(1, right + 0.025) - x) * CGFloat(image.width),
                                   height: (top - bottom) * CGFloat(image.height)).integral
            guard let crop = image.cropping(to: pixelRect) else { continue }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = !label.text.hasPrefix("商品")
            request.customWords = ["餐饮", "餐饮管理", "有限公司", "有限责任公司"]
            guard (try? VNImageRequestHandler(cgImage: crop).perform([request])) != nil else { continue }
            let observations = (request.results ?? []).sorted { $0.boundingBox.midY > $1.boundingBox.midY }
            var value = observations.compactMap { $0.topCandidates(1).first?.string }.joined()
            let oldValue = indices.sorted { original[$0].rect.midY > original[$1].rect.midY }
                .map { original[$0].text }.joined()
            if label.text.hasPrefix("商品") {
                let rowValue = recognizeProductRows(crop)
                if !rowValue.isEmpty { value = rowValue }
            } else {
                // 专名不靠语言模型改写；只在补齐完整字段或通用行业词更完整时采用复读。
                func completeness(_ text: String) -> Int {
                    ["有限公司", "有限责任公司", "餐饮", "食品", "科技", "管理"].filter { text.contains($0) }.count
                }
                if completeness(value) <= completeness(oldValue) { value = oldValue }
            }
            guard !value.isEmpty else { continue }
            removed.formUnion(indices)
            replacements.append(OCRLayout.Item(
                rect: CGRect(x: left, y: label.rect.minY, width: right - left, height: label.rect.height),
                text: value, confidence: observations.compactMap { $0.topCandidates(1).first?.confidence }.min() ?? 0))
        }
        return original.indices.filter { !removed.contains($0) }.map { original[$0] } + replacements
    }

    /// 按真实墨迹分行，恢复 Vision 在整段识别时忽略的单字/单数字续行。
    private static func recognizeProductRows(_ image: CGImage) -> String {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return "" }
        var pixels = [UInt8](repeating: 255, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return "" }
        var ranges: [Range<Int>] = []
        var start: Int?
        var lastInk = 0
        for y in 0..<height {
            let ink = (0..<width).reduce(0) { $0 + (pixels[y * width + $1] < 150 ? 1 : 0) }
            if ink > 2 {
                if start == nil { start = y }
                lastInk = y
            } else if let first = start, y - lastInk > 3 {
                if lastInk - first >= 1 { ranges.append(first..<(lastInk + 1)) }
                start = nil
            }
        }
        if let start, lastInk - start >= 1 { ranges.append(start..<(lastInk + 1)) }
        // 下划线可能低于数字基线，与主体文字之间有空白，仍属于上一视觉行。
        var joined: [Range<Int>] = []
        for row in ranges {
            if let previous = joined.last, row.count <= max(4, previous.count / 4),
               row.lowerBound - previous.upperBound <= max(5, previous.count / 2) {
                joined[joined.count - 1] = previous.lowerBound..<row.upperBound
            } else { joined.append(row) }
        }
        ranges = joined
        #if OCR_DIAGNOSTICS
        print("field-raster", width, height, "rows", ranges)
        #endif
        // 单行无需额外复读；正常字段保持原始识别。
        guard ranges.count > 1 else { return "" }
        var result = ""
        for row in ranges {
            let columns = (0..<width).filter { x in row.contains { pixels[$0 * width + x] < 150 } }
            guard let left = columns.first, let right = columns.last else { continue }
            let rect = CGRect(x: max(0, left - 8), y: max(0, row.lowerBound - 8),
                width: min(width, right + 9) - max(0, left - 8),
                height: min(height, row.upperBound + 8) - max(0, row.lowerBound - 8))
            guard let crop = image.cropping(to: rect) else { continue }
            func read(_ fast: Bool) -> String {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = fast ? .fast : .accurate
                request.recognitionLanguages = fast ? ["en-US"] : ["zh-Hans", "en-US"]
                request.usesLanguageCorrection = false
                request.minimumTextHeight = 0.001
                guard (try? VNImageRequestHandler(cgImage: crop).perform([request])) != nil else { return "" }
                return (request.results ?? []).sorted { $0.boundingBox.minX < $1.boundingBox.minX }
                    .compactMap { $0.topCandidates(1).first?.string }.joined()
            }
            var text = read(false)
            if text.isEmpty {
                text = read(true)
                // 仅数字编号末尾的孤立圆形字符，允许把 fast OCR 的 o 归一为 0。
                if result.last?.isNumber == true && text.lowercased() == "o" { text = "0" }
            }
            if !text.isEmpty {
                // 下划线位于字形底部；减号位于中部。用像素位置判定，不能按文本猜替换。
                var end = left
                while end < width && columns.contains(end) { end += 1 }
                // 下划线常与后面的数字在横向投影上相接，只检查最左侧的笔画。
                let prefixEnd = min(end, left + max(3, row.count / 4))
                let ys = row.filter { y in (left..<prefixEnd).contains { pixels[y * width + $0] < 150 } }
                #if OCR_DIAGNOSTICS
                print("row-ocr", text, "left", left, "end", end, "ink", ys.first ?? -1, ys.last ?? -1, "range", row)
                #endif
                if let top = ys.first, let bottom = ys.last,
                   top - row.lowerBound > row.count * 2 / 3,
                   end - left > (bottom - top + 1) * 2 {
                    if text.hasPrefix("-") { text = "_" + text.dropFirst() }
                    else if !text.hasPrefix("_") { text = "_" + text }
                }
            }
            result += text
        }
        return result
    }
}
