import SwiftUI
import WebKit
import AuthenticationServices

struct EquicordWebView: UIViewRepresentable {
    let url: URL
    var onPasskeySupport: ((Bool) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(onPasskeySupport: onPasskeySupport)
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
        // Discord refuses to serve its web client to mobile user agents and
        // only renders the QR login on the desktop layout. Requesting desktop
        // content mode swaps in a macOS Safari UA and desktop viewport.
        configuration.defaultWebpagePreferences = preferences

        let webView = WKWebView(frame: .zero, configuration: configuration)
        context.coordinator.webView = webView
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        // Do not hand-roll a UA string here — preferredContentMode above
        // already handles it. Note this does NOT enable WebAuthn: WebKit gates
        // that on the web browser public key credential entitlement, not the
        // user agent.
        webView.customUserAgent = nil

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
        private var hasProbedWebAuthn = false
        private let onPasskeySupport: ((Bool) -> Void)?

        @available(iOS 18.0, *)
        private lazy var passkeyManager = ASAuthorizationWebBrowserPublicKeyCredentialManager()

        init(onPasskeySupport: ((Bool) -> Void)? = nil) {
            self.onPasskeySupport = onPasskeySupport
            super.init()
        }

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

            if #available(iOS 26.2, *) {
                guard ASAuthorizationWebBrowserPublicKeyCredentialManager.isDeviceConfiguredForPasskeys else {
                    print("Equicord: device is not configured for passkeys")
                    return
                }
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

        // WebKit only injects the WebAuthn interfaces when the host app is
        // entitled. Probing for them is the only reliable way to know whether
        // passkey sign-in can actually succeed in this build.
        private func probeWebAuthnSupport() {
            guard !hasProbedWebAuthn, let webView else { return }
            hasProbedWebAuthn = true

            let probe = """
            (function () {
              return typeof window.PublicKeyCredential !== 'undefined'
                  && !!(navigator.credentials && navigator.credentials.get);
            })();
            """

            webView.evaluateJavaScript(probe) { [weak self] result, _ in
                let supported = (result as? Bool) ?? false

                if supported {
                    print("Equicord: WebAuthn is available — passkey sign-in should work")
                } else {
                    print("""
                    Equicord: WebAuthn is NOT available in this WKWebView.
                    This build does not carry an Apple-issued profile with
                    com.apple.developer.web-browser.public-key-credential, so
                    Discord will not offer passkey sign-in. Use password + 2FA,
                    or scan the QR code on the login page with the official
                    Discord app on another device.
                    """)
                }

                DispatchQueue.main.async {
                    self?.onPasskeySupport?(supported)
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            probeWebAuthnSupport()
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
