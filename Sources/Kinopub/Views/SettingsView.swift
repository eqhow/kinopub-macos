import SwiftUI

struct SettingsView: View {
    @AppStorage("kinopub.apiBase") private var customAPIBase = ""
    @State private var newAPIBase = ""
    @State private var saved = false

    var body: some View {
        TabView {
            Form {
                Section("API сервера kino.pub") {
                    TextField("Адрес API", text: $newAPIBase)
                        .textFieldStyle(.roundedBorder)
                        .onAppear {
                            newAPIBase = customAPIBase
                        }

                    HStack(spacing: 10) {
                        Button("Сохранить") {
                            customAPIBase = newAPIBase.trimmingCharacters(in: .whitespacesAndNewlines)
                            withAnimation { saved = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation { saved = false }
                            }
                        }
                        .disabled(newAPIBase.trimmingCharacters(in: .whitespacesAndNewlines) == customAPIBase)

                        if !customAPIBase.isEmpty {
                            Button("Сбросить на умолчание") {
                                customAPIBase = ""
                                newAPIBase = ""
                                withAnimation { saved = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    withAnimation { saved = false }
                                }
                            }
                        }
                    }

                    if saved {
                        Label("Сохранено. Перезапустите приложение, чтобы изменения вступили в силу.",
                              systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundColor(.green)
                    }

                    Text("По умолчанию: https://api.service-kp.com")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Можно также задать через переменную окружения KINOPUB_API_BASE")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Section("TMDB API (для логотипов)") {
                    Text("Ключ TMDB (v3) можно задать через переменную окружения KINOPUB_TMDB_KEY или\n`defaults write com.kinopub.mac kinopub.tmdbKey \"...\"`")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Сеть", systemImage: "network")
            }
        }
        .frame(width: 480, height: 340)
    }
}