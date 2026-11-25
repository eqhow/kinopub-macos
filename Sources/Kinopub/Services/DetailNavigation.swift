import CoreGraphics
import Foundation
import SwiftUI

/// Собственный стек деталок. Плюс «полёт» обложки: при открытии фильма
/// постер отдельным слоем перелетает из карточки в шапку страницы.
@MainActor
final class DetailNavigation: ObservableObject {
    struct Node: Identifiable {
        let id = UUID()
        let route: ItemRoute
    }

    /// Кадр перелёта обложки.
    struct Flight: Identifiable {
        let id = UUID()
        let url: URL?
        let from: CGRect
        let to: CGRect
    }

    /// Параметр открытия: если `true`, постер летит на всю ширину хедера.
    var fullHeroFlight = false

    @Published private(set) var stack: [Node] = []
    @Published private(set) var flight: Flight?

    /// Область деталки в координатах окна — цель перелёта.
    var detailFrame: CGRect = .zero

    var top: ItemRoute? { stack.last?.route }
    var isPresenting: Bool { !stack.isEmpty }

    func open(_ item: KinopubItem, sourceID: String, from sourceFrame: CGRect? = nil, artwork: URL? = nil) {
        // Полёт обложки в центр экрана выглядел навязчиво — открываем
        // деталку мягким появлением, без парящего постера.
        withAnimation(.easeInOut(duration: 0.26)) {
            stack.append(Node(route: ItemRoute(item: item, sourceID: sourceID)))
        }
    }

    func finishFlight(_ id: UUID) {
        guard flight?.id == id else { return }
        flight = nil
    }

    func pop() {
        guard !stack.isEmpty else { return }
        stack.removeLast()
    }

    func closeAll() {
        stack.removeAll()
        flight = nil
    }

    // MARK: - Flight target

    /// Цель перелёта: постер плавно увеличивается из позиции карточки
    /// в центр экрана (не летит в угол хедера).
    private func targetRect(for sourceFrame: CGRect) -> CGRect {
        let area = detailFrame.isEmpty
            ? CGRect(x: 240, y: 64, width: 1280, height: 820)
            : detailFrame
        // Масштабируем от размера карточки до крупного постера в центре
        let scale: CGFloat = fullHeroFlight ? 6.0 : 2.8
        let w = min(max(sourceFrame.width * scale, 200), area.width * 0.5)
        let h = min(max(sourceFrame.height * scale, 300), area.height * 0.6)
        return CGRect(
            x: area.minX + (area.width - w) / 2,
            y: area.minY + (area.height - h) / 2,
            width: w,
            height: h
        )
    }
}
