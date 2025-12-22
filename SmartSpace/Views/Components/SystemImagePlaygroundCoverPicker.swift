import SwiftUI
import UIKit

#if canImport(ImagePlayground)
import ImagePlayground
#endif

/// Presents the system Image Playground UI and returns the created image as `Data`.
/// Falls back to a simple "not available" message on platforms where ImagePlayground isn't present.
struct SystemImagePlaygroundCoverPicker: View {
    @Binding var isPresented: Bool
    let prompt: String
    let onImageData: (Data) -> Void

    var body: some View {
        #if canImport(ImagePlayground)
        ImagePlaygroundViewControllerRepresentable(
            isPresented: $isPresented,
            prompt: prompt,
            onImageData: onImageData
        )
        .ignoresSafeArea()
        #else
        VStack(spacing: 12) {
            Text("Image Playground isn’t available on this device.")
                .font(.headline)
            Text("Requires iOS 18.1+ and a device that supports Apple Intelligence image generation.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { isPresented = false }
            }
        }
        #endif
    }
}

#if canImport(ImagePlayground)
@MainActor
private struct ImagePlaygroundViewControllerRepresentable: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let prompt: String
    let onImageData: (Data) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, onImageData: onImageData)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = ImagePlaygroundViewController()
        vc.delegate = context.coordinator

        // Seed with the user's prompt (if any). If empty, let the user type freely in the system UI.
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        vc.concepts = trimmed.isEmpty ? [] : [.text(trimmed)]

        // User requirement: always use Animation style.
        vc.allowedGenerationStyles = [.animation]
        vc.selectedGenerationStyle = .animation

        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    final class Coordinator: NSObject, ImagePlaygroundViewController.Delegate {
        private let isPresented: Binding<Bool>
        private let onImageData: (Data) -> Void

        init(isPresented: Binding<Bool>, onImageData: @escaping (Data) -> Void) {
            self.isPresented = isPresented
            self.onImageData = onImageData
        }

        func imagePlaygroundViewController(
            _ imagePlaygroundViewController: ImagePlaygroundViewController,
            didCreateImageAt imageURL: URL
        ) {
            if let data = try? Data(contentsOf: imageURL) {
                onImageData(data)
            }
            isPresented.wrappedValue = false
        }

        func imagePlaygroundViewControllerDidCancel(_ imagePlaygroundViewController: ImagePlaygroundViewController) {
            isPresented.wrappedValue = false
        }
    }
}
#endif


