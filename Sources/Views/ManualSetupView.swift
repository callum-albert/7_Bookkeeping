import SwiftUI

/// 手动记账设置说明
struct ManualSetupView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                intro
                method(
                    badge: "A", tint: Theme.warm,
                    title: "侧边按钮",
                    subtitle: "付款成功页面按一下，后台识别屏幕金额",
                    needSetup: "需要设置：一次性，加 2 个动作",
                    steps: [
                        "设置 → 操作按钮 → 选「快捷指令」",
                        "新建快捷指令，加两个动作：「截屏」",
                        "再加「7记账 → 识别截图记账」，图片参数选「截屏」",
                        "命名为「记一笔」保存，回到操作按钮选中它"
                    ]
                )
                method(
                    badge: "B", tint: Theme.brand,
                    title: "轻点背面",
                    subtitle: "双击手机背面触发同一个快捷指令",
                    needSetup: "需要设置：一次性",
                    steps: [
                        "先按上面步骤 A 做好「记一笔」快捷指令",
                        "设置 → 辅助功能 → 触控 → 轻点背面 → 双击",
                        "选择「记一笔」"
                    ]
                )
                method(
                    badge: "C", tint: Theme.mint,
                    title: "App 内手动",
                    subtitle: "记一笔 / 粘贴识别 / 截图识别",
                    needSetup: "无需设置，装好就能用",
                    steps: []
                )
                detail
                note
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle("手动记账")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.brand)
                Text("所有场景的兜底，包括零钱支付")
                    .font(.system(size: 13, weight: .semibold))
            }
            Text("微信零钱、支付宝余额支付不会产生银行短信，自动记账覆盖不到。按一下侧边按钮就能补上，全程不打开 App。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular.tint(Theme.brand.opacity(0.12)), in: .rect(cornerRadius: 22))
    }

    private func method(badge: String, tint: Color, title: String, subtitle: String,
                        needSetup: String, steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(badge)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(tint, in: .circle)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(needSetup)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(tint)

            if !steps.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                        stepLine(i + 1, s)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private func stepLine(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n)")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 15, height: 15)
                .background(Theme.brand.opacity(0.8), in: .circle)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.merge")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.mint)
                Text("和自动记账不冲突")
                    .font(.system(size: 12, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 4) {
                bullet("同一笔自动记过，再按按钮不会重复记")
                bullet("手动记录会把商户名、卡号补进自动记的那笔")
                bullet("手动窗口 30 分钟，付款后晚一点按也能对上")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private func bullet(_ t: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Circle().fill(.secondary.opacity(0.5)).frame(width: 3, height: 3).padding(.top, 6)
            Text(t).font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var note: some View {
        Text("按按钮时请停留在微信/支付宝的「支付成功」页面，识别率最高。识别失败会自动读剪贴板兜底。")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }
}
