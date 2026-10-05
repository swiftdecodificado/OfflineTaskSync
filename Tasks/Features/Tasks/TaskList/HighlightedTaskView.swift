import SwiftUI

struct HighlightedTaskView: View {
    let task: TaskSnapshot
    let now: Date
    let onEdit: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    var body: some View {
        Button(action: onEdit) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xs))
                : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Spacing.xs))
            layout {
                if let date = task.dueDate { dateBadge(date) }
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(task.title)
                        .font(Theme.Typography.taskTitle)
                        .foregroundStyle(Theme.TaskPalette.content)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if task.icon != nil || task.dueTime != nil || task.reminderDate != nil {
                        HomeTaskMetadata(task: task, now: now)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTouchTarget, alignment: .leading)
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "chevron.right")
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Open task details.")
        .accessibilityIdentifier("home.highlight")
    }

    @ViewBuilder
    private func dateBadge(_ date: Date) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            Label {
                Text(date, format: dateFormat.day().month(.wide))
            } icon: {
                Image(systemName: "calendar")
            }
            .font(Theme.Typography.metadata)
            .foregroundStyle(Theme.textPrimary)
        } else {
            VStack(spacing: Theme.Spacing.xxs) {
                Text(date, format: dateFormat.month(.abbreviated))
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.textPrimary)
                Text(date, format: dateFormat.day())
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(width: Theme.Metrics.minTouchTarget)
            .frame(minHeight: Theme.Metrics.minTouchTarget)
            .background(Theme.surfaceSecondary,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.banner))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(date, format: dateFormat.day().month(.wide).year()))
        }
    }

    private var dateFormat: Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }
}
