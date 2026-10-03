import SwiftUI
import WebKit
import AVFoundation

final class WebModel: ObservableObject {
    @Published var firstLoadDone = false
    @Published var offlineMessage: String? = nil
    @Published var pageColor: Color? = nil
    @Published var pageIsDark = false
    weak var webView: WKWebView?
    private var colorTimer: Timer?

    /// 每秒看一次网页现在的底色，状态栏的文字深浅跟着它走
    func startColorWatch() {
        colorTimer?.invalidate()
        colorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollColor()
        }
        pollColor()
    }

    private func pollColor() {
        guard let wv = webView else { return }
        let js = "(function(){var t=function(c){return !c||c==='transparent'||c==='rgba(0, 0, 0, 0)'};var b=getComputedStyle(document.body).backgroundColor;if(t(b))b=getComputedStyle(document.documentElement).backgroundColor;return t(b)?'':b})()"
        wv.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self = self, let str = result as? String else { return }
            guard let parsed = WebModel.parseColor(str) else { return }
            if self.pageColor != parsed.0 { self.pageColor = parsed.0 }
            if self.pageIsDark != parsed.1 { self.pageIsDark = parsed.1 }
        }
    }

    /// 只认 rgb()/rgba()/#hex；透明色不算颜色 (网页还没上色时会读到它)
    static func parseColor(_ s: String) -> (Color, Bool)? {
        var r: Double = 0
        var g: Double = 0
        var b: Double = 0
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("#") {
            var hex = String(t.dropFirst())
            if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
            guard hex.count >= 6, let v = UInt64(hex.prefix(6), radix: 16) else { return nil }
            r = Double((v >> 16) & 0xff) / 255.0
            g = Double((v >> 8) & 0xff) / 255.0
            b = Double(v & 0xff) / 255.0
        } else if t.hasPrefix("rgb") {
            let parts = t.components(separatedBy: CharacterSet(charactersIn: "(),"))
            let nums: [Double] = parts.compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard nums.count >= 3 else { return nil }
            if nums.count >= 4 && nums[3] <= 0.01 { return nil }
            r = nums[0] / 255.0
            g = nums[1] / 255.0
            b = nums[2] / 255.0
        } else {
            return nil
        }
        let lum: Double = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return (Color(red: r, green: g, blue: b), lum < 0.45)
    }

    func reload() {
        offlineMessage = nil
        if let wv = webView, wv.url != nil {
            wv.reload()
        } else {
            webView?.load(URLRequest(url: Config.home))
        }
    }
}

struct WebView: UIViewRepresentable {
    @ObservedObject var model: WebModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()                    // cookie 持久：登录一次就记住
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.applicationNameForUserAgent = "Mobile/15E148 Safari/604.1" + Config.uaSuffix
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = true

        // 网页 → 壳：window.webkit.messageHandlers.shell.postMessage({cmd:'reload'})
        cfg.userContentController.add(context.coordinator, name: "shell")

