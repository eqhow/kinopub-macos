import SwiftUI

/// Хранит цвет темы для каждой открытой деталки.
/// Пока верхняя деталка открыта, её цвет красит весь интерфейс.
@MainActor
final class ThemeStore: ObservableObject {
    @Published private var colors: [UUID: Color] = [:]

    func set(_ color: Color, for id: UUID) {
        guard colors[id] != color else { return }
        colors[id] = color
    }

    func remove(_ id: UUID) {
        guard colors[id] != nil else { return }
        colors.removeValue(forKey: id)
    }

    func tint(for id: UUID?) -> Color? {
        guard let id else { return nil }
        return colors[id]
    }
}
