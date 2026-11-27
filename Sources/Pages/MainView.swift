import SwiftUI

struct MainView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        TabView(selection: $app.tab) {
            NavigationStack {
                SessionsView()
            }
            .tabItem { Label("会话", systemImage: "bubble.left.and.text.bubble.right") }
            .tag(0)

            NavigationStack {
                ConnectionsView()
            }
            .tabItem { Label("连接", systemImage: "point.3.connected.trianglepath.dotted") }
            .tag(1)
        }
        .tint(Theme.accent)
        .overlay(alignment: .bottom) {
            if let msg = app.toast {
                Text(msg)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.primaryText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(hex: "#1E2A3D"), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, 80)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: app.toast)
    }
}
