import UIKit

/// Foto del carné físico, independiente de la foto de perfil.
enum CarnetImageStore {
    private static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("utp-card.jpg")
    }

    static func load() async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            UIImage(contentsOfFile: url.path)
        }.value
    }

    /// Conserva la misma validación que load, sin retener la imagen en Perfil.
    static func hasStoredImage() async -> Bool {
        await Task.detached(priority: .userInitiated) {
            UIImage(contentsOfFile: url.path) != nil
        }.value
    }

    static func save(_ image: UIImage) throws -> UIImage {
        guard image.size.width > 0, image.size.height > 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
        // Normaliza la orientación y limita el peso sin recortar el documento.
        let factor = min(1, 2400 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let normalized = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = normalized.jpegData(compressionQuality: 0.9),
              let stored = UIImage(data: data) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return stored
    }
}
