import Foundation

enum TaskIcon: String, CaseIterable, Identifiable, Sendable {
    case exercise = "dumbbell.fill"
    case study = "book.closed.fill"
    case work = "briefcase.fill"
    case shopping = "cart.fill"
    case walking = "figure.walk"
    case health = "heart.fill"
    case home = "house.fill"
    case music = "music.note"

    var id: Self { self }
}

extension TaskSnapshot {
    var icon: TaskIcon? { iconName.flatMap(TaskIcon.init(rawValue:)) }
}

enum TaskCategoryFilter: Hashable, Identifiable, CaseIterable {
    case all
    case category(TaskIcon)
    case uncategorized

    var id: Self { self }

    static var allCases: [Self] {
        [.all] + TaskIcon.allCases.map(Self.category) + [.uncategorized]
    }

    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .category(let category): category.rawValue
        case .uncategorized: "tray"
        }
    }

    func includes(_ task: TaskSnapshot) -> Bool {
        switch self {
        case .all: true
        case .category(let category): task.icon == category
        case .uncategorized: task.icon == nil
        }
    }
}
