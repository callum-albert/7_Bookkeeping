import Foundation
import Observation

/// 从 GitHub Releases 检查更新
/// IPA 需要重签，所以这里只负责"发现新版本 + 给出下载入口"
@MainActor
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    struct Release {
        var version: String
        var notes: String
        var downloadURL: URL
        var pageURL: URL
    }

    private(set) var latest: Release?
    private(set) var lastChecked: Date?
    private(set) var isChecking = false
    private(set) var error: String?

    private let repo = "callum-albert/7_Bookkeeping"

    var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }

    var hasUpdate: Bool {
        guard let latest else { return false }
        return Self.compare(latest.version, currentVersion) > 0
    }

    /// App 启动时调用：一小时内只查一次
    func checkIfNeeded() {
        if let last = lastChecked, Date().timeIntervalSince(last) < 3600 { return }
        Task { await check() }
    }

    func check() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        do {
            var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.timeoutInterval = 15

            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                throw URLError(.cannotParseResponse)
            }

            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let notes = (json["body"] as? String) ?? ""
            let page = (json["html_url"] as? String) ?? "https://github.com/\(repo)/releases"

            var download = page
            if let assets = json["assets"] as? [[String: Any]],
               let ipa = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".ipa") == true }),
               let url = ipa["browser_download_url"] as? String {
                download = url
            }

            latest = Release(
                version: version,
                notes: notes,
                downloadURL: URL(string: download) ?? URL(string: page)!,
                pageURL: URL(string: page) ?? URL(string: "https://github.com")!
            )
            lastChecked = Date()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// 版本号比较：1.2.10 > 1.2.9
    static func compare(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y ? 1 : -1 }
        }
        return 0
    }
}
