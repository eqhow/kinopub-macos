import Foundation
import SwiftUI

@MainActor
final class PlayerCoordinator: ObservableObject {
    @Published var request: PlayRequest?
    /// Идёт подготовка к воспроизведению (догрузка карточки, поиск ссылки).
    @Published var preparing = false
    @Published var preparingTitle: String?
    /// Постер для фона на время подготовки.
    @Published var preparingPoster: URL?

    func open(_ request: PlayRequest) {
        withAnimation(.easeInOut(duration: 0.3)) {
            self.request = request
            preparing = false
            preparingTitle = nil
            preparingPoster = nil
        }
    }

    func close() {
        request = nil
    }
}
