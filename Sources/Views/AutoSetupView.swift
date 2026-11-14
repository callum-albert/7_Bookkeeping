import SwiftUI

/// 自动记账设置说明
struct AutoSetupView: View {
    private static let banks: [(String, String)] = [
        ("工商", "95588"), ("建设", "95533"), ("农业", "95599"), ("中国", "95566"),
        ("招商", "95555"), ("交通", "95559"), ("邮储", "95580"), ("中信", "95558"),
        ("民生", "95568"), ("光大", "95595"), ("兴业", "95561"), ("浦发", "95528"),
        ("平安", "95511"), ("广发", "95508"), ("华夏", "95577")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                openShortcutsButton
                intro
                channel(
                    badge: "A", badgeTint: Theme.mint,
                    title: "银行短信",
                    subtitle: "银行卡消费、入账与退款短信",
                    needSetup: "需开通消费和入账提醒；未发短信的交易可手动截图补记",
                    steps: [
                        "打开「快捷指令」App，点屏幕底部「自动化」标签（不是「快捷指令」标签）",
                        "右上角「+」→ 触发器列表里找「通信」分组 → 点「信息」",
                        "发件人点「添加」，填你的银行号码（下表）",
                        "「信息包含」按实际银行短信设置，如「消费」「支出」「入账」「收入」「退款」；不同措辞分别建自动化",
                        "右上角「下一步」→ 添加操作 → 搜「7记账」→ 解析账单文本记账",
                        "点动作里的「账单文本」→ 选「快捷指令输入」中的信息正文，先用真实消费短信测试",
                        "触发方式选「立即运行」（旧系统为关闭「运行前询问」），先解锁运行一次授权"
                    ],
                    extra: AnyView(bankList)
                )
                builtinCard
                note
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle("自动记账")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var openShortcutsButton: some View {
        Button {
            if let url = URL(string: "shortcuts://") {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.forward.app.fill")
                    .font(.system(size: 13))
                Text("打开「快捷指令」")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("先执行再照着做").font(.system(size: 10)).foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold)).opacity(0.35)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .glassEffect(.regular.tint(Theme.brand.opacity(0.16)).interactive(), in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.mint)
                Text("银行短信自动记录收入与支出")
                    .font(.system(size: 13, weight: .semibold))
            }
            Text("自动记账只保留银行短信。开通消费及入账提醒，配置一次快捷指令；微信零钱、支付宝余额等可继续使用手动按键截图记账。两种方式都能识别银行和卡尾号，并自动添加新卡。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("动作在动作库里搜「7记账」即可看到：解析账单文本记账 / 从剪贴板自动记账。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("注意：「信息」是自动化的触发器，在「自动化」标签里选；在新建快捷指令的搜索框里搜不到它。")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular.tint(Theme.mint.opacity(0.12)), in: .rect(cornerRadius: 22))
    }

    private func channel(badge: String, badgeTint: Color, title: String, subtitle: String,
                         needSetup: String, steps: [String], extra: AnyView) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(badge)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(badgeTint, in: .circle)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }

            Text(needSetup)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(badgeTint)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                    stepLine(i + 1, s)
                }
            }

            extra
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

    private var bankList: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("常见银行短信号码")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 3) {
                ForEach(Self.banks, id: \.0) { pair in
                    HStack(spacing: 4) {
                        Text(pair.0).font(.system(size: 9)).foregroundStyle(.secondary)
                        Text(pair.1)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.primary.opacity(0.7))
                    }
                }
            }
        }
        .padding(9)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 10))
    }

    private var builtinCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.brand)
                Text("无需设置的能力")
                    .font(.system(size: 12, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 4) {
                bullet("短信与按键截图都可自动添加新卡，识别范围以账单显示的尾号为准")
                bullet("绑定银行卡的支付会自动登记卡号")
                bullet("识别到尾号会自动创建这张卡，余额可后补")
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
        Text("银行未发送短信或金额低于提醒门槛时不会触发；可用原来的按键截图补记。同一笔短信与截图会合并，收入与支出分别统计。")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }
}
