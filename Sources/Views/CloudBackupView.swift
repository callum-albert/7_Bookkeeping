import SwiftUI
import UniformTypeIdentifiers

/// iCloud 备份与同步
struct CloudBackupView: View {
    private var _backup = State(wrappedValue: BackupService.shared)
    private var backup: BackupService { _backup.wrappedValue }
    private var _showFolderPicker = State(wrappedValue: false)
    private var showFolderPicker: Bool { get { _showFolderPicker.wrappedValue } nonmutating set { _showFolderPicker.wrappedValue = newValue } }
    private var _store = State(wrappedValue: LedgerStore.shared)
    private var store: LedgerStore { _store.wrappedValue }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                statusCard
                if backup.isConfigured { actionsCard } else { setupCard }
                howItWorks
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle("iCloud 备份")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: _showFolderPicker.projectedValue,
                      allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                backup.connect(url)
            }
        }
    }

    // MARK: - 状态
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "icloud.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.brand)
                VStack(alignment: .leading, spacing: 2) {
                    Text(backup.isConfigured ? "已连接" : "未设置")
                        .font(.system(size: 15, weight: .semibold))
                    Text(backup.isConfigured
                         ? (backup.folderName ?? "")
                         : "备份到你自己的 iCloud Drive")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if backup.isWorking { ProgressView().controlSize(.small) }
            }

            if let t = backup.lastSyncAt {
                Text("上次同步 \(t.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if let msg = backup.lastSummary {
                Text(msg)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.mint)
            }
            if let err = backup.lastError {
                Text(err)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                statBox("本机账目", "\(store.entries.count)")
                statBox("银行卡", "\(Accounts.shared.cards.count)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular.tint(Theme.brand.opacity(0.12)), in: .rect(cornerRadius: 24))
    }

    private func statBox(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8).padding(.horizontal, 10)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 12))
    }

    // MARK: - 设置步骤
    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("怎么设置（30 秒）")
                .font(.system(size: 13, weight: .semibold))

            step(1, "点下方按钮，选择「iCloud 云盘」里的一个文件夹（建议新建「7记账」）")
            step(2, "选好后立刻备份一次，之后每次记账都会自动上传")
            step(3, "换手机时，在新手机上重新选同一个文件夹，账目自动恢复")

            Button {
                showFolderPicker = true
            } label: {
                HStack {
                    Image(systemName: "folder.badge.plus")
                    Text("选择 iCloud 文件夹")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .opacity(0.35)
                }
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 14).padding(.vertical, 12)
                .glassEffect(.regular.tint(Theme.brand.opacity(0.18)).interactive(), in: .rect(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private var actionsCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    Task { await backup.backupNow() }
                } label: {
                    Label("立即备份", systemImage: "arrow.up.to.line")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .glassEffect(.regular.tint(Theme.brand.opacity(0.18)).interactive(), in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                Button {
                    Task { await backup.pull(force: true) }
                } label: {
                    Label("从 iCloud 恢复", systemImage: "arrow.down.to.line")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .glassEffect(.regular.tint(Theme.mint.opacity(0.18)).interactive(), in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 16) {
                Button("更换文件夹") { showFolderPicker = true }
                Button("断开") { backup.disconnect() }
                    .foregroundStyle(Theme.danger)
                Spacer()
            }
            .font(.system(size: 11))
            .buttonStyle(.plain)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    // MARK: - 说明
    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("同步规则")
                .font(.system(size: 12, weight: .semibold))
            bullet("备份文件：7jizhang-backup.json，就在你选的文件夹里")
            bullet("同一笔账按修改时间取最新，不会重复")
            bullet("删除的账目会在所有设备上一起删除，不会复活")
            bullet("换手机后余额也会一并恢复")
            Text("说明：免费签名无法申请 iCloud 容器权限，所以需要你手动选一个文件夹。文件真实存在于 iCloud Drive，会自动上传云端。")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private func step(_ n: Int, _ text: String) -> some View {
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

    private func bullet(_ t: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Circle().fill(.secondary.opacity(0.5)).frame(width: 3, height: 3).padding(.top, 6)
            Text(t).font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 灵动岛诊断详情
struct IslandDiagnosticsView: View {
    private var _liveActivity = State(wrappedValue: LiveActivityController.shared)
    private var liveActivity: LiveActivityController { _liveActivity.wrappedValue }

    var body: some View {
        let d = liveActivity.diagnostics()
        ScrollView {
            VStack(spacing: 16) {
                summary(d)
                rows(d)
                explains
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle("灵动岛诊断")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func summary(_ d: LiveActivityController.Diagnostics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: d.verdict == "配置正常" ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(d.verdict == "配置正常" ? Theme.mint : Theme.warm)
                Text(d.verdict)
                    .font(.system(size: 13, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let ok = d.lastResult {
                Text("最近创建：\(ok)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular.tint((d.verdict == "配置正常" ? Theme.mint : Theme.warm).opacity(0.12)),
                     in: .rect(cornerRadius: 22))
    }

    private func rows(_ d: LiveActivityController.Diagnostics) -> some View {
        VStack(spacing: 0) {
            row("系统实时活动", d.systemEnabled ? "已允许" : "未允许", d.systemEnabled)
            Divider().padding(.leading, 12).opacity(0.3)
            row("App 内开关", d.userEnabled ? "开启" : "关闭", d.userEnabled)
            Divider().padding(.leading, 12).opacity(0.3)
            row("灵动岛扩展",
                d.extensionInstalled ? (d.widgetBundleIDs.first ?? "已安装") : "缺失（无扩展版本）",
                d.extensionInstalled)
            Divider().padding(.leading, 12).opacity(0.3)
            row("Bundle ID 匹配", d.prefixMatched ? "匹配" : "不匹配", d.prefixMatched)
            Divider().padding(.leading, 12).opacity(0.3)
            row("当前活动数", "\(d.activeCount)", d.activeCount >= 0)
            if let err = d.lastError {
                Divider().padding(.leading, 12).opacity(0.3)
                HStack(alignment: .top, spacing: 8) {
                    Text("最近失败").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(err)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.danger)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private func row(_ title: String, _ value: String, _ ok: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(ok ? Theme.mint : Theme.danger)
            Text(title).font(.system(size: 12))
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    private var explains: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("为什么要点开才看得到大卡片？")
                .font(.system(size: 12, weight: .semibold))
            Text("iOS 规定 App 不能主动展开灵动岛，只有用户长按才会展开。所以记账完成后：灵动岛先显示「分类图标 + 金额」的紧凑形态，长按可看到金额、分类、商户、余额、时间的完整卡片；锁屏上也会出现完整卡片。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("如果显示异常，先检查：设置 → 7记账 → 实时活动 → 允许。")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}
