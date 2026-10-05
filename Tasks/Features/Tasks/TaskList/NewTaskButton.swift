import SwiftUI

struct NewTaskButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(Theme.Typography.toolbarIcon)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .frame(width: Theme.Metrics.floatingActionSize, height: Theme.Metrics.floatingActionSize)
                .contentShape(Circle())
        }
        .buttonStyle(PrimaryActionStyle(shape: .circle))
        .accessibilityLabel("Add task")
        .accessibilityHint("Opens the new task form.")
        .accessibilityIdentifier("task.new")
    }
}
