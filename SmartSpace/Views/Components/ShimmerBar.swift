import SwiftUI

/// A lightweight shimmering placeholder bar (used for generating/loading states).
struct ShimmerBar: View {
    var height: CGFloat
    var widthFactor: CGFloat

    @State private var phase: CGFloat = -0.6

    var body: some View {
        GeometryReader { proxy in
            let fullWidth = proxy.size.width
            let w = max(20, fullWidth * widthFactor)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.secondary.opacity(0.16))
                .frame(width: w, height: height, alignment: .leading)
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .clear,
                                    .white.opacity(0.35),
                                    .clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .rotationEffect(.degrees(18))
                        .offset(x: phase * fullWidth * 1.6)
                        .blendMode(.plusLighter)
                }
                .mask(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .onAppear {
                    withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                        phase = 0.8
                    }
                }
        }
        .frame(height: height)
    }
}


