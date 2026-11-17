//
//  ConectividadService.swift
//  RutaUTP
//
//  Estado real de la red y «Modo offline».
//
//  `NWPathMonitor` informa si hay una ruta a internet. Sin ella, o con el
//  Modo offline activado por el usuario, la app usa solo datos del iPhone:
//  la búsqueda del Mapa ofrece paraderos del feed GTFS y lugares guardados en
//  lugar de Apple Maps, y las caminatas se estiman al instante en vez de
//  esperar el plazo de MKDirections.
//

import Foundation
import Network
import Observation
import SwiftUI

@MainActor
@Observable
final class ConectividadService {
    static let shared = ConectividadService()

    /// Preferencia del usuario. Ausente equivale a `false` (automático).
    static let llaveModoOffline = "conectividad.modo.offline.v1"

    enum Estado: Equatable {
        /// El monitor aún no informó; se trata como conectado.
        case comprobando
        case conectado
        case sinConexion
    }

    enum Interfaz: Equatable {
        case wifi, datosMoviles, cable, otra
    }

    private(set) var estado: Estado = .comprobando
    private(set) var interfaz: Interfaz?
    /// Datos móviles o Modo de datos reducidos.
    private(set) var datosLimitados = false

    /// Activado por el usuario: usar solo datos locales aunque haya red.
    var modoOfflineManual: Bool {
        didSet {
            guard modoOfflineManual != oldValue else { return }
            defaults.set(modoOfflineManual, forKey: Self.llaveModoOffline)
            Self.indicador.escribir(usarSoloDatosLocales)
            anunciar(modoOfflineManual
                     ? L.t("Modo offline activado. Se usan los datos del iPhone.",
                           "Offline mode on. Using data on this iPhone.")
                     : L.t("Modo offline desactivado.", "Offline mode off."))
        }
    }

    /// Lo que deciden las pantallas: sin red o con el modo manual.
    var usarSoloDatosLocales: Bool { modoOfflineManual || estado == .sinConexion }

    /// Para código fuera del actor principal (p. ej. el cálculo de caminatas).
    nonisolated static var soloDatosLocalesAhora: Bool { indicador.leer() }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let monitor = NWPathMonitor()
    private nonisolated static let indicador = IndicadorConectividad()

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        modoOfflineManual = PreferenciasApp.boolGuardado(para: Self.llaveModoOffline, defaults: defaults) ?? false
        Self.indicador.escribir(modoOfflineManual)
        monitor.pathUpdateHandler = { [weak self] ruta in
            let satisfecha = ruta.status == .satisfied
            let limitada = ruta.isExpensive || ruta.isConstrained
            let tipo: Interfaz? = ruta.usesInterfaceType(.wifi) ? .wifi
                : ruta.usesInterfaceType(.cellular) ? .datosMoviles
                : ruta.usesInterfaceType(.wiredEthernet) ? .cable
                : satisfecha ? .otra : nil
            Task { @MainActor [weak self] in
                self?.aplicar(satisfecha: satisfecha, limitada: limitada, interfaz: tipo)
            }
        }
        monitor.start(queue: DispatchQueue(label: "rutautp.conectividad", qos: .utility))
    }

    private func aplicar(satisfecha: Bool, limitada: Bool, interfaz nueva: Interfaz?) {
        let anterior = estado
        let siguiente: Estado = satisfecha ? .conectado : .sinConexion
        if estado != siguiente { estado = siguiente }
        if interfaz != nueva { interfaz = nueva }
        if datosLimitados != limitada { datosLimitados = limitada }
        Self.indicador.escribir(usarSoloDatosLocales)
        // El primer informe no es un cambio: solo se anuncian las transiciones.
        guard anterior != .comprobando, anterior != siguiente else { return }
        anunciar(siguiente == .sinConexion
                 ? L.t("Sin conexión. La búsqueda usa paraderos y lugares guardados.",
                       "No connection. Search uses stops and saved places.")
                 : L.t("Conexión recuperada.", "Connection restored."))
    }

    /// VoiceOver anuncia el cambio; sin VoiceOver la notificación no hace nada.
    private func anunciar(_ texto: String) {
        AccessibilityNotification.Announcement(texto).post()
    }
}

/// Copia del estado efectivo legible desde cualquier hilo.
final class IndicadorConectividad: @unchecked Sendable {
    private let candado = NSLock()
    private var valor = false

    func leer() -> Bool {
        candado.lock()
        defer { candado.unlock() }
        return valor
    }

    func escribir(_ nuevo: Bool) {
        candado.lock()
        valor = nuevo
        candado.unlock()
    }
}
