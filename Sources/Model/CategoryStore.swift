import Foundation
import Observation

/// 自定义分类名称包含在分类标识中，删除分类也不会让历史账目丢失名称。
@Observable
final class CategoryStore {
    static let shared = CategoryStore()
    private(set) var categories: [Category] = []
    private(set) var deleted: [String] = []
    private let fileURL: URL
    private struct State: Codable { var categories: [Category]; var deleted: [String] }

    init() {
        fileURL = LedgerStore.storageDirectory.appendingPathComponent("categories.json")
        if let data = try? Data(contentsOf: fileURL), let state = try? JSONDecoder().decode(State.self, from: data) {
            categories = state.categories; deleted = state.deleted
        }
    }
    @discardableResult
    func add(_ name: String, kind: EntryKind) -> Category? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 20,
              !Category.builtIns.contains(where: { $0.kind == kind && $0.title == name }),
              !categories.contains(where: { $0.kind == kind && $0.title == name }) else { return nil }
        let category = Category.custom(name, kind: kind)
        categories.append(category); persist()
        return category
    }
    func remove(_ category: Category) {
        guard category.isCustom else { return }
        categories.removeAll { $0 == category }
        if !deleted.contains(category.rawValue) { deleted.append(category.rawValue) }
        persist()
    }
    func merge(_ incoming: [Category], deleted tombstones: [String]) {
        let previousCategories = categories, previousDeleted = Set(deleted)
        deleted = Array(Set(deleted + tombstones))
        var known = Set(categories)
        for category in incoming where category.isCustom && !deleted.contains(category.rawValue) && !known.contains(category) {
            categories.append(category); known.insert(category)
        }
        categories.removeAll { deleted.contains($0.rawValue) }
        if previousCategories != categories || previousDeleted != Set(deleted) { persist(notify: false) }
    }
    private func persist(notify: Bool = true) {
        Category.MerchantMemory.forget(categories: Set(deleted))
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(State(categories: categories, deleted: deleted)) { try? data.write(to: fileURL, options: .atomic) }
        if notify { LedgerStore.shared.onDataChanged?() }
    }
}
