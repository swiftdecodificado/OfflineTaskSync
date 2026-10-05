import SwiftData
import Foundation

enum TasksSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [StoredTask.self, StoredDeletion.self] }

    @Model
    final class StoredTask {
        var id: UUID
        var title: String
        var isDone: Bool
        var updatedAt: Date
        var pendingSync: Bool

        init(id: UUID, title: String, isDone: Bool, updatedAt: Date, pendingSync: Bool) {
            self.id = id
            self.title = title
            self.isDone = isDone
            self.updatedAt = updatedAt
            self.pendingSync = pendingSync
        }
    }

    @Model
    final class StoredDeletion {
        var id: UUID
        var requestedAt: Date

        init(id: UUID, requestedAt: Date) {
            self.id = id
            self.requestedAt = requestedAt
        }
    }
}

enum TasksSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] { [StoredTask.self, StoredDeletion.self] }

    @Model
    final class StoredTask {
        var id: UUID
        var title: String
        var isDone: Bool
        var updatedAt: Date
        var pendingSync: Bool
        var notes: String = ""
        var dueDate: Date?
        var reminderDate: Date?
        var calendarEventID: String?
        var calendarLinkDate: Date?

        init(id: UUID, title: String, isDone: Bool, updatedAt: Date, pendingSync: Bool) {
            self.id = id
            self.title = title
            self.isDone = isDone
            self.updatedAt = updatedAt
            self.pendingSync = pendingSync
        }
    }

    @Model
    final class StoredDeletion {
        var id: UUID
        var requestedAt: Date

        init(id: UUID, requestedAt: Date) {
            self.id = id
            self.requestedAt = requestedAt
        }
    }
}

enum TasksSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }
    static var models: [any PersistentModel.Type] { [StoredTask.self, StoredDeletion.self] }

    @Model
    final class StoredTask {
        var id: UUID
        var title: String
        var isDone: Bool
        var updatedAt: Date
        var pendingSync: Bool
        var notes: String = ""
        var dueDate: Date?
        var dueTime: Date?
        var reminderDate: Date?
        var calendarEventID: String?
        var calendarLinkDate: Date?

        init(id: UUID, title: String, isDone: Bool, updatedAt: Date, pendingSync: Bool) {
            self.id = id
            self.title = title
            self.isDone = isDone
            self.updatedAt = updatedAt
            self.pendingSync = pendingSync
        }
    }

    @Model
    final class StoredDeletion {
        var id: UUID
        var requestedAt: Date

        init(id: UUID, requestedAt: Date) {
            self.id = id
            self.requestedAt = requestedAt
        }
    }
}

enum TasksSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }
    static var models: [any PersistentModel.Type] { [StoredTask.self, StoredDeletion.self] }

    @Model
    final class StoredTask {
        var id: UUID
        var title: String
        var isDone: Bool
        var updatedAt: Date
        var pendingSync: Bool
        var notes: String = ""
        var dueDate: Date?
        var dueTime: Date?
        var reminderDate: Date?
        var calendarEventID: String?
        var calendarLinkDate: Date?
        var iconName: String?

        init(id: UUID, title: String, isDone: Bool, updatedAt: Date, pendingSync: Bool) {
            self.id = id
            self.title = title
            self.isDone = isDone
            self.updatedAt = updatedAt
            self.pendingSync = pendingSync
        }
    }

    @Model
    final class StoredDeletion {
        var id: UUID
        var requestedAt: Date

        init(id: UUID, requestedAt: Date) {
            self.id = id
            self.requestedAt = requestedAt
        }
    }
}

enum TasksSchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }
    static var models: [any PersistentModel.Type] { [StoredTask.self, StoredDeletion.self] }

    @Model
    final class StoredTask {
        var id: UUID
        var title: String
        var isDone: Bool
        var updatedAt: Date
        var pendingSync: Bool
        var notes: String = ""
        var documentData: Data?
        var dueDate: Date?
        var dueTime: Date?
        var reminderDate: Date?
        var calendarEventID: String?
        var calendarLinkDate: Date?
        var iconName: String?

        init(id: UUID, title: String, isDone: Bool, updatedAt: Date, pendingSync: Bool) {
            self.id = id
            self.title = title
            self.isDone = isDone
            self.updatedAt = updatedAt
            self.pendingSync = pendingSync
        }
    }

    @Model
    final class StoredDeletion {
        var id: UUID
        var requestedAt: Date

        init(id: UUID, requestedAt: Date) {
            self.id = id
            self.requestedAt = requestedAt
        }
    }
}

enum TasksSchemaV6: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(6, 0, 0) }
    static var models: [any PersistentModel.Type] { [StoredTask.self, StoredDeletion.self] }

    @Model
    final class StoredTask {
        var id: UUID
        var title: String
        var isDone: Bool
        var updatedAt: Date
        var pendingSync: Bool
        var notes: String = ""
        var documentData: Data?
        var dueDate: Date?
        var dueTime: Date?
        var reminderDate: Date?
        var calendarEventID: String?
        var calendarLinkDate: Date?
        var iconName: String?
        var colorID: String?

        init(id: UUID, title: String, isDone: Bool, updatedAt: Date, pendingSync: Bool) {
            self.id = id
            self.title = title
            self.isDone = isDone
            self.updatedAt = updatedAt
            self.pendingSync = pendingSync
        }
    }

    @Model
    final class StoredDeletion {
        var id: UUID
        var requestedAt: Date

        init(id: UUID, requestedAt: Date) {
            self.id = id
            self.requestedAt = requestedAt
        }
    }
}

enum TasksSchemaV7: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(7, 0, 0) }
    static var models: [any PersistentModel.Type] { [StoredTask.self, StoredDeletion.self] }

    @Model
    final class StoredTask {
        var id: UUID
        var title: String
        var isDone: Bool
        var updatedAt: Date
        var pendingSync: Bool
        var notes: String = ""
        var documentData: Data?
        var dueDate: Date?
        var dueTime: Date?
        var dueEndTime: Date?
        var reminderDate: Date?
        var calendarEventID: String?
        var calendarLinkDate: Date?
        var iconName: String?
        var colorID: String?

        init(id: UUID, title: String, isDone: Bool, updatedAt: Date, pendingSync: Bool) {
            self.id = id
            self.title = title
            self.isDone = isDone
            self.updatedAt = updatedAt
            self.pendingSync = pendingSync
        }
    }

    @Model
    final class StoredDeletion {
        var id: UUID
        var requestedAt: Date

        init(id: UUID, requestedAt: Date) {
            self.id = id
            self.requestedAt = requestedAt
        }
    }
}

enum TasksMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [TasksSchemaV1.self, TasksSchemaV2.self, TasksSchemaV3.self, TasksSchemaV4.self, TasksSchemaV5.self, TasksSchemaV6.self, TasksSchemaV7.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: TasksSchemaV1.self, toVersion: TasksSchemaV2.self),
         .lightweight(fromVersion: TasksSchemaV2.self, toVersion: TasksSchemaV3.self),
         .lightweight(fromVersion: TasksSchemaV3.self, toVersion: TasksSchemaV4.self),
         .lightweight(fromVersion: TasksSchemaV4.self, toVersion: TasksSchemaV5.self),
         .lightweight(fromVersion: TasksSchemaV5.self, toVersion: TasksSchemaV6.self),
         .lightweight(fromVersion: TasksSchemaV6.self, toVersion: TasksSchemaV7.self)]
    }
}

typealias StoredTask = TasksSchemaV7.StoredTask
typealias StoredDeletion = TasksSchemaV7.StoredDeletion
