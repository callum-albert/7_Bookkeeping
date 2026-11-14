import SwiftUI

struct RootView: View {
    private var _store = State(wrappedValue: LedgerStore.shared)
    private var store: LedgerStore { get { _store.wrappedValue } nonmutating set { _store.wrappedValue = newValue } }
    private var _bookkeeper = State(wrappedValue: AutoBookkeeper.shared)
    private var bookkeeper: AutoBookkeeper { get { _bookkeeper.wrappedValue } nonmutating set { _bookkeeper.wrappedValue = newValue } }
    private var _showCompose = State(wrappedValue: false)
    private var showCompose: Bool { get { _showCompose.wrappedValue } nonmutating set { _showCompose.wrappedValue = newValue } }
    private var _selectedTab = State(wrappedValue: 0)
    private var selectedTab: Int { get { _selectedTab.wrappedValue } nonmutating set { _selectedTab.wrappedValue = newValue } }

    var body: some View {
        ZStack {
            AppBackground()

            TabView(selection: _selectedTab.projectedValue) {
                Tab("记账", systemImage: "square.stack.3d.up.fill", value: 0) {
                    HomeView(showCompose: _showCompose.projectedValue)
                }
                Tab("统计", systemImage: "chart.bar.xaxis", value: 1) {
                    StatsView()
                }
                Tab("我的", systemImage: "person.crop.circle", value: 2) {
                    NavigationStack { SettingsView() }
                }
            }
        }
        .overlay(alignment: .top) {
            ToastOverlay(toast: bookkeeper.toast)
                .padding(.top, 4)
        }
        .task {
            await NotificationService.shared.requestIfNeeded()
        }
        .sheet(isPresented: _showCompose.projectedValue) {
            ComposeView()
                .presentationDetents([.large])
                .presentationBackground(.thinMaterial)
        }
        .tint(Theme.brand)
    }
}

// MARK: - 顶部提示条
struct ToastOverlay: View {
    var toast: AutoBookkeeper.Toast?

    private var symbol: String {
        switch toast?.kind {
        case .success: return "checkmark.circle.fill"
        case .merged: return "arrow.triangle.merge"
        case .ignored: return "arrow.uturn.left.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        case nil: return "checkmark.circle.fill"
        }
    }

    private var tint: Color {
        switch toast?.kind {
        case .success: return Theme.mint
        case .merged: return Theme.brand
        case .ignored: return Theme.warm
        case .failed: return Theme.danger
        case nil: return Theme.mint
        }
    }

    var body: some View {
        ZStack {
            if let toast {
                HStack(spacing: 12) {
                    Image(systemName: symbol)
                        .font(.system(size: 22))
                        .foregroundStyle(tint)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(toast.title)
                            .font(.system(size: 14, weight: .semibold))
                        Text(toast.subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glassEffect(.regular.tint(tint.opacity(0.22)), in: .rect(cornerRadius: 22))
                .padding(.horizontal, 20)
                .transition(.move(edge: .top).combined(with: .opacity))
                .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: toast?.id)
    }
}
