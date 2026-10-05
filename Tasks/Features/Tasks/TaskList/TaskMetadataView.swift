import SwiftUI

struct TaskMetadataView: View {
    let task: TaskSnapshot
    let now: Date
    var includesYear = true
    var showsReminder = true
    var showsDate = true
    var showsTime = true
    var usesTaskPalette = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                verticalMetadata
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xxs) {
                        if showsDate, let date = task.dueDate { dateLabel(date) }
                        if showsTime, let time = task.dueTime { TaskTimeLabel(start: time, end: task.dueEndTime) }
                        if showsReminder, task.reminderDate != nil {
                            Image(systemName: "bell")
                                .accessibilityLabel("Reminder set")
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    verticalMetadata
                }
            }
        }
        .font(Theme.Typography.footnote)
        .foregroundStyle(task.isOverdue(now: now, calendar: calendar)
                         ? (usesTaskPalette ? Theme.TaskPalette.overdue : Theme.error)
                         : (usesTaskPalette ? Theme.TaskPalette.secondaryContent : Theme.textSecondary))
        .accessibilityElement(children: .combine)
    }

    private var verticalMetadata: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            if showsDate, let date = task.dueDate { dateLabel(date) }
            if showsTime, let time = task.dueTime {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xxs) {
                    Image(systemName: "clock")
                    TaskTimeLabel(start: time, end: task.dueEndTime)
                }
            }
            if showsReminder, task.reminderDate != nil { Label("Reminder", systemImage: "bell") }
        }
    }

    private var dateFormat: Date.FormatStyle {
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).day().month()
        return includesYear ? style.year() : style
    }

    private func dateLabel(_ date: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xxs) {
            Image(systemName: task.isOverdue(now: now, calendar: calendar) ? "exclamationmark.circle" : "calendar")
            Text(date, format: dateFormat)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct HomeTaskMetadata: View {
    let task: TaskSnapshot
    let now: Date
    var showsDate = false
    var showsCategorySymbol = true
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var hasDetails: Bool {
        task.icon != nil || task.dueTime != nil || task.reminderDate != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            if showsDate, task.dueDate != nil {
                TaskMetadataView(task: task, now: now, showsReminder: false,
                                 showsTime: false, usesTaskPalette: true)
            }
            if hasDetails {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) { details }
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) { details }
                            .fixedSize(horizontal: true, vertical: false)
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) { details }
                    }
                }
            }
        }
        .font(Theme.Typography.footnote)
        .labelStyle(.titleAndIcon)
        .foregroundStyle(Theme.TaskPalette.secondaryContent)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var details: some View {
        if let category = task.icon {
            if showsCategorySymbol {
                Label {
                    Text(category.title)
                } icon: {
                    Image(systemName: category.rawValue)
                        .foregroundStyle(Theme.CategoryPalette.content)
                        .frame(width: Theme.Metrics.taskIconSize, height: Theme.Metrics.taskIconSize)
                        .background(Theme.CategoryPalette.background(for: category),
                                    in: RoundedRectangle(cornerRadius: Theme.Radius.icon))
                }
            }
            else { Text(category.title) }
        }
        if let time = task.dueTime {
            Label {
                TaskTimeLabel(start: time, end: task.dueEndTime).monospacedDigit()
            } icon: {
                Image(systemName: "clock")
            }
        }
        if task.reminderDate != nil {
            Label("Reminder", systemImage: "bell")
        }
    }
}

struct TaskTimeLabel: View {
    let start: Date
    let end: Date?
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    var body: some View {
        let format = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).hour().minute()
        if let end {
            Text("\(start.formatted(format)) – \(end.formatted(format))")
        } else {
            Text(start, format: format)
        }
    }
}
