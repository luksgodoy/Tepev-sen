import SwiftUI

@main
struct TepevesenApp: App {
    @StateObject private var device = DeviceState.shared

    var body: some Scene {
        WindowGroup {
            DeviceFace()
                .environmentObject(device)
                .statusBarHidden(false)
                .persistentSystemOverlays(.hidden)
        }
    }
}

extension DeviceState {
    /// One machine per app, the way there is one machine per desk. The memo
    /// intent needs to reach it from outside any view hierarchy.
    static let shared = DeviceState()
}
