import SwiftUI

struct ContentView: View {
    @StateObject private var model = WebModel()

    var body: some View {
        ZStack {
            (model.pageColor ?? Color("LaunchBackground")).ignoresSafeArea()
            WebView(model: model)
                .opacity(model.firstLoadDone ? 1 : 0)
                .animation(.easeOut(duration: 0.3), value: model.firstLoadDone)
            if let message = model.offlineMessage {
                OfflineView(message: message) { model.reload() }
            }
        }
        // 网页铺满整块屏幕 (背景可以延伸到刘海下面)。
        // 内容要不要往下让出状态栏，由网页自己用 env(safe-area-inset-top) 决定，见 web-snippet.css
        .ignoresSafeArea()
        .preferredColorScheme(model.pageIsDark ? .dark : .light)
    }
}

/// 断网或首屏打不开时显示的一页
struct OfflineView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(Config.displayName)
                .font(.system(size: 26, weight: .light, design: .serif))
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button(action: retry) {
                Text("再试一次")
                    .font(.system(size: 13))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("LaunchBackground"))
    }
}
