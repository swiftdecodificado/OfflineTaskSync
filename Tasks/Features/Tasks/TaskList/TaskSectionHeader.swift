import SwiftUI

struct TaskSectionHeader: View {
    let title: String
    let count: Int
    var symbol: String?
    @Binding var isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : Theme.Feedback.stateChange) { isExpanded.toggle() }
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                if let symbol, !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: symbol)
                        .font(Theme.Typography.metadataEmphasis)
                        .frame(width: Theme.Metrics.taskIconSize, height: Theme.Metrics.taskIconSize)
                        .foregroundStyle(Theme.CategoryPalette.foreground(for: TaskIcon(rawValue: symbol)))
                        .background(Theme.CategoryPalette.background(for: TaskIcon(rawValue: symbol)),
                                    in: RoundedRectangle(cornerRadius: Theme.Radius.icon))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .fixedSize(horizontal: false, vertical: true)
                Text(count, format: .number)
                    .font(Theme.Typography.numeric)
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: Theme.Spacing.xs)
                Image(systemName: "chevron.right")
                    .font(Theme.Typography.metadataEmphasis)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
            }
            .font(Theme.Typography.homeSectionTitle)
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTouchTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .textCase(nil)
        .accessibilityLabel(Text("\(title), \(count)"))
        .accessibilityValue(isExpanded ? Text("Expandida") : Text("Recolhida"))
        .accessibilityAddTraits(.isHeader)
    }
}
