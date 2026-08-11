import SwiftUI
import WebKit

struct EquicordWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()

        if let scriptPath = Bundle.main.path(forResource: "equicord.user", ofType: "js"),
           let scriptSource = try? String(contentsOfFile: scriptPath, encoding: .utf8) {
            let userScript = WKUserScript(
                source: scriptSource,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            contentController.addUserScript(userScript)
        }

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        webView.allowsBackForwardNavigationGestures = true
        
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if uiView.url == nil {
            uiView.load(URLRequest(url: url))
        }
    }
}
