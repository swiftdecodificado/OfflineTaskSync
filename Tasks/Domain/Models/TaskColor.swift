import Foundation

enum TaskColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case yellow, lavender, mint, pink, blue, peach

    var id: Self { self }
    static let defaultColor: Self = .yellow
}

extension TaskSnapshot {
    var color: TaskColor { colorID.flatMap(TaskColor.init(rawValue:)) ?? .defaultColor }
}
