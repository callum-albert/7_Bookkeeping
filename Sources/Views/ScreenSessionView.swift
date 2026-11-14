import SwiftUI

@available(iOS 27.0, *)
struct ScreenSessionView: View {
    private var _service = State(wrappedValue: ScreenBookkeepingService.shared)
    private var service: ScreenBookkeepingService { _service.wrappedValue }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("自动识屏会话 · iOS 27", systemImage: "viewfinder")
                .font(.system(size: 15, weight: .semibold))
            Text("先通过系统界面开启一次，会话期间停留在微信或支付宝支付成功页，即可自动识别记账，无需每笔截屏或长按按键。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("系统会显示屏幕共享状态。共享范围由系统选择器决定；画面只在本机处理，不保存视频、不上传、不采集麦克风或摄像头。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(service.status)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(service.running ? Theme.mint : Theme.brand)
                .accessibilityAddTraits(.updatesFrequently)
            if service.running || service.starting {
                Button("停止识屏", role: .destructive) { Task { await service.stop() } }
                    .buttonStyle(.bordered)
            } else {
                Button("开启系统授权识屏") { service.requestStart() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.brand)
            }
            Text("付款页需稳定显示数秒；锁屏、系统终止或手动停止后，需重新开启。此功能已通过编译与帧处理逻辑测试，安装签名权限和跨 App 后台运行仍需在你的 iPhone 上验证。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular.tint(Theme.mint.opacity(0.12)), in: .rect(cornerRadius: 22))
    }
}
