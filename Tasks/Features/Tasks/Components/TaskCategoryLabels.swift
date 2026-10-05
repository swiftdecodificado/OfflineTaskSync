import Foundation

extension TaskIcon {
    var title: String {
        switch self {
        case .exercise: AppLocalization.string("Exercise")
        case .study: AppLocalization.string("Study")
        case .work: AppLocalization.string("Work")
        case .shopping: AppLocalization.string("Shopping")
        case .walking: AppLocalization.string("Walking")
        case .health: AppLocalization.string("Health")
        case .home: AppLocalization.string("Home")
        case .music: AppLocalization.string("Music")
        }
    }
}

extension TaskCategoryFilter {
    var title: String {
        switch self {
        case .all: AppLocalization.string("Todas as categorias")
        case .category(let category): category.title
        case .uncategorized: AppLocalization.string("Sem categoria")
        }
    }
}
