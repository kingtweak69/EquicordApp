import SwiftUI

enum EquicordTab: String, CaseIterable {
    case servers = "Servers"
    case messages = "Messages"
    case search = "Search"
    case profile = "You"

    var icon: String {
        switch self {
        case .servers: return "bubble.left.and.bubble.right.fill"
        case .messages: return "message.fill"
        case .search: return "magnifyingglass"
        case .profile: return "person.crop.circle.fill"
        }
    }

    var command: String {
        switch self {
        case .servers: return "servers"
        case .messages: return "messages"
        case .search: return "search"
        case .profile: return "profile"
        }
    }
}

extension Notification.Name {
    static let equicordNavigation = Notification.Name("equicordNavigation")
}

struct ContentView: View {
    private let discordURL = URL(string: "https://discord.com/app")!
    @State private var selectedTab: EquicordTab = .messages

    var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.059, blue: 0.071)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                EquicordWebView(url: discordURL)
                    .background(Color(red: 0.055, green: 0.059, blue: 0.071))

                bottomBar
            }
        }
        .preferredColorScheme(.dark)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                sendCommand("back")
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 36, height: 36)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Equicord")
                    .font(.headline)
                    .fontWeight(.semibold)

                Text(selectedTab.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                sendCommand("reload")
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 36, height: 36)
            }

            Button {
                sendCommand("drawer")
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 36, height: 36)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(height: 52)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.25)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            ForEach(EquicordTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                    sendCommand(tab.command)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 19, weight: selectedTab == tab ? .bold : .medium))

                        Text(tab.rawValue)
                            .font(.system(size: 10, weight: selectedTab == tab ? .semibold : .regular))
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(selectedTab == tab ? Color.white : Color.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 7)
        .padding(.bottom, 4)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider().opacity(0.25)
        }
    }

    private func sendCommand(_ command: String) {
        NotificationCenter.default.post(
            name: .equicordNavigation,
            object: command
        )
    }
}
