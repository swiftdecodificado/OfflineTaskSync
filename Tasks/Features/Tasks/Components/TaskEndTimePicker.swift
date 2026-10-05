import SwiftUI

struct TaskEndTimePicker: View {
    @Binding var end: Date?
    let start: Date
    var allowsNone = true
    var accessibilityID = "task.end"
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    private var format: Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).hour().minute()
    }

    private var choices: [Date] {
        var dates = AgendaTimeGrid(day: start, calendar: calendar).ends(after: start)
        if let end, end > start, !dates.contains(end) { dates.append(end); dates.sort() }
        return dates
    }

    var body: some View {
        Picker("End time", selection: $end) {
            if allowsNone { Text("Não definido").tag(Optional<Date>.none) }
            ForEach(choices, id: \.self) { date in
                label(date).tag(Optional(date))
            }
        }
        .pickerStyle(.menu)
        .frame(minHeight: Theme.Metrics.minTouchTarget)
        .accessibilityIdentifier(accessibilityID)
    }

    @ViewBuilder private func label(_ date: Date) -> some View {
        let grid = AgendaTimeGrid(day: start, calendar: calendar)
        if date == grid.interval.end {
            Text("Midnight (next day)")
        } else if grid.interval.duration > 24 * 60 * 60 {
            Text(verbatim: "\(date.formatted(format)) \(calendar.timeZone.abbreviation(for: date) ?? "")")
        } else {
            Text(date, format: format)
        }
    }
}
