import AppKit
import CoreImage
import SwiftUI

/// Средний цвет кадра — им подкрашивается страница фильма.
@MainActor
final class ArtworkPalette {
    static let shared = ArtworkPalette()

    private var cache: [URL: Color] = [:]
    private let context = CIContext(options: [.workingColorSpace: NSNull()])

    func color(for url: URL) async -> Color? {
        if let cached = cache[url] { return cached }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let image = NSImage(data: data),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }

        let input = CIImage(cgImage: cgImage)
        guard input.extent.width > 0 else { return nil }

        // Сжимаем до 48 пикселей: средний цвет считается мгновенно.
        let scale = 48 / input.extent.width
        let small = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let extent = small.extent.insetBy(dx: small.extent.width * 0.12, dy: small.extent.height * 0.12)

        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: small,
            kCIInputExtentKey: CIVector(cgRect: extent),
        ]),
        let output = filter.outputImage
        else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        let base = NSColor(
            srgbRed: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )
        let color = Color(nsColor: tuned(base))
        cache[url] = color
        return color
    }

    /// Подтягиваем насыщенность и яркость, чтобы серые кадры не давали грязь.
    private func tuned(_ color: NSColor) -> NSColor {
        guard let srgb = color.usingColorSpace(.sRGB) else { return color }

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        srgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        return NSColor(
            hue: hue,
            saturation: min(0.85, max(0.30, saturation * 1.5)),
            brightness: min(0.85, max(0.42, brightness * 1.25)),
            alpha: 1
        )
    }
}
