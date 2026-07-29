import AppIntents
import SwiftUI

/// The memo key, wired to the outside of the machine.
///
/// A hardware recorder's memo button works whether or not you were already
/// holding it. This is the same button on the Action button, the Lock Screen,
/// Control Center and Siri — so the app being closed is not a reason to miss
/// the thing you wanted to keep.
struct StartMemoIntent: AppIntent {
    static var title: LocalizedStringResource = "new memo"
    static var description = IntentDescription(
        "wakes tepevësen and starts recording immediately."
    )
    /// Recording needs the app foregrounded; nothing is captured behind your back.
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        DeviceState.shared.powerOn()
        DeviceState.shared.memo()
        return .result()
    }
}

struct StopRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "stop recording"
    static var description = IntentDescription("stops the tape and files it.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        DeviceState.shared.stopButton()
        return .result()
    }
}

struct TepevesenShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartMemoIntent(),
            phrases: [
                "new memo in \(.applicationName)",
                "record with \(.applicationName)",
                "start \(.applicationName)"
            ],
            shortTitle: "new memo",
            systemImageName: "record.circle"
        )
        AppShortcut(
            intent: StopRecordingIntent(),
            phrases: ["stop \(.applicationName)"],
            shortTitle: "stop",
            systemImageName: "stop.circle"
        )
    }
}
