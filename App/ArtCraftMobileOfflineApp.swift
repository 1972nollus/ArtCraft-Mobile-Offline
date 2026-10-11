import SwiftUI
@main
struct ArtCraftMobileOfflineApp: App {
    @StateObject private var store = EditorStore()
    var body: some Scene {
        WindowGroup {
            EditorView().environmentObject(store).preferredColorScheme(.dark)
        }
    }
}
