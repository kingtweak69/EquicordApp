import SwiftUI
import WebKit

struct EquicordWebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()

        if let scriptPath = Bundle.main.path(forResource: "equicord.user", ofType: "js"),
           let scriptSource = try? String(contentsOfFile: scriptPath, encoding: .utf8) {
            contentController.addUserScript(
                WKUserScript(
                    source: scriptSource,
                    injectionTime: .atDocumentEnd,
                    forMainFrameOnly: true
                )
            )
        }

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences

        let webView = WKWebView(frame: .zero, configuration: configuration)
        context.coordinator.webView = webView

        // Keep Discord's desktop-capable client, then reshape it for iPhone in injected CSS.
        // Discord's mobile-browser layout is not a stable supported target.
        webView.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
            "AppleWebKit/537.36 (KHTML, like Gecko) " +
            "Chrome/124.0.0.0 Safari/537.36 EquicordApp/1.0"

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
        coordinator.webView = nil
    }

    final class Coordinator: NSObject {
        weak var webView: WKWebView?
        private var observer: NSObjectProtocol?

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
