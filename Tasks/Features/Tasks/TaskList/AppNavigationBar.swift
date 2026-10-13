import SwiftUI

struct AppNavigationBar: View {
    @Binding var selection: TaskCollection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionAnimation

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            destination(.all)
            destination(.upcoming)
        }
        .padding(Theme.Spacing.xs)
        .background(Theme.navigationBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.composer))
        .frame(maxWidth: Theme.Home.navigationMaxWidth)
        .animation(reduceMotion ? nil : Theme.Feedback.stateChange, value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Navigation")
        .accessibilityIdentifier("app.navigation")
    }

    private func destination(_ collection: TaskCollection) -> some View {
        let symbol = collection == .all ? "list.bullet" : collection.symbol
        let title = LocalizedStringKey(collection == .all ? "Tasks" : collection.rawValue)
        return Button {
            selection = collection
        } label: {
            VStack(spacing: Theme.Spacing.xxs) {
                Image(systemName: symbol)
                    .font(Theme.Typography.toolbarIcon)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTouchTarget)
                .foregroundStyle(selection == collection ? Theme.highlightContent : Theme.navigationContent)
                .background {
                    if selection == collection {
                        RoundedRectangle(cornerRadius: Theme.Radius.composer - Theme.Spacing.xs)
                            .fill(Theme.lime)
                            .matchedGeometryEffect(id: "navigation.selection", in: selectionAnimation)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(selection == collection ? .isSelected : [])
        .accessibilityIdentifier("tab.\(collection)")
        .accessibilityShowsLargeContentViewer {
            Label(title, systemImage: symbol)
        }
    }
}
