import SwiftUI

@main
struct ShellApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { phase in
            // 回到前台时通知网页一声 (壳里 visibilitychange 有时不触发)
            if phase == .active {
                NotificationCenter.default.post(name: .shellForeground, object: nil)
            }
        }
    }
}

extension Notification.Name {
    static let shellForeground = Notification.Name("shellForeground")
}
