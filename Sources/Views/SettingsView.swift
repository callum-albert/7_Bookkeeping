import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    private var _store = State(wrappedValue: LedgerStore.shared)
    private var store: LedgerStore { _store.wrappedValue }
    private var _bookkeeper = State(wrappedValue: AutoBookkeeper.shared)
    private var bookkeeper: AutoBookkeeper { _bookkeeper.wrappedValue }
    private var _liveActivity = State(wrappedValue: LiveActivityController.shared)
    private var liveActivity: LiveActivityController { _liveActivity.wrappedValue }
    private var _backup = State(wrappedValue: BackupService.shared)
    private var backup: BackupService { _backup.wrappedValue }
    private var _accounts = State(wrappedValue: Accounts.shared)
    private var accounts: Accounts { _accounts.wrappedValue }
    private var _update = State(wrappedValue: UpdateChecker.shared)
    private var update: UpdateChecker { _update.wrappedValue }
    private var _notify = State(wrappedValue: NotificationService.shared)
    private var notify: NotificationService { _notify.wrappedValue }
    private var _showClearAlert = State(wrappedValue: false)
    private var showClearAlert: Bool { get { _showClearAlert.wrappedValue } nonmutating set { _showClearAlert.wrappedValue = newValue } }
    private var _exportURL = State<URL?>(wrappedValue: nil)
    private var exportURL: URL? { get { _exportURL.wrappedValue } nonmutating set { _exportURL.wrappedValue = newValue } }
    private var _showShare = State(wrappedValue: false)
    private var showShare: Bool { get { _showShare.wrappedValue } nonmutating set { _showShare.wrappedValue = newValue } }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                methodsCard
                NavigationLink { CategoryManageView() } label: {
                    Label("自定义分类", systemImage: "tag.fill")
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
                }.buttonStyle(.plain)
                balanceCard
                dataCard
                islandCard
                aboutCard
                if let log = IntentLog.last {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Text(log)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 6)
                }
                Color.clear.frame(height: 90)
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle("我的")
        .navigationBarTitleDisplayMode(.inline)
        .alert("清空所有账目？", isPresented: _showClearAlert.projectedValue) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) { store.deleteAll() }
        } message: {
            Text("此操作不可撤销。如果配置了 iCloud 备份，下次同步会一并删除云端账目。")
        }
        .sheet(isPresented: _showShare.projectedValue) {
            if let exportURL { ShareSheet(url: exportURL) }
        }
    }

    // MARK: - 记账方式
    private var methodsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("记账方式")
                .font(.system(size: 22, weight: .bold, design: .rounded))

            methodRow(
                symbol: "bolt.fill",
                tint: Theme.mint,
                title: "自动记账",
                detail: "银行短信 · 自动记录收入与支出",
                badge: "需设置一次",
                destination: AutoSetupView()
            )

            Divider().opacity(0.35)

            methodRow(
                symbol: "hand.tap.fill",
                tint: Theme.brand,
                title: "手动记账",
                detail: "侧边按钮 Base64 图片 / 粘贴",
                badge: "需设置一次",
                destination: ManualSetupView()
            )

            Text("两种方式可以同时用，同一笔会自动去重，只记一次。")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private func methodRow<D: View>(symbol: String, tint: Color, title: String,
                                    detail: String, badge: String, destination: D) -> some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(tint, in: .rect(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                Text(badge)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tint.opacity(0.14), in: .capsule)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 余额
    private var balanceCard: some View {
        NavigationLink {
            BalanceManageView()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("余额")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("管理")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 8) {
                    smallBucket("微信", accounts.wechat, Theme.mint)
                    smallBucket("支付宝", accounts.alipay,
                                Color(red: 0.10, green: 0.47, blue: 0.96))
                    smallBucket("银行卡\(accounts.cards.isEmpty ? "" : "·\(accounts.cards.count)张")",
                                accounts.bankTotal, BalanceBucket.bank.tint)
                }

                if accounts.cards.count > 1 {
                    Text(accounts.cards.map(\.displayName).joined(separator: " · "))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
        }
        .buttonStyle(.plain)
    }

    private func smallBucket(_ title: String, _ cents: Int, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            Text(cents.amountOnly)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 9)
        .background(tint.opacity(0.09), in: .rect(cornerRadius: 12))
    }

    // MARK: - 数据
    private var dataCard: some View {
        VStack(spacing: 0) {
            NavigationLink {
                CloudBackupView()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "icloud.fill").foregroundStyle(Theme.brand)
                        .frame(width: 22)
                    Text("iCloud 备份与同步")
                    Spacer()
                    Text(backup.isConfigured ? "已连接" : "未设置")
                        .font(.system(size: 11))
                        .foregroundStyle(backup.isConfigured ? Theme.mint : .secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .font(.system(size: 14))
                .padding(.horizontal, 16).padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 48).opacity(0.35)

            Button { exportCSV() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.up").foregroundStyle(Theme.mint)
                        .frame(width: 22)
                    Text("导出 CSV")
                    Spacer()
                    Text("\(store.entries.count) 笔")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .font(.system(size: 14))
                .padding(.horizontal, 16).padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 48).opacity(0.35)

            Button { showClearAlert = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "trash").foregroundStyle(Theme.danger)
                        .frame(width: 22)
                    Text("清空所有数据").foregroundStyle(Theme.danger)
                    Spacer()
                }
                .font(.system(size: 14))
                .padding(.horizontal, 16).padding(.vertical, 14)
            }
            .buttonStyle(.plain)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    // MARK: - 灵动岛
    private var islandCard: some View {
        let d = liveActivity.diagnostics()
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.brandSoft)
                Text("灵动岛")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(d.verdict == "配置正常" ? "正常" : "异常")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(d.verdict == "配置正常" ? Theme.mint : Theme.warm)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((d.verdict == "配置正常" ? Theme.mint : Theme.warm).opacity(0.15), in: .capsule)
            }

            if d.verdict != "配置正常" {
                Text(d.verdict)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.warm)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle(isOn: Binding(
                get: { notify.enabled },
                set: { notify.setEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("记账后发通知").font(.system(size: 12))
                    Text(notify.authorized ? "每次记账推一条锁屏通知" : "需要先在系统设置里允许通知")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            .tint(Theme.brand)

            HStack(spacing: 8) {
                NavigationLink {
                    IslandDiagnosticsView()
                } label: {
                    Text("诊断")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Button {
                    let sample = Entry(amountCents: 2880, date: Date(), category: .food,
                                       merchant: "星巴克", source: .wechat, raw: "测试", auto: true)
                    _ = liveActivity.start(for: sample, todayTotal: bookkeeper.todayTotal(), auto: false)
                } label: {
                    Text("预览效果")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .glassEffect(.regular.tint(Theme.brand.opacity(0.18)).interactive(), in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    // MARK: - 关于
    private var aboutCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "7.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(LinearGradient(colors: [Theme.brand, Theme.brandSoft],
                                                    startPoint: .top, endPoint: .bottom))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("7记账").font(.system(size: 14, weight: .bold, design: .rounded))
                        Text("v\(update.currentVersion)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                        if update.hasUpdate {
                            Text("有新版本")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Theme.mint)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Theme.mint.opacity(0.16), in: .capsule)
                        }
                    }
                    Text("数据只存在本机与你的 iCloud")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await update.check() }
                } label: {
                    if update.isChecking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("检查更新")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .glassEffect(.regular.interactive(), in: .capsule)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            if update.hasUpdate, let latest = update.latest {
                Divider().opacity(0.35)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("v\(latest.version) 可用").font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text("当前 v\(update.currentVersion)")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Text("新版本需要用你的证书重新签名安装；快捷指令与自动化不用重配。")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button {
                            UIApplication.shared.open(latest.downloadURL)
                        } label: {
                            Text("下载安装包")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .glassEffect(.regular.tint(Theme.brand.opacity(0.2)).interactive(), in: .rect(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)

                        Button {
                            UIApplication.shared.open(latest.pageURL)
                        } label: {
                            Text("查看说明")
                                .font(.system(size: 12, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            } else if let err = update.error {
                Divider().opacity(0.35)
                Text("检查失败：\(err)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let last = update.lastChecked {
                Divider().opacity(0.35)
                HStack {
                    Text("已是最新版本")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.mint)
                    Spacer()
                    Text(last.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private func exportCSV() {
        var csv = "日期,金额,收支类型,分类,商户,来源,支付渠道,备注\n"
        func cell(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        for e in store.entries.sorted(by: { $0.date > $1.date }) {
            csv += [f.string(from: e.date), String(format: "%.2f", e.amount), e.kind.title,
                    e.category.title, e.merchant, e.source.title, e.account, e.note]
                .map(cell).joined(separator: ",") + "\n"
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("7记账-\(Date().formatted(.dateTime.year().month().day())).csv")
        try? csv.data(using: .utf8)?.write(to: url)
        exportURL = url
        showShare = true
    }
}

// MARK: - 分享面板
struct ShareSheet: UIViewControllerRepresentable {
    var url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
