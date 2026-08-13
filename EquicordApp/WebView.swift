import SwiftUI
import WebKit
import AuthenticationServices

struct EquicordWebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()

        // 1. Greasemonkey shims. The Equicord userscript build declares
        //    @grant unsafeWindow and @grant GM_xmlhttpRequest, neither of
        //    which exists in a bare WKWebView. These must be in place before
        //    the bundle evaluates or it throws on load.
        contentController.addUserScript(
            WKUserScript(
                source: Self.greasemonkeyShim,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )

        // 2. Equicord itself. Declares @run-at document-start because it has
        //    to install its webpack patches before Discord's bundle boots.
        if let bundleSource = Self.loadScript(named: "Equicord.user") {
            contentController.addUserScript(
                WKUserScript(
                    source: bundleSource,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true
                )
            )
        } else {
            print("Equicord: Equicord.user.js missing from bundle — no plugins will load")
        }

        // 3. Mobile skin last, once the DOM exists.
        if let skinSource = Self.loadScript(named: "equicord.user") {
            contentController.addUserScript(
                WKUserScript(
                    source: skinSource,
                    injectionTime: .atDocumentEnd,
                    forMainFrameOnly: true
                )
            )
        }

        contentController.addScriptMessageHandler(
            context.coordinator,
            contentWorld: .page,
            name: "equicordXhr"
        )

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .default()

        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        // Required: Equicord patches the desktop web bundle. Discord's mobile
        // site is a different client with different webpack modules, so the
        // patches match nothing there and no plugins load.
        preferences.preferredContentMode = .desktop
        configuration.defaultWebpagePreferences = preferences

        let webView = WKWebView(frame: .zero, configuration: configuration)
        context.coordinator.webView = webView
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.customUserAgent = nil

        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.keyboardDismissMode = .interactive
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear

        context.coordinator.startListening()

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if uiView.url == nil {
            uiView.load(URLRequest(url: url))
        }
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.stopListening()
        uiView.configuration.userContentController
            .removeScriptMessageHandler(forName: "equicordXhr", contentWorld: .page)
        uiView.navigationDelegate = nil
        uiView.uiDelegate = nil
        coordinator.webView = nil
    }

    private static func loadScript(named name: String) -> String? {
        guard let path = Bundle.main.path(forResource: name, ofType: "js"),
              let source = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }
        return source
    }

    private static let greasemonkeyShim = """
    (function () {
      if (window.__equicordShimInstalled) return;
      window.__equicordShimInstalled = true;

      // Equicord's userscript build assigns to unsafeWindow to escape the
      // sandbox. WKWebView user scripts already run in the page world, so
      // pointing it at window is both correct and sufficient.
      window.unsafeWindow = window;

      // GM_xmlhttpRequest is used for cross-origin fetches that CORS would
      // otherwise block. Proxy it through the native side.
      window.GM_xmlhttpRequest = function (details) {
        var handler = window.webkit
          && window.webkit.messageHandlers
          && window.webkit.messageHandlers.equicordXhr;

        if (!handler) {
          if (details && details.onerror) details.onerror({ error: "no native bridge" });
          return;
        }

        handler.postMessage({
          method: (details.method || "GET").toUpperCase(),
          url: details.url,
          headers: details.headers || {},
          data: typeof details.data === "string" ? details.data : null
        }).then(function (res) {
          if (details.onload) {
            details.onload({
              status: res.status,
              statusText: String(res.status),
              responseText: res.body,
              response: res.body,
              responseHeaders: res.headers || "",
              finalUrl: res.url || details.url,
              readyState: 4
            });
          }
        }).catch(function (err) {
          if (details.onerror) details.onerror({ error: String(err) });
        });
      };

      window.GM = window.GM || {};
      window.GM.xmlHttpRequest = window.GM_xmlhttpRequest;
    })();
    """

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandlerWithReply {
        weak var webView: WKWebView?
        private var observer: NSObjectProtocol?
        private var hasProbedEquicord = false

        func startListening() {
            guard observer == nil else { return }

            observer = NotificationCenter.default.addObserver(
                forName: .equicordNavigation,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let command = notification.object as? String else { return }
                self?.handle(command)
            }
        }

        func stopListening() {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
                self.observer = nil
            }
        }

        // MARK: - GM_xmlhttpRequest bridge

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage,
            replyHandler: @escaping (Any?, String?) -> Void
        ) {
            guard message.name == "equicordXhr",
                  let payload = message.body as? [String: Any],
                  let urlString = payload["url"] as? String,
                  let requestURL = URL(string: urlString) else {
                replyHandler(nil, "malformed request")
                return
            }

            var request = URLRequest(url: requestURL)
            request.httpMethod = payload["method"] as? String ?? "GET"

            if let headers = payload["headers"] as? [String: String] {
                for (key, value) in headers {
                    request.setValue(value, forHTTPHeaderField: key)
                }
            }

            if let body = payload["data"] as? String {
                request.httpBody = body.data(using: .utf8)
            }

            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    replyHandler(nil, error.localizedDescription)
                    return
                }

                let http = response as? HTTPURLResponse
                let headerText = (http?.allHeaderFields as? [String: String])?
                    .map { "\($0.key): \($0.value)" }
                    .joined(separator: "\r\n") ?? ""

                replyHandler([
                    "status": http?.statusCode ?? 0,
                    "body": String(data: data ?? Data(), encoding: .utf8) ?? "",
                    "headers": headerText,
                    "url": http?.url?.absoluteString ?? urlString
                ], nil)
            }.resume()
        }

        // MARK: - Navigation

        private func probeEquicord() {
            guard !hasProbedEquicord, let webView else { return }
            hasProbedEquicord = true

            webView.evaluateJavaScript("typeof window.Vencord !== 'undefined'") { result, _ in
                if (result as? Bool) == true {
                    print("Equicord: loaded — plugins active")
                } else {
                    print("Equicord: NOT loaded — window.Vencord is undefined")
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            probeEquicord()
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil,
               let requestURL = navigationAction.request.url {
                webView.load(URLRequest(url: requestURL))
            }
            return nil
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let destination = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            let scheme = destination.scheme?.lowercased()
            if scheme == "http" || scheme == "https" || scheme == "about" || scheme == "data" || scheme == "blob" {
                decisionHandler(.allow)
                return
            }

            if UIApplication.shared.canOpenURL(destination) {
                UIApplication.shared.open(destination)
            }
            decisionHandler(.cancel)
        }

        private func handle(_ command: String) {
            guard let webView else { return }

            switch command {
            case "back":
                if webView.canGoBack {
                    webView.goBack()
                } else {
                    run("window.EquicordMobile && window.EquicordMobile.closeDrawer();")
                }

            case "reload":
                webView.reload()

            default:
                let escaped = command.replacingOccurrences(of: "'", with: "\\'")
                run("window.EquicordMobile && window.EquicordMobile.navigate('\(escaped)');")
            }
        }

        private func run(_ javascript: String) {
            webView?.evaluateJavaScript(javascript) { _, error in
                if let error {
                    print("Equicord JS error: \(error.localizedDescription)")
                }
            }
        }
    }
}
