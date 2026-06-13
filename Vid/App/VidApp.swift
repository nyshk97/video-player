import SwiftUI

@main
struct VidApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            VideoLibraryView()
        }
    }
}
