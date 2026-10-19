import SwiftUI

struct TaskPropertiesView: View {
    @Bindable var session: TaskEditingSession
    var isInline = false
    var editingProperty: Property?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @State private var presented: Property?

    enum Property: String, Identifiable { case date, time, reminder; var id: Self { self } }

    var body: some View {
        Group {
            if let editingProperty {
                propertyEditor(editingProperty)
            } else if isInline {
                inlineProperties
            } else {
                quickProperties
            }
        }
        .sheet(item: $presented) { propertyEditor($0) }
    }

    private func closeProperty() {
        if editingProperty != nil { dismiss() }
        else { presented = nil }
    }

    private func propertyEditor(_ property: Property) -> some View {
        NavigationStack {
            Form {
                switch property {
                case .date:
                    DatePicker("Data", selection: Binding(get: { session.draft.dueDate ?? .now }, set: setDay), displayedComponents: .date)
                        .datePickerStyle(.graphical)
                case .time:
                    if session.draft.dueDate == nil {
                        Text("Escolha uma data para definir o horário.")
                        DatePicker("Data", selection: Binding(get: { .now }, set: setDay), displayedComponents: .date)
                    }
                    DatePicker("Horário", selection: Binding(get: { session.draft.dueTime ?? .now }, set: setTime), displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .disabled(session.draft.dueDate == nil)
                    if let start = session.draft.dueTime {
                        TaskEndTimePicker(end: $session.draft.dueEndTime, start: start)
                    }
                case .reminder:
                    DatePicker("Lembrete", selection: Binding(get: { session.draft.reminderDate ?? .now.addingTimeInterval(3600) }, set: { session.draft.reminderDate = $0 }), displayedComponents: [.date, .hourAndMinute])
                    Button("Remover lembrete", role: .destructive) { session.draft.reminderDate = nil; closeProperty() }
                        .disabled(session.draft.reminderDate == nil)
                }
            }
            .accessibilityIdentifier("task.editor.\(property.rawValue)Panel")
            .tint(Theme.nativeSelection)
            .contentMargins(.horizontal, Theme.pageMargin, for: .scrollContent)
            .listRowInsets(Theme.listRowInsets)
            .environment(\.defaultMinListRowHeight, Theme.Metrics.rowMinHeight)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(title(for: property))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Concluir") {
                        // Save the default if the picker has not changed.
                        switch property {
                        case .date: if session.draft.dueDate == nil { setDay(.now) }
                        case .time: if session.draft.dueTime == nil, session.draft.dueDate != nil { setTime(.now) }
                        case .reminder: if session.draft.reminderDate == nil { session.draft.reminderDate = .now.addingTimeInterval(3600) }
                        }
                        closeProperty()
                    }
                    .tint(Theme.textPrimary)
                    .accessibilityIdentifier("task.property.done")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar", action: closeProperty)
                        .tint(Theme.textPrimary)
                        .accessibilityIdentifier("task.property.cancel")
                }
            }
        }
        .presentationDetents(property == .date ? [.large] : [.medium, .large])
    }

    private var quickProperties: some View {
        VStack(spacing: 0) {
            property(.date, title: "Data", symbol: "calendar", value: session.draft.dueDate?.formatted(Date.FormatStyle(locale: locale).day().month(.abbreviated).year()))
            Divider()
                .padding(.leading, Theme.Layout.cardInset + Theme.Metrics.checkboxSize + Theme.Layout.iconSpacing)
                .padding(.trailing, Theme.Layout.cardInset)
            property(.time, title: "Horário", symbol: "clock", value: session.draft.dueTime?.formatted(Date.FormatStyle(locale: locale).hour().minute()))
            Divider()
                .padding(.leading, Theme.Layout.cardInset + Theme.Metrics.checkboxSize + Theme.Layout.iconSpacing)
                .padding(.trailing, Theme.Layout.cardInset)
            if let start = session.draft.dueTime {
                TaskEndTimePicker(end: $session.draft.dueEndTime, start: start)
                    .padding(.horizontal, Theme.Layout.cardInset)
                Divider()
                    .padding(.leading, Theme.Layout.cardInset + Theme.Metrics.checkboxSize + Theme.Layout.iconSpacing)
                    .padding(.trailing, Theme.Layout.cardInset)
            }
            property(.reminder, title: "Lembrete", symbol: "bell", value: session.draft.reminderDate?.formatted(Date.FormatStyle(locale: locale).day().month(.abbreviated).hour().minute()))
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.banner))
    }

    private var inlineProperties: some View {
        VStack(spacing: 0) {
            inlineProperty(.date, symbol: "calendar", isSet: session.draft.dueDate != nil) {
                if session.draft.dueDate != nil {
                    DatePicker("Data", selection: Binding(
                        get: { session.draft.dueDate ?? .now }, set: setDay
                    ), displayedComponents: .date)
                    .labelsHidden()
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityLabel("Data")
                } else {
                    inlineAdd("Definir data") { setDefault(.date) }
                }
            } add: { setDefault(.date) }
            Divider()
                .padding(.leading, Theme.Layout.cardInset + Theme.Metrics.checkboxSize + Theme.Layout.iconSpacing)
                .padding(.trailing, Theme.Layout.cardInset)
            inlineProperty(.time, symbol: "clock", isSet: session.draft.dueTime != nil) {
                if session.draft.dueTime != nil {
                    DatePicker("Horário", selection: Binding(
                        get: { session.draft.dueTime ?? .now }, set: setTime
                    ), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityLabel("Horário")
                } else {
                    inlineAdd("Definir horário") { setDefault(.time) }
                }
            } add: { setDefault(.time) }
            Divider()
                .padding(.leading, Theme.Layout.cardInset + Theme.Metrics.checkboxSize + Theme.Layout.iconSpacing)
                .padding(.trailing, Theme.Layout.cardInset)
            if let start = session.draft.dueTime {
                TaskEndTimePicker(end: $session.draft.dueEndTime, start: start)
                Divider()
                    .padding(.leading, Theme.Layout.cardInset + Theme.Metrics.checkboxSize + Theme.Layout.iconSpacing)
                    .padding(.trailing, Theme.Layout.cardInset)
            }
            inlineProperty(.reminder, symbol: "bell", isSet: session.draft.reminderDate != nil) {
                if session.draft.reminderDate != nil {
                    inlineReminderPicker
                } else {
                    inlineAdd("Definir lembrete") { setDefault(.reminder) }
                }
            } add: { setDefault(.reminder) } clear: { session.draft.reminderDate = nil }
        }
        .datePickerStyle(.compact)
        .font(Theme.Typography.metadata)
        .foregroundStyle(Theme.textPrimary)
        .tint(Theme.nativeSelection)
        .padding(Theme.Spacing.xs)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.banner))
    }

    private var inlineReminderPicker: some View {
        let selection = Binding(
            get: { session.draft.reminderDate ?? .now.addingTimeInterval(3600) },
            set: { session.draft.reminderDate = $0 }
        )
        return ViewThatFits(in: .horizontal) {
            DatePicker("Lembrete", selection: selection, displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel("Lembrete")
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                DatePicker("Data", selection: selection, displayedComponents: .date)
                    .labelsHidden()
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityLabel("Data do lembrete")
                DatePicker("Horário", selection: selection, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityLabel("Horário do lembrete")
            }
        }
    }

    private func inlineProperty<Content: View>(_ property: Property, symbol: String, isSet: Bool,
                                               @ViewBuilder content: () -> Content,
                                               add: @escaping () -> Void,
                                               clear: (() -> Void)? = nil) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xxs))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Spacing.xs))
        return layout {
            Image(systemName: symbol)
                .font(Theme.Typography.headline)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: Theme.Metrics.taskIconSize, height: Theme.Metrics.minTouchTarget)
                .accessibilityHidden(true)
            content()
                .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTouchTarget, alignment: .leading)
            if !isSet || clear != nil {
                Button(action: { if isSet { clear?() } else { add() } }) {
                    Image(systemName: isSet ? "xmark.circle.fill" : "plus.circle")
                        .font(Theme.Typography.headline)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .foregroundStyle(isSet ? Theme.textSecondary : Theme.accent)
                        .frame(width: Theme.Metrics.minTouchTarget, height: Theme.Metrics.minTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSet
                    ? Text("Remover: \(title(for: property))")
                    : Text("Adicionar: \(title(for: property))"))
            }
        }
        .frame(minHeight: Theme.Metrics.minTouchTarget)
        .padding(.vertical, Theme.Spacing.xxs)
        .accessibilityElement(children: .contain)
    }

    private func inlineAdd(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTouchTarget, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func setDefault(_ property: Property) {
        switch property {
        case .date: setDay(.now)
        case .time:
            if session.draft.dueDate == nil { setDay(.now) }
            setTime(.now)
        case .reminder: session.draft.reminderDate = .now.addingTimeInterval(3600)
        }
    }

    private func property(_ property: Property, title: LocalizedStringKey, symbol: String, value: String?) -> some View {
        Button {
            session.editor.textView.resignFirstResponder()
            presented = property
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: symbol)
                    .font(Theme.Typography.headline)
                    .frame(width: Theme.Metrics.checkboxSize)
                    .accessibilityHidden(true)
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xxs))
                    : AnyLayout(HStackLayout(spacing: Theme.Spacing.xs))
                layout {
                    Text(title).font(Theme.Typography.metadata)
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    Text(value ?? AppLocalization.string("Não definido"))
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Image(systemName: "chevron.right")
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTouchTarget)
            .padding(.horizontal, Theme.Layout.cardInset)
            .padding(.vertical, Theme.Spacing.xxs)
            .foregroundStyle(Theme.textPrimary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityValue(value ?? AppLocalization.string("Não definido"))
    }

    private func title(for property: Property) -> String {
        switch property {
        case .date: AppLocalization.string("Data")
        case .time: AppLocalization.string("Horário")
        case .reminder: AppLocalization.string("Lembrete")
        }
    }

    private func setDay(_ day: Date) {
        session.draft.dueDate = Calendar.current.startOfDay(for: day)
        if let time = session.draft.dueTime {
            let start = combined(day: day, time: time)
            session.draft.dueEndTime = TaskSchedule.shiftedEnd(from: session.draft.dueTime, end: session.draft.dueEndTime, to: start)
            session.draft.dueTime = start
        }
    }

    private func setTime(_ time: Date) {
        guard let day = session.draft.dueDate else { return }
        let start = combined(day: day, time: time)
        session.draft.dueEndTime = TaskSchedule.shiftedEnd(from: session.draft.dueTime, end: session.draft.dueEndTime, to: start)
        session.draft.dueTime = start
    }

    private func combined(day: Date, time: Date) -> Date? {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        return Calendar.current.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: day)
    }
}

