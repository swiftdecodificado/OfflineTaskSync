import Foundation

struct RemoteTaskSnapshot: Sendable, Equatable {
    let id: UUID
    let title: String
    let isDone: Bool
    let updatedAt: Date
}
