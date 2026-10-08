import SwiftUI

struct DeadlineEditor: View {
    let taskID: UUID
    @Environment(TasksViewModel.self) private var viewModel

    var body: some View {
        Group {
            if let date = viewModel.task(id: taskID)?.dueDate {
                DatePicker("Due date", selection: Binding(
                    get: { viewModel.task(id: taskID)?.dueDate ?? date },
                    set: { viewModel.editDueDate(id: taskID, date: $0) }
                ), displayedComponents: .date)
                .tint(Theme.nativeSelection)
                .frame(minHeight: Theme.Metrics.minTouchTarget)
                if let time = viewModel.task(id: taskID)?.dueTime {
                    DatePicker("Due time", selection: Binding(
                        get: { viewModel.task(id: taskID)?.dueTime ?? time },
                        set: { viewModel.editDueTime(id: taskID, date: $0) }
                    ), displayedComponents: .hourAndMinute)
                    .tint(Theme.nativeSelection)
                    .frame(minHeight: Theme.Metrics.minTouchTarget)
                } else {
                    Button { viewModel.editDueTime(id: taskID, date: .now) } label: {
                        Text("Add due time")
                            .font(Theme.Typography.body)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTouchTarget, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                DatePicker("Due date", selection: Binding(
                    get: { .now }, set: { viewModel.editDueDate(id: taskID, date: $0) }
                ), displayedComponents: .date)
            }
        }
        .font(Theme.Typography.body)
        .foregroundStyle(Theme.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
    }
}
