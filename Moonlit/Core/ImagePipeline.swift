import UIKit

enum ImagePipeline {
    static func prepareJPEG(_ image: UIImage, maxDimension: CGFloat = 2_048) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let size = image.size
            let scale = min(1, maxDimension / max(size.width, size.height))
            let target = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let normalized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: target))
            }
            guard let data = normalized.jpegData(compressionQuality: 0.82), data.count <= 10 * 1_024 * 1_024 else {
                throw ImagePipelineError.encodingFailed
            }
            return data
        }.value
    }
}

enum ImagePipelineError: LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        "Moonlit could not prepare this photo. Please choose a smaller image or retake it."
    }
}
