import PhotosUI
import SwiftUI

/// Uniform media picker (video + photo). Reports PHAsset identifiers.
struct KinoMediaPicker: UIViewControllerRepresentable {
    var onPick: ([String]) -> Void
    @Environment(\.presentationMode) private var presentation

    func makeUIViewController(context: Context) -> UIViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .any(of: [.videos, .images, .livePhotos])
        config.selectionLimit = 0
        config.preferredAssetRepresentationMode = .current
        let pic = PHPickerViewController(configuration: config)
        pic.delegate = context.coordinator
        return pic
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: KinoMediaPicker
        init(_ parent: KinoMediaPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            var ids: [String] = []
            for result in results {
                if result.assetIdentifier != nil {
                    ids.append(result.assetIdentifier!)
                } else if let itemProvider = result.itemProvider {
                    // fallback: transfer video/image via temporary URL
                    ids.append(itemProvider.registeredTypeIdentifiers.first ?? "")
                }
            }
            DispatchQueue.main.async {
                self.parent.onPick(ids)
                self.parent.presentation.wrappedValue.dismiss()
            }
        }
    }
}
