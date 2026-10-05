import SwiftUI

struct TaskIconPicker: View {
    @Binding var selection: TaskIcon?
    var showsTitle = true
    var onSelect: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            if showsTitle {
                Text("Categoria")
                    .font(Theme.Typography.sectionLabel)
                    .foregroundStyle(Theme.textSecondary)
            }
            TaskCategoryStrip(selection: Binding(
                get: { selection.map(TaskCategoryFilter.category) ?? .uncategorized },
                set: { category in
                    if case .category(let icon) = category { selection = icon }
                    else { selection = nil }
                }
            ), includesAll: false, accessibilityPrefix: "task.icon.option",
               accessibilityID: "task.icon.options", onSelect: onSelect)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Categoria")
        .accessibilityValue(selection?.title ?? AppLocalization.string("Sem categoria"))
        .accessibilityIdentifier("task.iconPicker")
    }
}

struct TaskIconSelectionSheet: View {
    @Binding var selection: TaskIcon?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TaskIconPicker(selection: $selection, showsTitle: false, onSelect: { dismiss() })
                .padding(Theme.pageMargin)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(Theme.surfaceSecondary)
                .navigationTitle("Categoria da tarefa")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", systemImage: "xmark") { dismiss() }
                            .labelStyle(.iconOnly)
                            .tint(Theme.textPrimary)
                            .accessibilityIdentifier("task.icon.close")
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct TaskCategoryStrip: View {
    @Binding var selection: TaskCategoryFilter
    var includesAll = true
    var accessibilityPrefix = "tasks.category"
    var accessibilityID = "tasks.categoryFilter"
    var onSelect: () -> Void = {}
    @ScaledMetric(relativeTo: .footnote) private var cardWidth = Theme.Metrics.rowMinHeight + Theme.Spacing.xxl + Theme.Spacing.md
    @ScaledMetric(relativeTo: .footnote) private var cardHeight = Theme.Metrics.rowMinHeight + Theme.Spacing.xl + Theme.Spacing.md

    private var categories: [TaskCategoryFilter] {
        includesAll ? TaskCategoryFilter.allCases : [.uncategorized] + TaskIcon.allCases.map(TaskCategoryFilter.category)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                    ForEach(categories) { category in
                        categoryButton(category)
                            .id(category)
                    }
                }
                .padding(.vertical, Theme.Spacing.xxs)
            }
            .scrollIndicators(.hidden)
            .fixedSize(horizontal: false, vertical: true)
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
            .onChange(of: selection) { _, category in
                proxy.scrollTo(category, anchor: .center)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(includesAll ? Text("Filtrar por categoria") : Text("Categoria"))
        .accessibilityValue(selection.title)
        .accessibilityIdentifier(accessibilityID)
    }

    private func categoryButton(_ category: TaskCategoryFilter) -> some View {
        let selected = selection == category
        let icon = TaskIcon(rawValue: category.symbol)
        let content = Theme.CategoryPalette.foreground(for: icon)
        return Button { selection = category; onSelect() } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.xxs) {
                    if let icon {
                        TaskIconBadge(icon: icon, usesTaskPalette: true)
                    } else {
                        Image(systemName: category.symbol)
                            .font(Theme.Typography.headline)
                            .frame(width: Theme.Metrics.taskIconSize, height: Theme.Metrics.taskIconSize)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: Theme.Icon.checkmark)
                        .font(Theme.Typography.checkmark)
                        .opacity(selected ? 1 : 0)
                }
                .accessibilityHidden(true)
                Text(category == .all ? AppLocalization.string("All") : category.title)
                    .font(Theme.Typography.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.Spacing.sm)
            .frame(width: cardWidth, alignment: .leading)
            .frame(minHeight: cardHeight, alignment: .topLeading)
            .foregroundStyle(content)
            .background(Theme.CategoryPalette.background(for: icon), in: RoundedRectangle(cornerRadius: Theme.Radius.banner))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.banner)
                    .strokeBorder(selected ? content : Theme.border,
                                  lineWidth: selected ? Theme.Metrics.checkboxStroke : Theme.Metrics.borderStroke)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.banner))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("\(accessibilityPrefix).\(identifier(for: category))")
    }

    private func identifier(for category: TaskCategoryFilter) -> String {
        switch category {
        case .all: "all"
        case .category(let icon): icon.rawValue
        case .uncategorized: "none"
        }
    }
}
