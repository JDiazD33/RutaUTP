//
//  SeniasService.swift
//  RutaUTP
//
//  Resuelve una clave estable a un clip de seña del bundle.
//
//  Diseño: el contenido viaja DENTRO de la app (carpeta senias/), igual que el
//  feed GTFS. Por eso el Modo Señas funciona sin conexión. Si el paquete crece
//  mucho se migra a On-Demand Resources, pero no antes de que haga falta.
//

import Foundation
import AVFoundation

final class SeniasService {

    static let shared = SeniasService()

    /// Llave de UserDefaults del interruptor "Modo Señas".
    static let llaveModo = "senias.modo.activado"

    private let manifesto: ManifestoSenias?
    private let carpetaClips: URL?

    // MARK: - Init

    private init() {
        let bundle = Bundle.main

        // Manifiesto: senias/manifest.json
        if let url = bundle.url(forResource: "manifest", withExtension: "json", subdirectory: "senias"),
           let data = try? Data(contentsOf: url) {
            manifesto = try? JSONDecoder().decode(ManifestoSenias.self, from: data)
        } else {
            manifesto = nil
        }

        // Carpeta de clips: senias/clips/
        carpetaClips = bundle.url(forResource: "clips", withExtension: nil, subdirectory: "senias")
    }

    // MARK: - Estado del modo

    /// true si el usuario activó el Modo Señas en Perfil.
    var modoActivo: Bool {
        UserDefaults.standard.bool(forKey: SeniasService.llaveModo)
    }

    var manifiestoCargado: Bool { manifesto != nil }

    // MARK: - Resolución

    /// Devuelve qué se puede mostrar para una clave.
    ///
    /// Degrada de forma honesta: si no hay clip, devuelve `.pendiente` con el
    /// motivo. Nunca inventa una seña.
    func estado(para clave: String) -> EstadoSenia {
        guard let manifesto else {
            return .pendiente(motivo: "No se encontró senias/manifest.json en el bundle")
        }
        guard let senia = manifesto.senia(para: clave) else {
            return .pendiente(motivo: "La clave «\(clave)» no está en el manifiesto")
        }
        guard let carpeta = carpetaClips else {
            return .pendiente(motivo: "No se encontró senias/clips/ en el bundle")
        }

        let archivo = carpeta.appendingPathComponent(senia.archivo)
        guard FileManager.default.fileExists(atPath: archivo.path) else {
            return .pendiente(motivo: "Falta el archivo \(senia.archivo)")
        }
        return .clip(archivo, senia: senia)
    }

    /// Texto legible de la clave, en el idioma activo.
    func texto(clave: String) -> String {
        CatalogoSenias.shared.texto(clave: clave) ?? clave
    }

    /// Todas las claves del manifiesto. Útil para depurar y para el checklist
    /// de grabación.
    func clavesEnManifiesto() -> [String] {
        manifesto?.señas.map(\.clave).sorted() ?? []
    }
}

// MARK: - Presentador (controla qué seña se muestra en pantalla)

/// Coordina la aparición del overlay a nivel de RootView.
///
/// El texto señable sólo llama a `mostrar(clave:)`; el overlay vive una única
/// vez en la raíz para que se dibuje por encima de todo.
final class SeniasPresenter: ObservableObject {

    static let shared = SeniasPresenter()

    @Published var claveVisible: String?

    private init() {}

    func mostrar(clave: String) {
        guard SeniasService.shared.modoActivo else { return }
        claveVisible = clave
    }

    func ocultar() {
        claveVisible = nil
    }
}
