import SwiftUI

struct ContentView: View {
    private let discordURL = URL(string: "https://discord.com/app")!

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            EquicordWebView(url: discordURL)
                .edgesIgnoringSafeArea(.all)
        }
    }
}
