import UIKit

/// Foto del carné físico por empresa, independiente de la foto de perfil.
enum CarnetImageStore {
    private static func url(empresa: TematicaEmpresa) -> URL {
        // Conservar el archivo original de UTP: no se migra ni se reemplaza.
        let archivo = empresa == .utp ? "utp-card.jpg" : "company-card-\(empresa.rawValue).jpg"
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(archivo)
    }

    static func load(empresa: TematicaEmpresa = .utp) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            UIImage(contentsOfFile: url(empresa: empresa).path)
        }.value
    }

    /// Conserva la misma validación que load, sin retener la imagen en Perfil.
    static func hasStoredImage(empresa: TematicaEmpresa = .utp) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            UIImage(contentsOfFile: url(empresa: empresa).path) != nil
        }.value
    }

    static func save(_ image: UIImage, empresa: TematicaEmpresa = .utp) throws -> UIImage {
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
        try data.write(to: url(empresa: empresa), options: [.atomic, .completeFileProtection])
        return stored
    }
}
