import SwiftUI
import AppKit

/// Модальное окно при запуске: новая версия + список изменений + «Обновить».
struct UpdateSheet: View {
    @ObservedObject var checker: UpdateChecker
    let info: UpdateChecker.UpdateInfo
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                ReleaseNotesView(markdown: info.notes.isEmpty
                    ? "Список изменений доступен на странице релиза."
                    : info.notes)
                    .padding(20)
            }
            .frame(height: 320)
            Divider()
            footer
        }
        .frame(width: 540)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text("Доступно обновление \(info.version)")
                    .font(.title3.weight(.semibold))
                Text("У вас установлена версия \(checker.currentVersion)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            status
            Spacer(minLength: 8)

            Button("Позже") { onClose() }
                .keyboardShortcut(.cancelAction)

            Button {
                if let file = checker.downloadedFile {
                    NSWorkspace.shared.activateFileViewerSelecting([file])
                } else {
                    Task { await checker.download() }
                }
            } label: {
                if checker.isDownloading {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Скачивание…")
                    }
                } else {
                    Text(checker.downloadedFile == nil ? "Обновить" : "Показать в Finder")
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(checker.isDownloading)
        }
        .padding(16)
    }

    @ViewBuilder
    private var status: some View {
        if let file = checker.downloadedFile {
            VStack(alignment: .leading, spacing: 2) {
                Label("Скачано: \(file.lastPathComponent)", systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
                    .lineLimit(1)
                Text("Распакуйте архив и замените Kinopub.app в «Программах».")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let error = checker.error {
            Text(error)
                .font(.callout)
                .foregroundStyle(.red)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("Архив скачается в «Загрузки».")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link("Страница релиза", destination: info.releaseURL)
                    .font(.caption)
            }
        }
    }
}

/// Простой рендер markdown-описания релиза: заголовки, списки,
/// код и обычный текст. Полноценный markdown SwiftUI.Text не умеет.
private struct ReleaseNotesView: View {
    let markdown: String

    private enum Block {
        case heading(String)
        case bullet(String)
        case text(String)
        case code(String)
        case divider
        case spacer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let text):
                    Text(inline(text))
                        .font(.headline)
                        .padding(.top, 4)
                case .bullet(let text):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        Text(inline(text))
                    }
                case .text(let text):
                    Text(inline(text))
                case .code(let text):
                    Text(text)
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                case .divider:
                    Divider().padding(.vertical, 2)
                case .spacer:
                    Color.clear.frame(height: 2)
                }
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var inCode = false

        for rawLine in markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                inCode.toggle()
                continue
            }
            if inCode {
                result.append(.code(rawLine))
                continue
            }
            if line.isEmpty {
                result.append(.spacer)
                continue
            }
            // HTML-блоки из GitHub-релиза (картинки, центрирование) пропускаем.
            if line.hasPrefix("<") || line.contains("<img") {
                continue
            }
            if line == "---" || line == "***" {
                result.append(.divider)
                continue
            }
            if line.hasPrefix("#") {
                let text = String(line.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { result.append(.heading(text)) }
                continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                result.append(.bullet(String(line.dropFirst(2))))
                continue
            }
            if let range = line.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                result.append(.bullet(String(line[range.upperBound...])))
                continue
            }
            result.append(.text(line))
        }
        return result
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}
