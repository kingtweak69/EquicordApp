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
        configuration.websiteDataStore = .default()

        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences

        let webView = WKWebView(frame: .zero, configuration: configuration)
        context.coordinator.webView = webView
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        // Let Discord see the real iOS/WebKit environment so WebAuthn can use
        // WebKit's native authentication path.
        webView.customUserAgent = nil
        webView.applicationNameForUserAgent = "EquicordApp/1.0"

        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.keyboardDismissMode = .interactive
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear

        context.coordinator.startListening()
        context.coordinator.requestPasskeyAccessIfAvailable()

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if uiView.url == nil {
            uiView.load(URLRequest(url: url))
        }
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.stopListening()
        uiView.navigationDelegate = nil
        uiView.uiDelegate = nil
        coordinator.webView = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        weak var webView: WKWebView?
        private var observer: NSObjectProtocol?

        @available(iOS 18.0, *)
        private lazy var passkeyManager = ASAuthorizationWebBrowserPublicKeyCredentialManager()

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

        func requestPasskeyAccessIfAvailable() {
            guard #available(iOS 18.0, *) else { return }
            guard ASAuthorizationWebBrowserPublicKeyCredentialManager.isDeviceConfiguredForPasskeys else {
                print("Equicord: this device is not configured for passkeys")
                return
            }

            switch passkeyManager.authorizationStateForPlatformCredentials {
            case .authorized:
                print("Equicord: browser passkey access is authorized")
            case .notDetermined:
                passkeyManager.requestAuthorizationForPublicKeyCredentials { state in
                    DispatchQueue.main.async {
                        switch state {
                        case .authorized:
                            print("Equicord: browser passkey access granted")
                        case .denied:
                            print("Equicord: browser passkey access denied")
                        case .notDetermined:
                            print("Equicord: browser passkey access still undetermined")
                        @unknown default:
                            print("Equicord: unknown passkey authorization state")
                        }
                    }
                }
            case .denied:
                print("Equicord: browser passkey access denied in Settings")
            @unknown default:
                print("Equicord: unknown passkey authorization state")
            }
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
