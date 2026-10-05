import SwiftUI
import UIKit

struct NotificationSettingsSection: View {
    @Environment(TasksViewModel.self) private var viewModel
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        if let reminders = viewModel.reminders {
            Section {
                Group {
                    switch reminders.authorizationStatus {
                    case .notDetermined:
                        Button {
                            Task {
                                _ = await reminders.authorize()
                                await viewModel.reconcileReminders()
                            }
                        } label: {
                            Label("Ativar notificações", systemImage: "bell.badge")
                                .frame(minHeight: Theme.Metrics.minTouchTarget)
                        }
                        .disabled(reminders.isRequestingPermission)
                        .accessibilityIdentifier("notifications.enable")
                    case .permitted:
                        Label("Notificações ativadas", systemImage: "bell.badge")
                            .foregroundStyle(Theme.textPrimary)
                    case .denied:
                        Label("Notificações desativadas", systemImage: "bell.slash")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if reminders.authorizationStatus != .notDetermined {
                        Button("Ajustes de notificações do iPhone") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                        }
                        .frame(minHeight: Theme.Metrics.minTouchTarget)
                        .accessibilityIdentifier("notifications.systemSettings")
                    }
                }
                .listRowBackground(Theme.surface)
            } header: {
                Text("Notificações")
            } footer: {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text("Defina um lembrete na tarefa para receber um aviso no horário escolhido, mesmo com o app fechado.")
                    Text("Os avisos seguem os ajustes de notificações e Foco do iPhone.")
                }
            }
            .task { await reminders.refreshAuthorization() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await reminders.refreshAuthorization() } }
            }
        }
    }
}
