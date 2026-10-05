import SwiftUI

struct ReminderListSheet: View {
    @Environment(TasksViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State private var editingTask: TaskSnapshot?

    private var tasks: [TaskSnapshot] {
        viewModel.tasks.filter { !$0.isDone && $0.reminderDate != nil }.sorted {
            if $0.reminderDate != $1.reminderDate { return $0.reminderDate! < $1.reminderDate! }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    var body: some View {
        NavigationStack {
            List {
                NotificationSettingsSection()
                if tasks.isEmpty {
                    Text("No reminders")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .listRowBackground(Theme.background)
                } else {
                    ForEach(tasks) { task in
                        Button { editingTask = task } label: {
                            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                                Text(task.title).font(Theme.Typography.body)
                                if let date = task.reminderDate {
                                    Text(date, format: .dateTime.day().month().hour().minute())
                                        .font(Theme.Typography.footnote)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minHeight: Theme.Metrics.minTouchTarget)
                        }
                        .listRowBackground(Theme.surface)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .contentMargins(.horizontal, Theme.pageMargin, for: .scrollContent)
            .listRowInsets(Theme.listRowInsets)
            .environment(\.defaultMinListRowHeight, Theme.Metrics.rowMinHeight)
            .foregroundStyle(Theme.textPrimary)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Reminders")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(item: $editingTask) { TaskDetailView(taskID: $0.id) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                        .tint(Theme.textPrimary)
                }
            }
        }
        .environment(\.bottomNavigationHeight, 0)
        .tint(Theme.accent)
    }
}
