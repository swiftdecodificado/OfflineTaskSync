import SwiftUI

@main
struct TasksApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var environment = AppEnvironment()
    @State private var preferences = AppPreferences()

    var body: some Scene {
        WindowGroup {
            TaskListView()
                .tint(Theme.accent)
                .preferredColorScheme(effectiveColorScheme)
                .environment(\.locale, effectiveLocale)
                .environment(preferences)
                .environment(environment.viewModel)
                .environment(environment.syncCoordinator)
                .environment(environment.networkMonitor)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if phase == .active {
                        environment.syncCoordinator.resume()
                        Task { await environment.viewModel.reconcileReminders() }
                    } else {
                        environment.syncCoordinator.suspend()
                        environment.persistPendingTitleEdits()
                    }
                }
        }
    }

    private var effectiveLocale: Locale {
        #if DEBUG
        let values = ProcessInfo.processInfo.environment
        if values["TASKS_REGRESSION_TEST_HOST"] == "1", let identifier = values["TASKS_REGRESSION_LOCALE"] {
            return Locale(identifier: identifier)
        }
        #endif
        return preferences.language.locale
    }

    private var effectiveColorScheme: ColorScheme? {
        #if DEBUG
        let values = ProcessInfo.processInfo.environment
        if values["TASKS_REGRESSION_TEST_HOST"] == "1" {
            switch values["TASKS_REGRESSION_COLOR_SCHEME"] {
            case "light": return .light
            case "dark": return .dark
            default: return nil
            }
        }
        #endif
        return preferences.appearance.colorScheme
    }
}
