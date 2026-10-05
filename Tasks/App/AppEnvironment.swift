import Foundation
import UIKit

@MainActor
final class AppEnvironment {
    let persistentStore: PersistenceContainer
    let taskStore: SwiftDataTaskRepository
    let networkMonitor: NetworkMonitor
    let syncService: SyncService
    let syncCoordinator: SyncCoordinator
    let viewModel: TasksViewModel
    private var backgroundSaveID: UIBackgroundTaskIdentifier = .invalid
    private var backgroundSaveTask: Task<Void, Never>?

    convenience init() {
        #if DEBUG
        let isRegressionTest = ProcessInfo.processInfo.environment["TASKS_REGRESSION_TEST_HOST"] == "1"
        let regressionURL: URL?
        if isRegressionTest,
           let value = ProcessInfo.processInfo.environment["TASKS_REGRESSION_STORE_ID"],
           let id = UUID(uuidString: value) {
            regressionURL = FileManager.default.temporaryDirectory.appendingPathComponent("Regression-\(id.uuidString).store")
        } else {
            regressionURL = nil
        }
        #else
        let isRegressionTest = false
        let regressionURL: URL? = nil
        #endif
        let persistentStore: PersistenceContainer
        do {
            persistentStore = try PersistenceContainer(inMemory: isRegressionTest && regressionURL == nil, storeURL: regressionURL)
        } catch {
            fatalError("Failed to load persistent store: \(error)")
        }

        let networkMonitor = NetworkMonitor(startMonitoring: !isRegressionTest)
        #if DEBUG
        if isRegressionTest { networkMonitor.setOnline(false) }
        #endif
        self.init(
            persistentStore: persistentStore,
            networkMonitor: networkMonitor,
            syncService: MockSyncService(),
            mediaStore: isRegressionTest
                ? TaskMediaStore(root: FileManager.default.temporaryDirectory
                    .appendingPathComponent("Media-\(regressionURL?.lastPathComponent ?? UUID().uuidString)", isDirectory: true))
                : .shared,
            enableIntegrations: !isRegressionTest
        )
    }

    init(
        persistentStore: PersistenceContainer,
        networkMonitor: NetworkMonitor,
        syncService: any SyncService,
        mediaStore: TaskMediaStore,
        enableIntegrations: Bool = false
    ) {
        let taskStore = SwiftDataTaskRepository(store: persistentStore)
        let syncCoordinator = SyncCoordinator(store: taskStore, syncService: syncService, networkMonitor: networkMonitor)
        syncCoordinator.suspend()
        let viewModel = TasksViewModel(
            store: taskStore,
            mediaStore: mediaStore,
            reminders: enableIntegrations ? TaskReminders(center: LocalReminderCenter()) : nil,
            calendar: enableIntegrations ? TaskCalendar(client: AppleTaskCalendarClient(), repository: taskStore) : nil,
            onLocalWrite: syncCoordinator.didWriteLocally
        )
        syncCoordinator.onSyncCompleted = { [weak viewModel] in
            Task { await viewModel?.refresh() }
        }

        self.persistentStore = persistentStore
        self.taskStore = taskStore
        self.networkMonitor = networkMonitor
        self.syncService = syncService
        self.syncCoordinator = syncCoordinator
        self.viewModel = viewModel
    }

    func persistPendingTitleEdits() {
        guard backgroundSaveTask == nil else { return }
        backgroundSaveID = UIApplication.shared.beginBackgroundTask(withName: "Save task edits") { [weak self] in
            Task { @MainActor [weak self] in self?.endBackgroundSave() }
        }
        backgroundSaveTask = Task { [self] in
            await viewModel.flushTitleEdits()
            endBackgroundSave()
            backgroundSaveTask = nil
        }
    }

    private func endBackgroundSave() {
        guard backgroundSaveID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundSaveID)
        backgroundSaveID = .invalid
    }
}
