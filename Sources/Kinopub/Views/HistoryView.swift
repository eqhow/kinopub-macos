import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var api: APIClient
    @EnvironmentObject private var player: PlayerCoordinator
    @State private var entries: [HistoryEntry] = []
    @State private var loading = true

    var body: some View {
        Group {
            if loading {
                ProgressView().scaleEffect(0.8).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                ContentUnavailableView(
                    "История пуста",
                    systemImage: "clock",
                    description: Text("Просмотры будут отображаться здесь")
                )
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text("История")
                        .font(.largeTitle.weight(.bold))
                        .padding(.horizontal, 24)
                        .padding(.top, 18)
                        .padding(.bottom, 16)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            ForEach(days) { day in
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(Self.title(for: day.date))
                                        .font(.title3.weight(.bold))
                                        .foregroundColor(.secondary)

                                    LazyVGrid(
                                        columns: [GridItem(.adaptive(minimum: 320, maximum: 320), spacing: 16)],
                                        alignment: .leading,
                                        spacing: 16
                                    ) {
                                        ForEach(day.entries) { entry in
                                            Button {
                                                ResumePlayback.start(entry, api: api, player: player)
                                            } label: {
                                                HistoryWideCard(entry: entry)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .task {
            do {
                entries = try await api.history().dedupedByItem()
            } catch { entries = [] }
            loading = false
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Grouping

    private struct Day: Identifiable {
        let date: Date
        let entries: [HistoryEntry]
        var id: Date { date }
    }

    /// Группируем по дню последнего просмотра, свежие сверху.
    private var days: [Day] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) {
            calendar.startOfDay(for: $0.lastSeenDate)
        }
        return grouped.keys.sorted(by: >).map { day in
            Day(
                date: day,
                entries: grouped[day]!.sorted { ($0.lastSeen ?? 0) > ($1.lastSeen ?? 0) }
            )
        }
    }

    // MARK: - Dates

    private static func title(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Сегодня" }
        if calendar.isDateInYesterday(date) { return "Вчера" }

        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: Date())
        return (sameYear ? dayFormatter : dayYearFormatter).string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM"
        return f
    }()

    private static let dayYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM yyyy"
        return f
    }()
}
