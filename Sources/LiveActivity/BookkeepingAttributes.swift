import Foundation
import ActivityKit

/// 灵动岛 / 实时活动数据模型（App 与 Widget Extension 共享）
struct BookkeepingAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var amountText: String
        var categoryTitle: String
        var categorySymbol: String
        var merchant: String
        var sourceTitle: String
        var totalTodayText: String
        var timeText: String
        /// 记账后该账户的现存余额，例如 "¥1,234.56"
        var balanceText: String
        /// 余额归属，例如 "微信余额" / "招商银行(1234)"
        var balanceLabel: String
        /// "自动记账" / "手动记账"
        var howText: String
    }

    var entryID: String
}