        // 告诉网页"你在壳里"：viewport-fit=cover 让 env(safe-area-inset-*) 有值；<html> 加一个类名
        let inject = """
        (function(){try{
          var m=document.querySelector('meta[name=viewport]');
          if(!m){m=document.createElement('meta');m.name='viewport';(document.head||document.documentElement).appendChild(m);m.content='width=device-width,initial-scale=1.0,viewport-fit=cover';}
          else if(m.content.indexOf('viewport-fit')<0){m.content=m.content+',viewport-fit=cover';}
          document.documentElement.classList.add('\(Config.htmlClass)');
        }catch(e){}})();
        """
        let script = WKUserScript(source: inject, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        cfg.userContentController.addUserScript(script)

        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = false       // 左边缘右滑交给下面的手势
        let edge = UIScreenEdgePanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.edgeBack(_:)))
        edge.edges = .left
        wv.addGestureRecognizer(edge)
        wv.scrollView.bounces = true                          // 下拉刷新需要它
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.backgroundColor = .clear
        if #available(iOS 16.4, *) { wv.isInspectable = true }  // 有 Mac 的话可以用 Safari 连进来调试

        // 下拉刷新
        let rc = UIRefreshControl()
        rc.addTarget(context.coordinator, action: #selector(Coordinator.pull(_:)), for: .valueChanged)
        wv.scrollView.refreshControl = rc

        // 切到后台时音频不断
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        model.webView = wv
        context.coordinator.observeForeground(wv)
        wv.load(URLRequest(url: Config.home))
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let model: WebModel
        private var fgObserver: NSObjectProtocol?

        init(model: WebModel) { self.model = model }

        deinit {
            if let o = fgObserver { NotificationCenter.default.removeObserver(o) }
        }

        func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let d = message.body as? [String: Any], let cmd = d["cmd"] as? String else { return }
            if cmd == "reload" { model.reload() }
        }

        func observeForeground(_ wv: WKWebView) {
            fgObserver = NotificationCenter.default.addObserver(forName: .shellForeground, object: nil, queue: .main) { [weak wv] _ in
                wv?.evaluateJavaScript("document.dispatchEvent(new Event('visibilitychange'));window.dispatchEvent(new Event('focus'))", completionHandler: nil)
            }
        }

        // 左边缘右滑：拉过 60pt 或甩得够快，就执行配置里的返回 JS
        @objc func edgeBack(_ g: UIScreenEdgePanGestureRecognizer) {
            guard g.state == .ended else { return }
            let dx: CGFloat = g.translation(in: g.view).x
            let vx: CGFloat = g.velocity(in: g.view).x
            if dx > 60 || vx > 500 {
                let js = "(function(){try{" + Config.backJS + "}catch(e){history.back()}})()"
                model.webView?.evaluateJavaScript(js, completionHandler: nil)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }

        @objc func pull(_ rc: UIRefreshControl) {
            model.webView?.reload()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { rc.endRefreshing() }
        }

        // MARK: 导航：自己的域名留在壳里，外链去 Safari
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.allow); return }
            let scheme = url.scheme?.lowercased() ?? ""
            if scheme == "http" || scheme == "https" {
                let host = url.host?.lowercased() ?? ""
                let isSubframe = (navigationAction.targetFrame?.isMainFrame == false)
                if Config.inAppHosts.contains(host) || isSubframe {
                    decisionHandler(.allow); return
                }
                if navigationAction.navigationType == .linkActivated {
                    UIApplication.shared.open(url)
                    decisionHandler(.cancel); return
                }
                decisionHandler(.allow); return
            }
            if scheme == "about" || scheme == "blob" || scheme == "data" {
                decisionHandler(.allow); return
            }
            // mailto: / tel: 等交给系统
            if UIApplication.shared.canOpenURL(url) { UIApplication.shared.open(url) }
            decisionHandler(.cancel)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            model.offlineMessage = nil
            if !model.firstLoadDone {
                model.firstLoadDone = true
                model.startColorWatch()
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let ns = error as NSError
            if ns.code == NSURLErrorCancelled { return }
            if !model.firstLoadDone { model.offlineMessage = friendly(ns) }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            let ns = error as NSError
            if ns.code == NSURLErrorCancelled { return }
            if !model.firstLoadDone { model.offlineMessage = friendly(ns) }
        }

        private func friendly(_ e: NSError) -> String {
            switch e.code {
            case NSURLErrorNotConnectedToInternet: return "现在没有网络。"
            case NSURLErrorTimedOut: return "等了太久，网络可能不太好。"
            case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost: return "连不上服务器。"
            default: return e.localizedDescription
            }
        }

        // 网页进程被系统回收后自动重载
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }

        // MARK: window.open：自己的域名在当前窗口开，其它去 Safari
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                let host = url.host?.lowercased() ?? ""
                if Config.inAppHosts.contains(host) {
                    webView.load(navigationAction.request)
                } else {
                    UIApplication.shared.open(url)
                }
            }
            return nil
        }

        // MARK: alert / confirm / prompt 接成系统弹窗 (WKWebView 默认不显示)
        private func top() -> UIViewController? {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            var vc: UIViewController? = scenes.compactMap { $0.keyWindow }.first?.rootViewController
            while let p = vc?.presentedViewController { vc = p }
            return vc
        }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            guard let host = top() else { completionHandler(); return }
            let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
            host.present(a, animated: true)
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            guard let host = top() else { completionHandler(false); return }
            let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
            a.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler(true) })
            host.present(a, animated: true)
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            guard let host = top() else { completionHandler(nil); return }
            let a = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            a.addTextField { $0.text = defaultText }
            a.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(nil) })
            a.addAction(UIAlertAction(title: "好", style: .default) { [weak a] _ in completionHandler(a?.textFields?.first?.text) })
            host.present(a, animated: true)
        }

        // MARK: 相机 / 麦克风：自己的域名直接放行 (系统仍会问一次)，其它域名照常询问
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(Config.inAppHosts.contains(origin.host.lowercased()) ? .grant : .prompt)
        }
    }
}
