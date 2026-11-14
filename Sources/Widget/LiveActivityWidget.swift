import SwiftUI
import WidgetKit
import ActivityKit

@main
struct SevenWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BookkeepingLiveActivity()
    }
}

struct BookkeepingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BookkeepingAttributes.self) { context in
            // 锁屏 / 通知中心完整卡片
            LockScreenCard(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.001))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                // 展开态（长按）：金额 + 分类 + 商户 + 余额
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        islandIcon(s)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("7记账")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(s.categoryTitle)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(s.amountText)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                        Text(s.howText)
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.trailing, 6)
                }

                DynamicIslandExpandedRegion(.center) {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(red: 0.24, green: 0.80, blue: 0.66))
                        Text("已记账")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 7) {
                        Divider().overlay(.white.opacity(0.15))

                        HStack(spacing: 6) {
                            Image(systemName: "storefront.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.45))
                            Text(s.merchant)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.75))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(s.sourceTitle)
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.5))
                            Text("·").foregroundStyle(.white.opacity(0.25))
                            Text(s.timeText)
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.5))
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "wallet.pass.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.45))
                            Text(s.balanceLabel)
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.55))
                            Spacer(minLength: 4)
                            Text(s.balanceText)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .monospacedDigit()
                        }

                        HStack(spacing: 4) {
                            Text("今日累计")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.4))
                            Text(s.totalTodayText)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.6))
                                .monospacedDigit()
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 2)
                }
            } compactLeading: {
                islandIcon(s)
            } compactTrailing: {
                Text(s.amountText.replacingOccurrences(of: "¥", with: ""))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .padding(.trailing, 2)
            } minimal: {
                islandIcon(s)
            }
            .keylineTint(Color(red: 0.35, green: 0.36, blue: 0.98))
            .widgetURL(URL(string: "seven7://open"))
        }
    }

    @ViewBuilder
    private func islandIcon(_ s: BookkeepingAttributes.ContentState) -> some View {
        Image(systemName: s.categorySymbol)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(
                LinearGradient(colors: [Color(red: 0.35, green: 0.36, blue: 0.98),
                                        Color(red: 0.55, green: 0.45, blue: 1.00)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .circle
            )
    }
}

// MARK: - 锁屏卡片
struct LockScreenCard: View {
    let state: BookkeepingAttributes.ContentState

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: state.categorySymbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        LinearGradient(colors: [Color(red: 0.35, green: 0.36, blue: 0.98),
                                                Color(red: 0.55, green: 0.45, blue: 1.00)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: .rect(cornerRadius: 14)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text("7记账")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.white.opacity(0.5))
                        Text("已记账")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(red: 0.24, green: 0.80, blue: 0.66))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color(red: 0.24, green: 0.80, blue: 0.66).opacity(0.18), in: .capsule)
                        Text(state.howText)
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    Text(state.merchant)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("\(state.categoryTitle) · \(state.sourceTitle) · \(state.timeText)")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(state.amountText)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Text("今日 \(state.totalTodayText)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                        .monospacedDigit()
                }
            }

            Divider().overlay(.white.opacity(0.14))

            HStack {
                Image(systemName: "wallet.pass.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
                Text(state.balanceLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text(state.balanceText)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
        }
        .padding(16)
    }
}
