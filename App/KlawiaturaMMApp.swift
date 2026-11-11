import SwiftUI

@main
struct KlawiaturaMMApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .onOpenURL { model.handle(url: $0) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        model.refresh()
                        model.sync()
                    }
                }
                .onAppear {
                    model.refresh()
                    model.sync()
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView(selection: $model.selectedTab) {
            SetupView()
                .tabItem { Label("Start", systemImage: "keyboard") }
                .tag(0)
            LearnedWordsView()
                .tabItem { Label("Słowa", systemImage: "text.book.closed") }
                .tag(1)
            BlockedWordsView()
                .tabItem { Label("Zablokowane", systemImage: "nosign") }
                .tag(2)
            DictationView()
                .tabItem { Label("Dyktowanie", systemImage: "mic") }
                .tag(3)
        }
    }
}
