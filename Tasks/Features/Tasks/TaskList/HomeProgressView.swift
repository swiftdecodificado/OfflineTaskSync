import SwiftUI

struct HomeProgressView: View {
    let progress: DayProgress
    var categoryTitle: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xxs))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs))
            layout {
                Image(systemName: "chart.bar.xaxis")
                    .font(Theme.Typography.headline)
                    .frame(width: Theme.Metrics.minTouchTarget, height: Theme.Metrics.minTouchTarget)
                    .background(Theme.highlightContent.opacity(0.08), in: Circle())
                    .accessibilityHidden(true)
                Text(categoryTitle ?? AppLocalization.string("Seu dia"))
                    .font(Theme.Typography.headline)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Text("Today")
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.highlightContent)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text("\(progress.completedCount) de \(progress.totalCount) concluídas")
                    .font(Theme.Typography.sectionTitle)
                    .monospacedDigit()
                    .foregroundStyle(Theme.highlightContent)
                HStack(spacing: Theme.Spacing.xxs) {
                    Text(progress.pendingCount, format: .number)
                        .monospacedDigit()
                    Text("Remaining")
                }
                .font(Theme.Typography.metadata)
                .foregroundStyle(Theme.highlightContent)
            }
            bar("Completed", symbol: "checkmark.circle", count: progress.completedCount, color: Theme.highlightContent)
            bar("Pending", symbol: "clock", count: progress.pendingCount, color: Theme.highlightContent.opacity(0.65))
        }
        .padding(Theme.Layout.cardInset)
        .foregroundStyle(Theme.highlightContent)
        .background(Theme.lime, in: RoundedRectangle(cornerRadius: Theme.Radius.composer))
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(categoryTitle ?? AppLocalization.string("Seu dia")))
        .accessibilityValue(Text("\(Text("Completed \(progress.completedCount) of \(progress.totalCount)")), \(Text("Remaining")): \(progress.pendingCount)"))
        .accessibilityIdentifier("home.progress")
    }

    private func bar(_ title: LocalizedStringKey, symbol: String, count: Int, color: Color) -> some View {
        let fraction = progress.totalCount == 0 ? 0 : Double(count) / Double(progress.totalCount)
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                Label(title, systemImage: symbol)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Theme.Spacing.xs)
                Text(count, format: .number)
                    .monospacedDigit()
            }
            .font(Theme.Typography.metadataEmphasis)
            .foregroundStyle(Theme.highlightContent)
            Capsule()
                .fill(Theme.highlightContent.opacity(0.12))
                .overlay {
                    DailyProgressFill(fraction: fraction)
                        .fill(color)
                        .animation(reduceMotion ? nil : .smooth(duration: Theme.Home.progressFillDuration), value: fraction)
                }
                .frame(height: Theme.Spacing.sm)
                .accessibilityHidden(true)
        }
    }
}

@Animatable
private struct DailyProgressFill: Shape {
    var fraction: Double

    func path(in rect: CGRect) -> Path {
        let width = rect.width * min(max(fraction, 0), 1)
        let fill = CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height)
        return Path(roundedRect: fill, cornerRadius: rect.height / 2)
    }
}

struct DayCompletionSummary: View {
    var celebrating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(Theme.Typography.toolbarIcon)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(Theme.highlightContent)
                .frame(width: Theme.Metrics.minTouchTarget, height: Theme.Metrics.minTouchTarget)
                .background(Theme.secondaryGradient, in: Circle())
                .symbolEffect(.bounce, value: celebrating)
                .symbolEffectsRemoved(reduceMotion)
                .overlay {
                    if celebrating { CompletionBurst() }
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text("Por hoje, tá feito.")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text("Todas as tarefas de hoje concluídas. Aproveite seu tempo.")
                    .font(Theme.Typography.metadata)
                    .foregroundStyle(Theme.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct DayCompletionCelebration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var celebrating = false

    var body: some View {
        DayCompletionSummary(celebrating: celebrating && !reduceMotion)
            .padding(Theme.Spacing.md)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("home.dayCompleted")
            .allowsHitTesting(false)
            .task {
                do {
                    try await Task.sleep(for: .milliseconds(50))
                    celebrating = true
                } catch {}
            }
    }
}

private struct CompletionBurst: View {
    @State private var startedAt = Date.now

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = max(0, timeline.date.timeIntervalSince(startedAt))
            let progress = min(elapsed / 1.2, 1)
            ZStack {
                ForEach(0..<12, id: \.self) { index in
                    let angle = Double(index) * .pi / 6
                    let distance = Theme.Spacing.md + (Theme.Spacing.xxl + Theme.Spacing.sm) * progress
                    Capsule()
                        .fill(index.isMultiple(of: 2) ? Theme.lime : Theme.cyan)
                        .frame(width: Theme.Spacing.xxs, height: Theme.Spacing.xs)
                        .rotationEffect(.radians(angle + progress))
                        .offset(x: cos(angle) * distance, y: sin(angle) * distance)
                        .opacity(1 - progress)
                }
            }
        }
        .frame(width: Theme.Metrics.minTouchTarget, height: Theme.Metrics.minTouchTarget)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
