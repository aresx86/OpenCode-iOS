import SwiftUI

@main
struct OpenCodeApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(app)
                .preferredColorScheme(.dark)
                .onAppear { app.reload() }
        }
    }
}
