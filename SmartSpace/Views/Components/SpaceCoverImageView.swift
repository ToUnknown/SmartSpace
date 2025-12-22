import SwiftUI
import UIKit

/// Renders a Space cover image if available, otherwise falls back to `smartspace_logo`.
/// The fallback asset is rendered as template so it adapts (black in light mode, white in dark mode).
struct SpaceCoverImageView: View {
    let space: Space
    var size: CGFloat = 36
    var cornerRadius: CGFloat = 10
    var showsBackground: Bool = true
    var showsBorder: Bool = true

    var body: some View {
        let image = Group {
            if space.coverStatus == .ready,
               let data = space.coverImageData,
               let uiImage = UIImage(data: data)
            {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image("smartspace_logo")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.primary)
                    .padding(size * 0.18)
            }
        }

        return image
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                if showsBorder {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.secondary.opacity(0.12), lineWidth: 1)
                }
            }
            .background {
                if showsBackground {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.secondary.opacity(0.06))
                }
            }
            .accessibilityHidden(true)
    }
}


