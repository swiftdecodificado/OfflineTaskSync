import SwiftUI

struct TaskDetailView: View {
    let taskID: UUID
    @Environment(TasksViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss
    @State private var session: TaskEditingSession?
    @State private var loaded = false

    var body: some View {
        Group {
            if let session {
                TaskFullEditor(session: session) { dismiss() }
            } else if loaded {
                VStack {
                    ContentUnavailableView("This task is no longer available.", systemImage: "doc.questionmark")
                    Button("Fechar") { dismiss() }
                        .frame(minWidth: Theme.Metrics.minTouchTarget, minHeight: Theme.Metrics.minTouchTarget)
                        .padding(Theme.pageMargin)
                }
            } else {
                ProgressView("Loading tasks")
            }
        }
        .task {
            if session == nil, let task = viewModel.task(id: taskID) {
                session = TaskEditingSession(task: task, mediaStore: viewModel.mediaStore)
            }
            loaded = true
        }
    }
}
