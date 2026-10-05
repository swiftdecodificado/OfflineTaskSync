import SwiftUI

struct AppNavigationBar: View {
    @Binding var selection: TaskCollection
    let onProfile: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionAnimation

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            destination(.today)
            destination(.upcoming)
            destination(.all)
            profile
        }
        .padding(Theme.Spacing.xs)
        .background(Theme.navigationBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.composer))
        .frame(maxWidth: Theme.Home.navigationMaxWidth)
        .animation(reduceMotion ? nil : Theme.Feedback.stateChange, value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Navigation")
        .accessibilityIdentifier("app.navigation")
    }

    private var profile: some View {
        Button(action: onProfile) {
            Image(systemName: "person.crop.circle")
                .font(Theme.Typography.toolbarIcon)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(Theme.navigationContent)
                .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Perfil")
        .accessibilityIdentifier("settings.open")
        .accessibilityShowsLargeContentViewer {
            Label("Perfil", systemImage: "person.crop.circle")
        }
    }

    private func destination(_ collection: TaskCollection) -> some View {
        let symbol = collection == .today ? "house" : collection == .all ? "list.bullet" : collection.symbol
        return Button {
            selection = collection
        } label: {
            Image(systemName: collection == .today && selection == collection ? "house.fill" : symbol)
                .font(Theme.Typography.toolbarIcon)
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
        .accessibilityLabel(Text(LocalizedStringKey(collection.rawValue)))
        .accessibilityAddTraits(selection == collection ? .isSelected : [])
        .accessibilityIdentifier("tab.\(collection)")
        .accessibilityShowsLargeContentViewer {
            Label(LocalizedStringKey(collection.rawValue), systemImage: symbol)
        }
    }
}
