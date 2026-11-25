import Foundation

/// Общий запрос для строки поиска в сайдбаре и экрана поиска.
@MainActor
final class SearchState: ObservableObject {
    @Published var query = ""
    @Published private(set) var submitID = 0

    func submit() {
        submitID &+= 1
    }
}
