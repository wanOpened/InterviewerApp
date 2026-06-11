import SwiftUI

@main
struct InterviewerAppApp: App {
    var body: some Scene {
        WindowGroup {
            if DesignGalleryGate.isEnabled {
                DesignGalleryRootView()
            } else {
                HomeView()
            }
        }
    }
}
