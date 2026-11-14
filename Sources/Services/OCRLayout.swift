import Foundation

/// Vision 的归一化坐标（左下为原点）。独立于 Vision，便于回归版式错位。
enum OCRLayout {
    struct Item {
        var rect: CGRect
        var text: String
        var confidence: Float = 1
    }

    static func text(from items: [Item]) -> String {
        var rows: [[Item]] = []
        for item in items.sorted(by: { $0.rect.midY > $1.rect.midY }) {
            // 相对文字高度判定同一行；固定锚点，避免连续偏移把相邻字段串起来。
            if let i = rows.indices.min(by: {
                abs(rows[$0][0].rect.midY - item.rect.midY) < abs(rows[$1][0].rect.midY - item.rect.midY)
            }), abs(rows[i][0].rect.midY - item.rect.midY) <= min(rows[i][0].rect.height, item.rect.height) * 0.6 {
                rows[i].append(item)
            } else { rows.append([item]) }
        }
        // 标签与右侧多行值配对，保留字段边界；不把上一字段的长值串到下一标签。
        var result: [String] = []
        var pendingLabel: String?
        var pendingValueX: CGFloat?
        for row in rows {
            let sorted = row.sorted { $0.rect.minX < $1.rect.minX }
            let line = sorted.map(\.text).joined(separator: "  ")
            if let first = sorted.first, BillParser.detailLabel(first.text) != nil {
                result.append(line)
                pendingLabel = first.text
                pendingValueX = sorted.count > 1 ? sorted[1].rect.minX : nil
            } else if let first = sorted.first, let valueX = pendingValueX,
                      first.rect.minX >= valueX - 0.025,
                      let label = pendingLabel, !label.contains("金额"),
                      !label.contains("状态"), !label.contains("单号"),
                      let last = result.last, last != label {
                result[result.count - 1] += " " + line
            } else {
                result.append(line)
                pendingLabel = nil
                pendingValueX = nil
            }
        }
        return result.joined(separator: "\n")
    }
}
