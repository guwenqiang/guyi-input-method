import SwiftUI

struct TranslatedRegionView: View {
    let text: String
    let bounds: CGRect
    let canvas: CGSize
    private var box: CGRect {
        CGRect(x: bounds.minX * canvas.width, y: (1 - bounds.maxY) * canvas.height,
               width: bounds.width * canvas.width, height: bounds.height * canvas.height)
            .insetBy(dx: -3, dy: -3)
            .intersection(CGRect(origin: .zero, size: canvas))
    }
    var body: some View {
        Text(text)
            .font(.system(size: max(9, bounds.height * canvas.height)))
            .minimumScaleFactor(0.5)
            .foregroundStyle(.black)
            .frame(width: box.width, height: box.height, alignment: .leading)
            .background(.white).clipped()
            .position(x: box.midX, y: box.midY)
            .help(text)
    }
}
