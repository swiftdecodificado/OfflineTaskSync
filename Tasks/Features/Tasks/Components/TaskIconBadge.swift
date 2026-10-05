import SwiftUI

struct TaskIconBadge: View {
    let icon: TaskIcon
    var usesTaskPalette = false

    var body: some View {
        Image(systemName: icon.rawValue)
            .font(Theme.Typography.headline)
            .foregroundStyle(Theme.CategoryPalette.content)
            .frame(width: usesTaskPalette ? Theme.Metrics.taskIconSize : Theme.Metrics.minTouchTarget, height: usesTaskPalette ? Theme.Metrics.taskIconSize : Theme.Metrics.minTouchTarget)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .accessibilityHidden(true)
    }
}
