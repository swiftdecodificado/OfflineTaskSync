import SwiftUI

struct PersistenceErrorBanner: View {
    @Environment(TasksViewModel.self) private var viewModel

    var body: some View {
        if let message = viewModel.serviceMessage ?? viewModel.reminders?.message {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Label(message, systemImage: Theme.Icon.failure)
                if viewModel.hasPendingCalendarRequests {
                    Button("Retry Calendar", action: viewModel.retryCalendarRequests)
                        .frame(minHeight: Theme.Metrics.minTouchTarget)
                }
                if viewModel.serviceMessage != nil {
                    Button("Dismiss") { viewModel.serviceMessage = nil }
                        .frame(minHeight: Theme.Metrics.minTouchTarget)
                } else {
                    Button("Retry") { Task { await viewModel.retryReminders() } }
                        .frame(minHeight: Theme.Metrics.minTouchTarget)
                }
            }
            .font(Theme.Typography.callout)
            .foregroundStyle(Theme.textPrimary)
            .padding(Theme.Spacing.md)
            .background(Theme.warningBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.banner))
        }
        if let failure = viewModel.failure {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Label(failure.message, systemImage: Theme.Icon.failure)
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.textPrimary)
                if failure == .load {
                    Button("Try Again") {
                        Task { await viewModel.refresh() }
                    }
                    .frame(minHeight: Theme.Metrics.minTouchTarget)
                } else {
                    if failure == .update || failure == .emptyTitle {
                        Button("Retry text edits", action: viewModel.retryTextEdits)
                            .frame(minHeight: Theme.Metrics.minTouchTarget)
                    }
                    Button("Dismiss", action: viewModel.dismissFailure)
                        .frame(minHeight: Theme.Metrics.minTouchTarget)
                }
            }
            .buttonStyle(.borderless)
            .controlSize(.large)
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.errorBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.banner))
        }
    }
}
