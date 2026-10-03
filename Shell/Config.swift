import Foundation

/// 所有可调的东西都从 project.yml 里读 (最终进 Info.plist)，这里不用改。
enum Config {
    private static func text(_ key: String) -> String? {
        guard let s = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// 打开 app 时加载的网址
    static let home: URL = {
        if let s = text("ShellHomeURL"), let u = URL(string: s) { return u }
        return URL(string: "https://example.com/")!
    }()

    /// 这些域名留在 app 里打开，其它域名的链接交给 Safari
    static let inAppHosts: Set<String> = {
        var hosts = Set<String>()
        if let h = home.host?.lowercased() { hosts.insert(h) }
        if let extra = Bundle.main.object(forInfoDictionaryKey: "ShellExtraHosts") as? [String] {
            for e in extra {
                let t = e.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !t.isEmpty { hosts.insert(t) }
            }
        }
        return hosts
    }()

    /// User-Agent 末尾追加的标识，网页可以用它认出自己在壳里
    static let uaSuffix: String = " " + (text("ShellUserAgentTag") ?? "webshell-ios")

    /// 加在 <html> 上的类名 (只保留字母、数字、- 和 _)
    static let htmlClass: String = {
        let raw = text("ShellHTMLClass") ?? "in-ios-shell"
        let ok = raw.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return ok.isEmpty ? "in-ios-shell" : ok
    }()

    /// 左边缘右滑时执行的 JS
    static let backJS: String = text("ShellBackJS") ?? "history.back()"

    /// 断网页上显示的名字
    static let displayName: String = text("CFBundleDisplayName") ?? "App"
}
