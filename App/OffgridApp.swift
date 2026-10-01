import SwiftData
import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier == ModelStore.backgroundSessionID else { return completionHandler() }
        Task { @MainActor in AppModel.shared.store.backgroundCompletionHandler = completionHandler }
    }

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        Task { @MainActor in
            if !ChatController.shared.isGenerating { await AppModel.shared.releaseMemory() }
        }
    }
}

extension ChatController {
    static let shared = ChatController()
}

@main
struct OffgridApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(AppModel.shared)
                .environment(ChatController.shared)
        }
        .modelContainer(for: [Conversation.self, Message.self])
        .onChange(of: scenePhase) { _, phase in
            // iOS forbids GPU work in the background, so stop generating when the app leaves the screen.
            if phase == .background { ChatController.shared.stop() }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @State private var showOnboarding = false

    var body: some View {
        ConversationListView()
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView { showOnboarding = false }
            }
            .onAppear {
                app.refreshSelection()
                showOnboarding = app.store.installedModels.isEmpty
            }
            .onChange(of: app.store.installedModels.map(\.id)) { _, _ in
                app.refreshSelection()
            }
    }
}
