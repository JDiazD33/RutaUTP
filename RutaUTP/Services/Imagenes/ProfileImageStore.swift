//
//  ProfileImageStore.swift
//  RutaUTP
//
//  Persistencia de la foto de perfil en Documents.
//  
//  Fuente ÚNICA de la foto: la leen el drawer, Perfil, el Carné Digital
//  y Datos Personales. Estaba dentro de `SideDrawer.swift`.
//  
//  Nota: `CarnetImageStore` (la foto del carné físico) vive todavía en
//  `CarnetScannerView.swift`. Unificarlos es un trabajo aparte.

import UIKit
// MARK: - Persistencia de foto de perfil (Documents)
enum ProfileImageStore {
    private static var url: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("perfil_foto.jpg")
    }

    @discardableResult
    static func save(_ image: UIImage) -> Bool {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func load() -> UIImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}

