import Foundation
import Observation
import UserNotifications

enum ReminderAccess: Equatable, Sendable { case notDetermined, permitted, denied }

struct ReminderRequest: Equatable, Sendable {
    let id: String
    let title: String
    let date: Date
}

@MainActor
protocol ReminderCenter: AnyObject {
    func access() async -> ReminderAccess
    func requestAccess() async throws -> Bool
    func pending() async -> [ReminderRequest]
    func add(_ request: ReminderRequest) async throws
    func remove(ids: [String])
    func cleanDelivered(activeIDs: Set<String>) async
}

@MainActor
final class LocalReminderCenter: NSObject, ReminderCenter, UNUserNotificationCenterDelegate {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        center.delegate = self
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func access() async -> ReminderAccess {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .authorized, .provisional, .ephemeral: .permitted
        default: .denied
        }
    }

    func requestAccess() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func pending() async -> [ReminderRequest] {
        await center.pendingNotificationRequests().compactMap { request in
            guard request.identifier.hasPrefix(TaskReminders.prefix),
                  let trigger = request.trigger as? UNCalendarNotificationTrigger,
                  let date = trigger.nextTriggerDate() else { return nil }
            return ReminderRequest(id: request.identifier, title: request.content.title, date: date)
        }
    }

    func add(_ request: ReminderRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = AppLocalization.string("É hora da sua tarefa.")
        content.sound = .default
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: request.date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await center.add(UNNotificationRequest(identifier: request.id, content: content, trigger: trigger))
    }

    func remove(ids: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    func cleanDelivered(activeIDs: Set<String>) async {
        let obsolete = await center.deliveredNotifications().map(\.request.identifier)
            .filter { $0.hasPrefix(TaskReminders.prefix) && !activeIDs.contains($0) }
        center.removeDeliveredNotifications(withIdentifiers: obsolete)
    }
}

@MainActor @Observable
final class TaskReminders {
    static let prefix = "task-reminder."
    private let center: any ReminderCenter
    private var tail: Task<Void, Never>?
    private(set) var message: String?
    private(set) var authorizationStatus: ReminderAccess = .notDetermined
    private(set) var isRequestingPermission = false
    @ObservationIgnored private var permissionTask: Task<Bool, Never>?

    init(center: any ReminderCenter) { self.center = center }

    func refreshAuthorization() async {
        authorizationStatus = await center.access()
    }

    func authorize() async -> Bool {
        if let permissionTask { return await permissionTask.value }
        isRequestingPermission = true
        let request = Task { await requestPermission() }
        permissionTask = request
        let granted = await request.value
        permissionTask = nil
        isRequestingPermission = false
        return granted
    }

    private func requestPermission() async -> Bool {
        do {
            await refreshAuthorization()
            switch authorizationStatus {
            case .permitted:
                message = nil
                return true
            case .notDetermined:
                let granted = try await center.requestAccess()
                await refreshAuthorization()
                if granted { message = nil; return true }
            case .denied: break
            }
            message = AppLocalization.string("Notifications are disabled. Allow notifications for this app in Settings, then try again.")
        } catch {
            message = AppLocalization.string("Couldn't request notification access. Try again.")
        }
        return false
    }

    func reconcile(tasks: [TaskSnapshot], now: Date = .now) async {
        let previous = tail
        let next = Task { [self] in
            await previous?.value
            await update(tasks: tasks, now: now)
        }
        tail = next
        await next.value
    }

    private func update(tasks: [TaskSnapshot], now: Date) async {
        let active = tasks.filter { !$0.isDone && $0.reminderDate != nil }
        await center.cleanDelivered(activeIDs: Set(active.map { Self.prefix + $0.id.uuidString }))
        let access = await center.access()
        authorizationStatus = access
        let candidates = active.filter { $0.reminderDate! > now }.sorted {
            if $0.reminderDate != $1.reminderDate { return $0.reminderDate! < $1.reminderDate! }
            return $0.id.uuidString < $1.id.uuidString
        }
        // iOS limits pending local notifications; keep the nearest reminders scheduled.
        let desired = access == .permitted ? candidates.prefix(64).map {
            ReminderRequest(id: Self.prefix + $0.id.uuidString, title: $0.title,
                            date: Date(timeIntervalSince1970: floor($0.reminderDate!.timeIntervalSince1970)))
        } : []
        let pending = await center.pending()
        let ids = Set(desired.map(\.id))
        center.remove(ids: pending.map(\.id).filter { !ids.contains($0) })
        do {
            for request in desired where !pending.contains(request) { try await center.add(request) }
            if !active.isEmpty && access != .permitted {
                message = AppLocalization.string("Saved reminders aren't scheduled. Allow notifications in Settings.")
            } else if candidates.count > 64 {
                message = AppLocalization.string("The next 64 reminders are scheduled. Open the app again to schedule later reminders as space becomes available.")
            } else {
                message = nil
            }
        } catch {
            message = AppLocalization.string("Tasks are saved, but some reminders couldn't be scheduled. Open the app again or tap Retry.")
        }
    }
}
