import SwiftUI

/// Заставка запуска: постер заполняет экран, очень мягко «дышит»,
/// ровно по центру — спиннер. Появление и исчезновение — чистый fade.
struct LaunchCurtain: View {
    let poster: URL?

    @State private var breathe = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                if let poster {
                    RemoteImage(url: poster, contentMode: .fill) {
                        Color.black
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .scaleEffect(breathe ? 1.05 : 1.0)
                    .overlay { Color.black.opacity(0.35) }
                }

                LinearGradient(
                    colors: [.black.opacity(0.2), .black.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .overlay {
                ProgressView()
                    .progressViewStyle(.circular)
                    .environment(\.colorScheme, .dark)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }
}