struct TaskCalendarOptions: View {
    @Bindable var session: TaskEditingSession
    @Environment(TasksViewModel.self) private var viewModel
    @State private var calendars: [TaskCalendarChoice] = []
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if session.original?.calendarEventID?.isEmpty == false {
                Button { viewModel.checkCalendarLink(id: session.draft.id) } label: {
                    Label("Linked to Calendar", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTouchTarget, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Check Calendar link")
            } else {
                Toggle(isOn: $session.draft.addToCalendar) {
                    Label("Adicionar ao calendário", systemImage: session.draft.addToCalendar ? "checkmark.circle.fill" : "calendar.badge.plus")
                        .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTouchTarget, alignment: .leading)
                }
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .disabled(session.draft.dueDate == nil)
                    .accessibilityHint(session.draft.dueDate == nil ? Text("Set a due date to add to Calendar.") : Text(""))
                    .onChange(of: session.draft.addToCalendar) { _, requested in
                        if requested { loadCalendars() }
                    }
                if loading { ProgressView("Loading calendars") }
                if session.draft.addToCalendar, !calendars.isEmpty {
                    Picker("Calendar", selection: $session.draft.calendarID) {
                        ForEach(calendars) { Text($0.title).tag(Optional($0.id)) }
                    }
                    .frame(minHeight: Theme.Metrics.minTouchTarget)
                }
            }
        }
        .font(Theme.Typography.callout)
        .foregroundStyle(Theme.textPrimary)
        .tint(Theme.nativeSelection)
        .task { if session.draft.addToCalendar { loadCalendars() } }
    }

    private func loadCalendars() {
        loading = true
        Task {
            calendars = await viewModel.calendarChoices()
            session.draft.calendarID = calendars.first(where: { $0.id == session.draft.calendarID })?.id ?? calendars.first?.id
            loading = false
        }
    }
}
