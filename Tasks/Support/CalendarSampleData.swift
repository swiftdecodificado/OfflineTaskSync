#if DEBUG
import Foundation
import SwiftData

@MainActor
enum CalendarSampleData {
    private struct Activity {
        let title: String
        let notes: String
        let dayOffset: Int
        let hour: Int
        let minute: Int
        let duration: Int
        let color: TaskColor
        let icon: TaskIcon
        var isDone = false
    }

    static func replace(in store: PersistenceContainer, now: Date = .now,
                        calendar: Calendar = .current, beforeSave: () throws -> Void = {}) throws -> Int {
        let activities: [Activity] = [
            .init(title: "Caminhada da manhã", notes: "Caminhar por 30 minutos e levar água.", dayOffset: 0, hour: 7, minute: 0, duration: 30, color: .mint, icon: .walking, isDone: true),
            .init(title: "Organizar a semana", notes: "Revisar os compromissos e escolher as prioridades.", dayOffset: 0, hour: 8, minute: 30, duration: 30, color: .yellow, icon: .home, isDone: true),
            .init(title: "Revisar o projeto", notes: "Conferir as entregas e anotar os próximos passos.", dayOffset: 0, hour: 10, minute: 0, duration: 60, color: .blue, icon: .work),
            .init(title: "Estudar Swift", notes: "Praticar navegação e estado com um exemplo pequeno.", dayOffset: 0, hour: 14, minute: 0, duration: 45, color: .lavender, icon: .study),
            .init(title: "Comprar frutas", notes: "Banana, maçã, laranja e itens para o café.", dayOffset: 0, hour: 17, minute: 30, duration: 30, color: .peach, icon: .shopping),
            .init(title: "Ler antes de dormir", notes: "Ler um capítulo e separar uma ideia para amanhã.", dayOffset: 0, hour: 21, minute: 30, duration: 30, color: .pink, icon: .study),
            .init(title: "Treino", notes: "Aquecimento, treino e alongamento.", dayOffset: 1, hour: 7, minute: 30, duration: 60, color: .mint, icon: .exercise),
            .init(title: "Planejar a próxima entrega", notes: "Dividir a entrega em atividades menores.", dayOffset: 1, hour: 9, minute: 0, duration: 45, color: .blue, icon: .work),
            .init(title: "Praticar música", notes: "Repetir os trechos difíceis por 30 minutos.", dayOffset: 3, hour: 18, minute: 0, duration: 30, color: .pink, icon: .music),
            .init(title: "Revisão da semana", notes: "Revisar o que foi concluído e ajustar o planejamento.", dayOffset: 7, hour: 10, minute: 0, duration: 45, color: .yellow, icon: .work),
            .init(title: "Organizar os documentos", notes: "Separar os arquivos e conferir as pendências.", dayOffset: 14, hour: 15, minute: 0, duration: 60, color: .lavender, icon: .home),
            .init(title: "Planejar o próximo mês", notes: "Reservar tempo para estudo, trabalho e descanso.", dayOffset: 21, hour: 18, minute: 30, duration: 30, color: .peach, icon: .home)
        ]
        let context = ModelContext(store.container)
        context.autosaveEnabled = false
        do {
            for task in try context.fetch(FetchDescriptor<StoredTask>()) { context.delete(task) }
            for deletion in try context.fetch(FetchDescriptor<StoredDeletion>()) { context.delete(deletion) }
            for activity in activities {
                guard let day = calendar.date(byAdding: .day, value: activity.dayOffset, to: calendar.startOfDay(for: now)),
                      let start = calendar.date(bySettingHour: activity.hour, minute: activity.minute, second: 0, of: day),
                      let end = calendar.date(byAdding: .minute, value: activity.duration, to: start) else {
                    throw TaskScheduleError.invalidEnd
                }
                let task = StoredTask(id: UUID(), title: activity.title, isDone: activity.isDone,
                                      updatedAt: now, pendingSync: true)
                task.notes = activity.notes
                task.dueDate = day
                task.dueTime = start
                task.dueEndTime = end
                task.colorID = activity.color.rawValue
                task.iconName = activity.icon.rawValue
                context.insert(task)
            }
            try beforeSave()
            try context.save()
            return activities.count
        } catch {
            context.rollback()
            throw error
        }
    }
}
#endif
