import SwiftUI

struct HomeProgressView: View {
    let progress: DayProgress
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("\(progress.completedCount) de \(progress.totalCount) concluídas")
                .font(Theme.Typography.metadata)
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Capsule()
                .fill(Theme.surfaceSecondary)
                .overlay {
                    DailyProgressFill(fraction: progress.fraction)
                        .fill(Theme.accent)
                        .animation(reduceMotion ? nil : .smooth(duration: Theme.Home.progressFillDuration),
                                   value: progress.fraction)
                }
                .frame(height: Theme.Spacing.xxs)
                .accessibilityHidden(true)
        }
        .padding(.bottom, Theme.Spacing.sm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Seu dia")
        .accessibilityValue(Text("Completed \(progress.completedCount) of \(progress.totalCount)"))
        .accessibilityIdentifier("home.progress")
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
