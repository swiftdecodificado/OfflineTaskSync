import SwiftUI

struct Composer: View {
    @Environment(\.dismiss) private var dismiss
    @State private var session: TaskEditingSession

    init(draft: TaskDraft = TaskDraft(), mediaStore: TaskMediaStore) {
        _session = State(initialValue: TaskEditingSession(draft: draft, mediaStore: mediaStore))
    }

    var body: some View {
        TaskFullEditor(session: session) { dismiss() }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
    }
}
