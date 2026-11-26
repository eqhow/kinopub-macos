import SwiftUI

/// Единая кнопка «Смотреть». На HeroSlider — белая, в деталке —
/// красится в акцент страницы (цвет постера).
struct PlayButton: View {
    let action: () -> Void
    var label: String = "Смотреть"
    var systemImage: String = "play.fill"
    /// Цвет кнопки. Если не задан — белая с чёрным текстом.
    var tint: Color? = nil

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .font(.headline)
                .padding(.horizontal, 22)
                .padding(.vertical, 11)
                .background(buttonColor, in: Capsule())
                .foregroundColor(tint != nil ? .white : .black)
        }
        .buttonStyle(.plain)
    }

    private var buttonColor: Color {
        tint ?? .white
    }
}

/// Полупрозрачная капсула для второстепенных действий (трейлер,
/// скрыть трейлер). Красится в акцент страницы, если он передан.
struct SecondaryButton: View {
    let action: () -> Void
    var label: String
    var systemImage: String? = nil
    /// Акцентный цвет страницы. Если задан — кнопка тонируется в него.
    var tint: Color? = nil

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(label)
            }
            .font(.headline)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background((tint?.opacity(0.22) ?? .white.opacity(0.12)), in: Capsule())
            .overlay {
                if let tint {
                    Capsule().strokeBorder(tint.opacity(0.45), lineWidth: 1)
                }
            }
            .foregroundColor(.white)
        }
        .buttonStyle(.plain)
    }
}

/// Единая круглая кнопка «Назад» / «Закрыть» (только визуал, без
/// внешних отступов). Вызывающий добавляет `.padding()` по месту.
struct CloseCircleButton: View {
    let action: () -> Void
    /// Иконка: `"chevron.left"` (назад), `"xmark"` (закрыть).
    var icon: String = "chevron.left"
    /// Текст рядом с иконкой (название фильма в деталке).
    var label: String? = nil
    /// Показывать ли текст (для fade in/out по скроллу).
    var labelVisible: Bool = true

    var body: some View {
        HStack(spacing: 8) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.black.opacity(0.38), in: Circle())
                    .overlay {
                        Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
                    }
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)

            if let label {
                Button(action: action) {
                    Text(label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(.black.opacity(0.38), in: Capsule())
                        .overlay {
                            Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
                        }
                }
                .buttonStyle(.plain)
                .opacity(labelVisible ? 1 : 0)
                .allowsHitTesting(labelVisible)
                .animation(.easeInOut(duration: 0.2), value: labelVisible)
            }
        }
    }
}