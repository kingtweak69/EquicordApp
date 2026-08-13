# EquicordApp

Native SwiftUI/WKWebView wrapper for Discord.

## Build with Codemagic

The repository includes both `project.yml` (XcodeGen source) and a checked-in `EquicordApp.xcodeproj`.

The production Codemagic workflow uses automatic iOS signing. In Codemagic, create/connect an App Store Connect API key integration named `codemagic`, then run the `ios-equicord` workflow.

Bundle ID:

`com.kingtweak69.EquicordApp`

The workflow uses an Ad Hoc distribution profile so the resulting IPA can be installed on registered devices. For TestFlight/App Store distribution, change `distribution_type` to `app_store`.

The unsigned workflow is useful for verifying the project compiles before configuring Apple signing.

## Passkeys

The WebView uses the real iOS/WebKit user agent and requests browser passkey authorization on iOS 18+. WebKit automatically handles WebAuthentication challenges for WKWebView browser apps.
