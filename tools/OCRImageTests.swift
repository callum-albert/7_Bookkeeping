import Foundation
import ImageIO

// 本机真实图片验收工具。输入、期望值和输出应放在仓库之外，避免公开私人账单。
// --expected JSON: { "图片文件名": { "amountCents": "1234", "source": "wechat", ... } }
var inputs: [String] = []
var output: String?
var expectedPath: String?
var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let arg = args.removeFirst()
    if arg == "--output", !args.isEmpty { output = args.removeFirst() }
    else if arg == "--expected", !args.isEmpty { expectedPath = args.removeFirst() }
    else { inputs.append(arg) }
}
guard !inputs.isEmpty, let output else {
    fputs("Usage: OCRImageTests --output /tmp/results.json [--expected /tmp/expected.json] image...\n", stderr)
    exit(2)
}
let expected: [String: [String: String]]
if let expectedPath {
    expected = try JSONDecoder().decode([String: [String: String]].self,
        from: Data(contentsOf: URL(fileURLWithPath: expectedPath)))
} else { expected = [:] }
let formatter = DateFormatter()
formatter.locale = Locale(identifier: "en_US_POSIX")
formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
var results: [[String: Any]] = []
var failed = 0
var passedFields = 0
var totalFields = 0
func canonical(_ s: String) -> String {
    (s.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? s)
        .replacingOccurrences(of: "･", with: "·").replacingOccurrences(of: "・", with: "·")
        .filter { !$0.isWhitespace }
}
for path in inputs {
    let url = URL(fileURLWithPath: path)
    let name = url.lastPathComponent
    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
        results.append(["file": name, "error": "Image decode failed"])
        failed += 1
        continue
    }
    let props = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
    let orientation = CGImagePropertyOrientation(rawValue: (props?[kCGImagePropertyOrientation] as? UInt32) ?? 1) ?? .up
    let receipt = ReceiptOCR.recognize(image, orientation: orientation)
    let parsed = BillParser.parse(receipt.text)
    var fields: [String: String] = [:]
    if let p = parsed.first {
        fields = ["amountCents": String(p.amountCents), "category": p.category.rawValue,
                  "source": p.source.rawValue, "account": p.account, "channel": p.channel.rawValue,
                  "paidTime": p.hasPaidTime ? formatter.string(from: p.date) : "",
                  "merchant": p.merchant, "product": p.product, "flow": p.flow.rawValue]
    }
    var mismatches: [String] = []
    if let wanted = expected[name] {
        for (key, value) in wanted {
            totalFields += 1
            if canonical(fields[key] ?? "") == canonical(value) { passedFields += 1 }
            else { mismatches.append(key) }
        }
    } else if expectedPath != nil { mismatches.append("missingExpectation") }
    if parsed.count != 1 { mismatches.append("entryCount") }
    if !mismatches.isEmpty { failed += 1 }
    results.append(["file": name, "fields": fields, "entryCount": parsed.count,
                    "needsReview": receipt.needsReview || (parsed.first?.needsReview ?? true),
                    "mismatches": mismatches, "ocrText": receipt.text])
    let status = mismatches.isEmpty ? (expectedPath == nil ? "PARSED (not validated)" : "PASS") : "FAIL " + mismatches.joined(separator: ",")
    print("\(name): \(status)")
}
let report: [String: Any] = ["imageCount": inputs.count, "failedImages": failed,
                            "passedFields": passedFields, "totalFields": totalFields,
                            "results": results]
try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    .write(to: URL(fileURLWithPath: output), options: .atomic)
print("Images: \(inputs.count - failed)/\(inputs.count); fields: \(passedFields)/\(totalFields)")
exit(failed == 0 ? 0 : 1)
