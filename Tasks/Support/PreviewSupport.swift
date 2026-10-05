import SwiftUI

struct PreviewHost: View {
    struct SeedTask {
        let title: String
        var isDone: Bool = false
        var pending: Bool = true
    }

    @State private var preferences = AppPreferences()
    @State private var environment: PreviewEnvironment

    init(seedTasks: [SeedTask] = [], isOnline: Bool = true, triggerSync: Bool = false) {
        _environment = State(initialValue: PreviewEnvironment(
            seedTasks: seedTasks, isOnline: isOnline, triggerSync: triggerSync
        ))
    }

    var body: some View {
        TaskListView()
            .environment(preferences)
            .environment(environment.app.viewModel)
            .environment(environment.app.syncCoordinator)
            .environment(environment.app.networkMonitor)
            .task { await environment.prepare() }
            .onDisappear { environment.app.syncCoordinator.suspend() }
    }
}

@MainActor
private final class PreviewEnvironment {
    let app: AppEnvironment
    private let seedTasks: [PreviewHost.SeedTask]
    private let triggerSync: Bool
    private var isPrepared = false

    init(seedTasks: [PreviewHost.SeedTask], isOnline: Bool, triggerSync: Bool) {
        self.seedTasks = seedTasks
        self.triggerSync = triggerSync
        let networkMonitor = NetworkMonitor(startMonitoring: false)
        networkMonitor.setOnline(isOnline)
        app = AppEnvironment(
            persistentStore: try! PersistenceContainer(inMemory: true),
            networkMonitor: networkMonitor,
            syncService: MockSyncService(latency: .seconds(999)),
            mediaStore: TaskMediaStore(root: FileManager.default.temporaryDirectory
                .appendingPathComponent("PreviewMedia-\(UUID().uuidString)", isDirectory: true))
        )
    }

    func prepare() async {
        guard !isPrepared else { return }
        isPrepared = true
        do {
            for seed in seedTasks {
                let id = UUID()
                try await app.taskStore.createTask(id: id, title: seed.title)
                if seed.isDone { try await app.taskStore.toggleDone(id: id) }
                if !seed.pending, let snapshot = try await app.taskStore.snapshot(id: id) {
                    try await app.taskStore.markSynced(snapshot)
                }
            }
            await app.viewModel.refresh()
            if triggerSync { app.syncCoordinator.resume() }
        } catch {
            assertionFailure("Failed to prepare preview: \(error)")
        }
    }
}
