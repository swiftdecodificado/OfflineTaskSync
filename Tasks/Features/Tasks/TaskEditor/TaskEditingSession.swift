import Foundation
import Observation
import PhotosUI
import SwiftUI
import UIKit

@MainActor
@Observable
final class TaskEditingSession: Identifiable {
    let id = UUID()
    var draft: TaskDraft
    let original: TaskSnapshot?
    let editor: RichTaskEditorState
    let mediaStore: TaskMediaStore
    var isSaving = false
    var isImporting = false
    var importedCount = 0
    var importCount = 0
    var errorMessage: String?
    private(set) var finished = false
    private let initialDraft: TaskDraft
    @ObservationIgnored private var importTask: Task<Void, Never>?

    init(draft: TaskDraft = TaskDraft(), task: TaskSnapshot? = nil, mediaStore: TaskMediaStore) {
        var value = draft
        if let task {
            value.id = task.id
            value.title = task.title
            value.isDone = task.isDone
            value.notes = task.notes
            value.document = task.document
            value.color = task.color
            value.icon = task.icon
            value.dueDate = task.dueDate
            value.dueTime = task.dueTime
            value.dueEndTime = task.dueEndTime
            value.reminderDate = task.reminderDate
        }
        self.draft = value
        self.mediaStore = mediaStore
        initialDraft = value
        original = task
        editor = RichTaskEditorState(document: value.document, notes: value.notes)
    }

    var hasChanges: Bool { draft != initialDraft || editor.revision > 0 }
    var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving && !isImporting && !finished
            && editor.errorMessage == nil
    }

    func save(using viewModel: TasksViewModel) async -> Bool {
        guard canSave else { return false }
        do { try TaskSchedule.validate(draft) }
        catch { errorMessage = error.localizedDescription; return false }
        if let reminder = draft.reminderDate, reminder <= .now, reminder != original?.reminderDate {
            errorMessage = AppLocalization.string("Choose a future time for the reminder, or remove it.")
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            var value = draft
            value.document = try editor.document()
            value.notes = value.document?.plainText ?? ""
            let attachments = value.document?.attachments ?? []
            let copied = try await mediaStore.prepare(attachments, sessionID: id)
            guard await viewModel.saveEditingDraft(value, creating: original == nil) else {
                await mediaStore.rollback(copied)
                errorMessage = AppLocalization.string("Erro ao salvar. Seu conteúdo foi mantido. Tente novamente.")
                return false
            }
            finished = true
            let referenced = Set(viewModel.tasks.flatMap { $0.document?.attachments ?? [] }.map(\.id))
            await mediaStore.finish(sessionID: id, removed: original?.document?.attachments ?? [], keeping: referenced)
            return true
        } catch {
            errorMessage = AppLocalization.string("Erro ao salvar. Seu conteúdo foi mantido. Tente novamente.")
            return false
        }
    }

    func importPhotos(_ items: [PhotosPickerItem], kind: TaskAttachment.Kind) {
        guard !isImporting, !finished else { return }
        beginImport(count: items.count)
        importTask = Task {
            defer { endImport() }
            for item in items {
                do {
                    try Task.checkCancellation()
                    guard let media = try await item.loadTransferable(type: PickedTaskMedia.self) else { throw TaskMediaError.invalidFile }
                    do {
                        try await importOne(media.url, kind: kind)
                        await mediaStore.removeTransfer(media.url)
                    } catch {
                        await mediaStore.removeTransfer(media.url)
                        throw error
                    }
                } catch is CancellationError { return }
                catch { reportImportFailure(); return }
            }
        }
    }

    func importFiles(_ urls: [URL]) {
        guard !isImporting, !finished else { return }
        beginImport(count: urls.count)
        importTask = Task {
            defer { endImport() }
            for url in urls {
                do { try Task.checkCancellation(); try await importOne(url, kind: .file) }
                catch is CancellationError { return }
                catch { reportImportFailure(); return }
            }
        }
    }

    private func importOne(_ url: URL, kind: TaskAttachment.Kind) async throws {
        let attachment = try await mediaStore.importFile(url, kind: kind, sessionID: id)
        try Task.checkCancellation()
        let thumbnail = try await mediaStore.thumbnail(attachment, sessionID: id)
        editor.insert(attachment, thumbnail: thumbnail)
        importedCount += 1
    }

    private func beginImport(count: Int) {
        editor.textView.resignFirstResponder()
        isImporting = true
        importedCount = 0
        importCount = count
        UIAccessibility.post(notification: .announcement, argument: AppLocalization.string("Importando arquivos"))
    }

    private func endImport() {
        isImporting = false
        importTask = nil
        UIAccessibility.post(notification: .announcement, argument: AppLocalization.string("Importação finalizada"))
    }

    private func reportImportFailure() {
        errorMessage = AppLocalization.string("Não foi possível importar o arquivo. Verifique o espaço disponível e tente novamente.")
        UIAccessibility.post(notification: .announcement, argument: errorMessage)
    }

    func cancelImport() { importTask?.cancel() }

    func discard() async {
        guard !isSaving else { return }
        finished = true
        importTask?.cancel()
        await importTask?.value
        await mediaStore.discard(sessionID: id)
    }
}
