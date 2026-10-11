import SwiftUI
import UIKit

enum BackgroundSessionBridge {
    static var completionHandler: (() -> Void)?
}

final class ArtCraftAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier == ModelDownloadStore.backgroundID else {
            completionHandler()
            return
        }
        BackgroundSessionBridge.completionHandler = completionHandler
    }
}

@main
struct ArtCraftMobileOfflineApp: App {
    @UIApplicationDelegateAdaptor(ArtCraftAppDelegate.self) private var appDelegate
    @StateObject private var store = EditorStore()
    @StateObject private var modelStore = ModelDownloadStore()

    var body: some Scene {
        WindowGroup {
            EditorView()
                .environmentObject(store)
                .environmentObject(modelStore)
                .preferredColorScheme(.dark)
        }
    }
}
