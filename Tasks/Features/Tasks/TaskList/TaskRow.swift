import SwiftUI

struct TaskRow: View {
    @Environment(TasksViewModel.self) private var viewModel
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var completionFeedback: Bool?
    let task: TaskSnapshot
    let now: Date
    var showNotes = true
    var isHomeRow = false
    var isHomeCard = false
    var showsCategory = true
    var isTimeline = false
    var minimumHeight: CGFloat?
    var showsTime = true
    var showsDate = true
    var showsReminder = true
    var search = ""
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onDeadline: () -> Void
    let onEdit: () -> Void

    private var displayedCompletion: Bool { completionFeedback ?? task.isDone }

    private var hasHomeMetadata: Bool {
        task.icon != nil || task.dueTime != nil || task.reminderDate != nil
            || task.isOverdue(now: now, calendar: calendar)
    }

    private var accessibilityStatus: String {
        let status = task.isDone ? AppLocalization.string("Completed") : AppLocalization.string("Active")
        if isHomeRow { return status }
        let category = task.icon?.title ?? AppLocalization.string("Sem categoria")
        var values = [status, category]
        if isTimeline, let start = task.dueTime {
            let format = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).hour().minute()
            values.append(start.formatted(format))
            if let end = task.dueEndTime { values.append(end.formatted(format)) }
        }
        return values.joined(separator: ", ")
    }

    var body: some View {
        rowContent
        .padding(.horizontal, isHomeCard ? 0 : isTimeline ? Theme.Spacing.xxs : Theme.Layout.cardInset)
        .padding(.vertical, isHomeCard || isTimeline ? 0 : Theme.Spacing.xs)
        .frame(minHeight: minimumHeight, alignment: .top)
        .background(Theme.TaskPalette.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.banner))
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(action: toggleCompletion) {
                Label(task.isDone ? "Reopen" : "Complete", systemImage: task.isDone ? "arrow.uturn.backward" : "checkmark")
            }
            .tint(Theme.nativeSelection)
            .accessibilityIdentifier("task.swipe.toggle")
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button { showingDeleteConfirmation = true } label: {
                Label("Delete Task", systemImage: "trash")
            }
            .tint(Theme.nativeDestructive)
            .accessibilityIdentifier("task.swipe.delete")
            Button("Change Due Date", systemImage: "calendar", action: onDeadline)
                .tint(Theme.nativeSelection)
                .accessibilityIdentifier("task.swipe.deadline")
            Button("Edit Task", systemImage: "pencil", action: onEdit)
                .tint(Theme.nativeSelection)
                .accessibilityIdentifier("task.swipe.edit")
        }
        .contextMenu {
            Button(action: toggleCompletion) {
                Label(task.isDone ? "Reopen" : "Complete", systemImage: task.isDone ? "arrow.uturn.backward" : "checkmark")
            }
            Button("Change Due Date", systemImage: "calendar", action: onDeadline)
            Button("Edit Task", systemImage: "pencil", action: onEdit)
            Button("Delete Task", systemImage: "trash", role: .destructive) { showingDeleteConfirmation = true }
        }
        .accessibilityAction(named: task.isDone ? Text("Reopen") : Text("Complete"), toggleCompletion)
        .accessibilityAction(named: "Change Due Date", onDeadline)
        .accessibilityAction(named: "Edit Task", onEdit)
        .accessibilityAction(named: "Delete Task") { showingDeleteConfirmation = true }
        .alert("Delete this task?", isPresented: $showingDeleteConfirmation) {
            Button("Delete Task", role: .destructive) {
                guard !isDeleting else { return }
                isDeleting = true
                Task {
                    _ = await viewModel.delete(id: task.id)
                    isDeleting = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(task.title)
        }
        .disabled(isDeleting || viewModel.isChangingCompletion)
    }

    @ViewBuilder
    private var rowContent: some View {
        if isHomeCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Button(action: onEdit) { homeContent }
                    .buttonStyle(.plain)
                    .accessibilityValue(Text(verbatim: accessibilityStatus))
                    .accessibilityIdentifier("task.open.\(task.id.uuidString)")
                Spacer(minLength: Theme.Spacing.md)
                Button(action: toggleCompletion) {
                    Label(displayedCompletion ? LocalizedStringKey("Completed") : LocalizedStringKey("Pending"),
                          systemImage: displayedCompletion ? "checkmark.circle.fill" : "circle")
                        .font(Theme.Typography.footnote)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .frame(minHeight: Theme.Metrics.minTouchTarget)
                        .foregroundStyle(Theme.textPrimary)
                        .background(Theme.surfaceSecondary, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(displayedCompletion ? Text("Reopen \(task.title)") : Text("Complete \(task.title)"))
                .accessibilityIdentifier("task.toggle.\(task.id.uuidString)")
            }
            .padding(Theme.Layout.cardInset)
            .frame(maxWidth: .infinity, minHeight: Theme.Home.taskCardMinHeight, alignment: .topLeading)
        } else {
            HStack(alignment: .top, spacing: Theme.Layout.iconSpacing) {
                Button(action: toggleCompletion) {
                    Image(systemName: displayedCompletion ? "checkmark.circle.fill" : task.icon?.rawValue ?? "tray")
                        .font(Theme.Typography.toolbarIcon)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                        .animation(reduceMotion ? nil : Theme.Feedback.stateChange, value: displayedCompletion)
                        .frame(minWidth: Theme.Metrics.minTouchTarget, minHeight: Theme.Metrics.minTouchTarget,
                               alignment: isHomeRow && hasHomeMetadata ? .top : .center)
                }
                .foregroundStyle(!displayedCompletion && task.isOverdue(now: now, calendar: calendar)
                                 ? Theme.TaskPalette.overdue : (displayedCompletion ? Theme.accent : Theme.CategoryPalette.foreground(for: task.icon)))
                .background(displayedCompletion || task.isOverdue(now: now, calendar: calendar)
                            ? Theme.surface : Theme.CategoryPalette.background(for: task.icon),
                            in: RoundedRectangle(cornerRadius: Theme.Radius.banner))
                .buttonStyle(.borderless)
                .accessibilityLabel(displayedCompletion ? Text("Reopen \(task.title)") : Text("Complete \(task.title)"))
                .accessibilityValue(task.icon?.title ?? AppLocalization.string("Sem categoria"))
                .accessibilityIdentifier("task.toggle.\(task.id.uuidString)")
                Button(action: onEdit) {
                    if isHomeRow {
                        homeContent
                    } else {
                        collectionContent
                            .frame(maxHeight: isTimeline ? .infinity : nil, alignment: .topLeading)
                            .contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)
                .accessibilityValue(Text(verbatim: accessibilityStatus))
                .accessibilityIdentifier("task.open.\(task.id.uuidString)")
                .layoutPriority(1)
            }
        }
    }

    private func toggleCompletion() {
        Task {
            await viewModel.toggle(id: task.id) { completed in
                completionFeedback = completed
                if !reduceMotion {
                    try? await Task.sleep(for: Theme.Feedback.completionIconDuration)
                }
            }
            completionFeedback = nil
        }
    }

    private var collectionContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(TaskSearchPreview.highlighted(task.title, query: search))
                .font(Theme.Typography.taskTitle)
                .foregroundStyle(task.isDone ? Theme.TaskPalette.secondaryContent : Theme.TaskPalette.content)
                .strikethrough(task.isDone)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
            if showNotes && !task.notes.isEmpty {
                Text(TaskSearchPreview.highlighted(TaskSearchPreview.snippet(task.notes, query: search), query: search))
                    .font(Theme.Typography.metadata)
                    .foregroundStyle(Theme.TaskPalette.secondaryContent)
                    .lineLimit(search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 1 : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("task.notes.\(task.id.uuidString)")
            }
            if showsCategory, let category = task.icon {
                Text(category.title)
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.TaskPalette.secondaryContent)
            }
            if (showsDate && task.dueDate != nil) || (showsTime && task.dueTime != nil) || (showsReminder && task.reminderDate != nil) {
                TaskMetadataView(task: task, now: now,
                                 includesYear: task.dueDate.map { !calendar.isDate($0, equalTo: now, toGranularity: .year) } ?? false,
                                 showsReminder: showsReminder, showsDate: showsDate, showsTime: showsTime, usesTaskPalette: true)
                    .accessibilityIdentifier("task.row.metadata")
            }
        }
        .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTouchTarget, alignment: .leading)
        .padding(.vertical, isTimeline ? 0 : Theme.Spacing.xs)
    }

    private var homeContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(task.title)
                .font(Theme.Typography.taskTitle)
                .foregroundStyle(task.isDone ? Theme.TaskPalette.secondaryContent : Theme.TaskPalette.content)
                .strikethrough(task.isDone)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if showNotes && !task.notes.isEmpty {
                Text(task.notes)
                    .font(Theme.Typography.metadata)
                    .foregroundStyle(Theme.TaskPalette.secondaryContent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if hasHomeMetadata {
                HomeTaskMetadata(task: task, now: now, showsDate: task.isOverdue(now: now, calendar: calendar), showsCategorySymbol: false)
                    .accessibilityIdentifier("task.row.metadata")
            }
        }
        .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTouchTarget,
               alignment: hasHomeMetadata ? .topLeading : .leading)
        .contentShape(Rectangle())
    }

}
