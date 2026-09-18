import SwiftUI
import WebKit
import CryptoKit

@MainActor final class OnlineBridge: NSObject, WKScriptMessageHandler, WKScriptMessageHandlerWithReply, WKNavigationDelegate {
    private(set) var webView: WKWebView!
    var onEvent: ((String, [String: Any]) -> Void)?
    private var ready = false
    private var queue: [[String: Any]] = []
    private let session: URLSession

    override init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        config.httpCookieStorage = nil
        session = URLSession(configuration: config)
        super.init()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(self, name: "event")
        configuration.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "request")
        configuration.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "digest")
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.isInspectable = false
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Bridge") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }
    func send(_ payload: [String: Any]) {
        guard ready else { queue.append(payload); return }
        Task { @MainActor in
            do { _ = try await webView.callAsyncJavaScript("await window.nativeCommand(message)", arguments: ["message": payload], in: nil, contentWorld: .page) }
            catch { onEvent?("error", ["key": "error.connectFailed"]) }
        }
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        if type == "ready" {
            ready = true
            let pending = queue; queue.removeAll()
            for item in pending { send(item) }
        }
        onEvent?(type, body)
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        guard message.frameInfo.isMainFrame else { replyHandler(nil, "Invalid frame"); return }
        if message.name == "digest", let text = message.body as? String, text.utf8.count < 4096 {
            replyHandler(SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined(), nil)
            return
        }
        guard message.name == "request", let data = message.body as? [String: Any],
              let path = data["path"] as? String, path.hasPrefix("/api/"), !path.contains(".."),
              let url = URL(string: "https://us-central1-enotix.cloudfunctions.net/twivvy-signal" + path),
              url.host == "us-central1-enotix.cloudfunctions.net",
              let method = data["method"] as? String, ["GET", "POST", "DELETE"].contains(method) else {
            replyHandler(nil, "Invalid request"); return
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body = data["body"] as? String {
            guard body.utf8.count < 128_000 else { replyHandler(nil, "Request too large"); return }
            request.httpBody = Data(body.utf8)
        }
        Task { @MainActor in
            do {
                let (body, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, body.count < 1_000_000,
                      let string = String(data: body, encoding: .utf8) else { replyHandler(nil, "Invalid response"); return }
                replyHandler(["status": http.statusCode, "body": string], nil)
            } catch { replyHandler(nil, "Connection unavailable") }
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.request.url?.isFileURL == true ? .allow : .cancel)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        ready = false
        onEvent?("terminated", [:])
        webView.reload()
    }
}

struct ProtocolHost: UIViewRepresentable {
    let bridge: OnlineBridge
    func makeUIView(context: Context) -> WKWebView { bridge.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
