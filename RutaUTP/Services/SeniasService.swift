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

        // Carpeta de clips: senias/clips/<idioma>/ con idioma = "es" | "en".
        // Dentro de cada carpeta el archivo tiene el MISMO nombre para ambos
        // idiomas; el manifest no distingue idiomas.
        carpetaClips = bundle.url(forResource: "clips", withExtension: nil, subdirectory: "senias")
    }

    // MARK: - Estado del modo

    /// true si el usuario activó el Modo Señas en Perfil.
    var modoActivo: Bool {
        UserDefaults.standard.bool(forKey: SeniasService.llaveModo)
    }

    var manifiestoCargado: Bool { manifesto != nil }

    // MARK: - Resolución

    /// Devuelve qué se puede mostrar para una clave, en el idioma activo.
    ///
    /// Cada idioma tiene su propia carpeta (senias/clips/es, senias/clips/en)
    /// con el mismo nombre de archivo dentro. Degrada de forma honesta: si no
    /// hay clip para el idioma activo, devuelve `.pendiente` con el motivo.
    /// Nunca inventa una seña ni recicla la del otro idioma.
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

        let idioma = IdiomaManager.shared.codigo // "es" | "en"
        let carpetaIdioma = carpeta.appendingPathComponent(idioma)
        guard FileManager.default.fileExists(atPath: carpetaIdioma.path) else {
            return .pendiente(motivo: "No se encontró senias/clips/\(idioma)/ en el bundle")
        }
        let archivo = carpetaIdioma.appendingPathComponent(senia.archivo)
        guard FileManager.default.fileExists(atPath: archivo.path) else {
            return .pendiente(motivo: "Falta el archivo \(idioma)/\(senia.archivo)")
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

    @Published var claveVisible: String? {
        didSet {
            // El miniplayer vive en su propia UIWindow (por encima de sheets
            // y covers): la ventana aparece con la seña y se esconde al cerrar.
            SeniasOverlayVentana.shared.actualizar(hayClave: claveVisible != nil)
        }
    }

    private var accionPendiente: (() -> Void)?
    private var espera: DispatchWorkItem?
    private var esperandoPresentacion = false
    private var tarjetaVisible: String?
    private var solicitud = UUID()

    /// Tiempo visible antes de continuar con la acción solicitada.
    static let pausaParaVerSenia: TimeInterval = 3.0

    private init() {}

    func cancelarAccionPendiente() {
        solicitud = UUID()
        espera?.cancel()
        espera = nil
        accionPendiente = nil
        esperandoPresentacion = false
    }

    func mostrar(clave: String) {
        cancelarAccionPendiente()
        guard SeniasService.shared.modoActivo else { return }
        claveVisible = clave
    }

    /// Cerrar permite continuar sin esperar el resto de la presentación.
    func ocultar() {
        let accion = accionPendiente
        cancelarAccionPendiente()
        tarjetaVisible = nil
        claveVisible = nil
        accion?()
    }

    /// El botón entrega explícitamente su clave y acción: no depende del
    /// orden entre un TapGesture y la acción nativa de Button.
    func ejecutarTrasVerSenia(clave: String? = nil, _ accion: @escaping () -> Void) {
        // Un segundo toque al mismo botón no reinicia la espera ni lo duplica.
        if SeniasService.shared.modoActivo, let clave,
           claveVisible == clave, accionPendiente != nil { return }
        cancelarAccionPendiente()
        guard SeniasService.shared.modoActivo, let clave else {
            tarjetaVisible = nil
            claveVisible = nil
            accion()
            return
        }
        accionPendiente = accion
        esperandoPresentacion = true
        claveVisible = clave
        // Si la tarjeta ya estaba montada, su onAppear no se repetirá.
        if tarjetaVisible == clave { tarjetaPresentada(clave: clave) }
    }

    func tarjetaPresentada(clave: String) {
        tarjetaVisible = clave
        guard claveVisible == clave, esperandoPresentacion else { return }
        esperandoPresentacion = false
        let id = solicitud
        let trabajo = DispatchWorkItem { [weak self] in
            guard let self, self.solicitud == id, self.claveVisible == clave else { return }
            self.ocultar()
        }
        espera = trabajo
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pausaParaVerSenia, execute: trabajo)
    }
}
