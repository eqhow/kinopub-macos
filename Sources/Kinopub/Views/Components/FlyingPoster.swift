import SwiftUI

/// Обложка, летящая из карточки в шапку страницы. Живёт поверх всего
/// интерфейса, поэтому координаты берём сразу в системе окна.
struct FlyingPoster: View {
    let flight: DetailNavigation.Flight
    let onFinish: (UUID) -> Void

    @State private var expanded = false
    @State private var faded = false

    var body: some View {
        RemoteImage(url: flight.url) {
            Color.gray.opacity(0.25)
        }
        .frame(width: rect.width, height: rect.height)
        .clipShape(RoundedRectangle(cornerRadius: expanded ? 16 : 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: expanded ? 16 : 10, style: .continuous)
                .strokeBorder(.white.opacity(expanded ? 0 : 0.12), lineWidth: 0.5)
        }
        .shadow(
            color: .black.opacity(expanded ? 0.5 : 0.2),
            radius: expanded ? 28 : 10,
            y: expanded ? 14 : 5
        )
        .position(x: rect.midX, y: rect.midY)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .opacity(faded ? 0 : 1)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.42)) {
                expanded = true
            }
            withAnimation(.easeInOut(duration: 0.3).delay(0.46)) {
                faded = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.82) {
                onFinish(flight.id)
            }
        }
    }

    private var rect: CGRect {
        expanded ? flight.to : flight.from
    }
}
