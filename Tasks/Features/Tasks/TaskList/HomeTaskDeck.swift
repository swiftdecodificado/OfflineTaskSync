import SwiftUI

struct HomeTaskDeck: View {
    let tasks: [TaskSnapshot]
    let now: Date
    let onOpen: (UUID) -> Void
    let onEdit: (UUID) -> Void
    let onDeadline: (TaskSnapshot) -> Void
    @Environment(TasksViewModel.self) private var viewModel
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSaving = false
    @State private var deletion: TaskSnapshot?
    @State private var showingDelete = false

    private var visibleTasks: [TaskSnapshot] { Array(tasks.prefix(3)) }

    var body: some View {
        ZStack(alignment: .top) {
            if let task = tasks.first {
                frontCard(task)
                    .fixedSize(horizontal: false, vertical: true)
                    .background {
                        GeometryReader { geometry in
                            ZStack(alignment: .top) {
                                ForEach(visibleTasks.reversed()) { preview in
                                    let depth = visibleTasks.firstIndex(where: { $0.id == preview.id }) ?? 0
                                    if depth > 0 {
                                        backCard(preview, depth: depth)
                                            .frame(height: geometry.size.height)
                                    }
                                }

                            }
                            .frame(width: geometry.size.width, height: geometry.size.height)
                        }
                    }
                    .id(task.id)
                    .accessibilityAction(named: "Complete") { complete(task) }
                    .accessibilityAction(named: "Edit Task") { edit(task) }
                    .accessibilityAction(named: "Change Due Date") { onDeadline(task) }
                    .accessibilityAction(named: "Delete Task") { requestDeletion(task) }
            }
        }
        .padding(.horizontal, Theme.Spacing.xxs)
        .padding(.top, Theme.Spacing.xs)
        .padding(.bottom, CGFloat(max(0, visibleTasks.count - 1)) * Theme.Spacing.lg + Theme.Spacing.sm)
        .animation(reduceMotion ? nil : Theme.Feedback.stateChange, value: tasks.map(\.id))
        .disabled(isSaving || viewModel.isChangingCompletion)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.taskDeck")
        .alert("Delete this task?", isPresented: $showingDelete, presenting: deletion) { task in
            Button("Delete Task", role: .destructive) {
                isSaving = true
                Task {
                    _ = await viewModel.delete(id: task.id)
                    isSaving = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { task in
            Text(task.title)
        }
    }

    private func backCard(_ task: TaskSnapshot, depth: Int) -> some View {
        RoundedRectangle(cornerRadius: Theme.Radius.card)
            .fill(Theme.CategoryPalette.background(for: task.icon))
            .overlay(alignment: .bottomLeading) {
                Text(task.title)
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.CategoryPalette.foreground(for: task.icon))
                    .lineLimit(1)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.bottom, Theme.Spacing.xs)
            }
            .scaleEffect(1 - CGFloat(depth) * 0.045, anchor: .top)
            .rotationEffect(.degrees(reduceMotion ? 0 : depth == 1 ? -2 : 2))
            .offset(y: CGFloat(depth) * Theme.Spacing.lg)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func frontCard(_ task: TaskSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            cardHeader(task)
            Button { onOpen(task.id) } label: {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(task.title)
                        .font(Theme.Typography.editorTitle)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                    let description = TaskSearchPreview.snippet(task.notes, query: "")
                    if !description.isEmpty {
                        Text(description)
                            .font(Theme.Typography.metadata)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTouchTarget, alignment: .leading)
                .contentShape(Rectangle())
                .multilineTextAlignment(.leading)
            }
            .accessibilityIdentifier("task.open.\(task.id.uuidString)")
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.sm))
                : AnyLayout(HStackLayout(alignment: .center, spacing: Theme.Spacing.sm))
            layout {
                if let time = task.dueTime {
                    Label {
                        TaskTimeLabel(start: time, end: task.dueEndTime)
                    } icon: {
                        Image(systemName: "clock")
                            .frame(width: Theme.Metrics.checkboxSize)
                    }
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Button { complete(task) } label: {
                    Label("Concluir tarefa", systemImage: "checkmark.circle")
                        .font(Theme.Typography.metadataEmphasis)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .frame(minHeight: Theme.Metrics.minTouchTarget)
                        .foregroundStyle(Theme.onAccent)
                        .background(Theme.actionBackground, in: Capsule())
                }
                .accessibilityLabel(Text("Complete \(task.title)"))
                .accessibilityIdentifier("task.toggle.\(task.id.uuidString)")
            }
        }
        .buttonStyle(.plain)
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, minHeight: Theme.Home.taskDeckMinHeight, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(Theme.border, lineWidth: Theme.Metrics.borderStroke)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.06), radius: Theme.Spacing.sm, y: Theme.Spacing.xxs)
    }

    private func cardHeader(_ task: TaskSnapshot) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xs))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Theme.Spacing.sm))
        return layout {
            Label {
                Text(task.dueDate ?? now, format: Date.FormatStyle(locale: locale, calendar: calendar,
                                                                 timeZone: calendar.timeZone).day().month(.abbreviated))
            } icon: {
                Image(systemName: "calendar").frame(width: Theme.Metrics.checkboxSize)
            }
            .font(Theme.Typography.footnote)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            HStack(spacing: Theme.Spacing.xs) {
                if let icon = task.icon {
                    Label(icon.title, systemImage: icon.rawValue)
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                }
                Menu {
                    Button("Edit Task", systemImage: "pencil") { edit(task) }
                    Button("Change Due Date", systemImage: "calendar") { onDeadline(task) }
                    Button("Delete Task", systemImage: "trash", role: .destructive) { requestDeletion(task) }
                } label: {
                    Label("Task options", systemImage: "ellipsis")
                        .labelStyle(.iconOnly)
                        .rotationEffect(.degrees(90))
                        .font(Theme.Typography.toolbarIcon)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .frame(minWidth: Theme.Metrics.minTouchTarget, minHeight: Theme.Metrics.minTouchTarget)
                }
                .accessibilityIdentifier("home.taskDeck.options")
            }
        }
    }

    private func complete(_ task: TaskSnapshot) {
        guard !isSaving else { return }
        isSaving = true
        Task {
            _ = await viewModel.toggle(id: task.id)
            isSaving = false
        }
    }

    private func edit(_ task: TaskSnapshot) {
        onEdit(task.id)
    }

    private func requestDeletion(_ task: TaskSnapshot) {
        deletion = task
        showingDelete = true
    }

}
