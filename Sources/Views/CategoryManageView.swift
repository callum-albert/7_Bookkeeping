import SwiftUI

struct CategoryManageView: View {
    private var _dismiss = Environment(\.dismiss)
    private var dismiss: DismissAction { _dismiss.wrappedValue }
    private var _kind: State<EntryKind>
    private var kind: EntryKind { get { _kind.wrappedValue } nonmutating set { _kind.wrappedValue = newValue } }
    private var _name = State(wrappedValue: "")
    private var name: String { get { _name.wrappedValue } nonmutating set { _name.wrappedValue = newValue } }
    private var _error = State(wrappedValue: "")
    private var error: String { get { _error.wrappedValue } nonmutating set { _error.wrappedValue = newValue } }
    init(initialKind: EntryKind = .expense) { _kind = State(wrappedValue: initialKind) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("分类类型", selection: _kind.projectedValue) {
                        ForEach(EntryKind.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                    VStack(spacing: 12) {
                        TextField("新分类名称（最多20字）", text: _name.projectedValue)
                        Button("添加分类") {
                            if CategoryStore.shared.add(name, kind: kind) != nil { name = ""; error = "" }
                            else { error = "请输入1–20字的名称，同一收支类型不能重名。" }
                        }.buttonStyle(.borderedProminent).tint(Theme.brand)
                        if !error.isEmpty { Text(error).font(.footnote).foregroundStyle(Theme.danger) }
                    }.padding(16).glassEffect(.regular, in: .rect(cornerRadius: 20))
                    ForEach(CategoryStore.shared.categories.filter { $0.kind == kind }) { category in
                        HStack {
                            Label(category.title, systemImage: category.symbol)
                            Spacer()
                            Button("删除", role: .destructive) { CategoryStore.shared.remove(category) }
                        }.padding(16).glassEffect(.regular, in: .rect(cornerRadius: 16))
                    }
                    Text("删除后不再用于新账目；历史账目的分类名称和统计保持不变。内置分类不受影响。")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(18)
            }.background(AppBackground()).navigationTitle("自定义分类")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }
}
