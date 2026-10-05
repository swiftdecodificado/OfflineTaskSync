import Foundation
@testable import Tasks

func makeTestMediaStore() -> TaskMediaStore {
    TaskMediaStore(root: FileManager.default.temporaryDirectory
        .appendingPathComponent("TestMedia-\(UUID().uuidString)", isDirectory: true))
}
