//
//  BusquedaLocalDestinos.swift
//  RutaUTP
//
//  Búsqueda de destino sin internet.
//
//  Apple Maps necesita red para autocompletar y buscar direcciones. Sin ella
//  (o con el Modo offline), el Mapa busca en lo que ya está en el iPhone: los
//  paraderos del feed GTFS incluido en la app y los lugares guardados. Elegir
//  un resultado calcula la ruta en micro con el mismo catálogo local.
//

import SwiftUI
import CoreLocation

/// Resultado de la búsqueda local.
struct SugerenciaLocal: Identifiable, Equatable {
    enum Tipo: Equatable { case lugarGuardado, paradero }

    let id: String
    let tipo: Tipo
    let titulo: String
    let detalle: String
    let coordenada: CLLocationCoordinate2D

    var icono: String { tipo == .lugarGuardado ? "bookmark.fill" : "bus" }

    static func == (izquierda: SugerenciaLocal, derecha: SugerenciaLocal) -> Bool {
        izquierda.id == derecha.id && izquierda.titulo == derecha.titulo
            && izquierda.detalle == derecha.detalle
    }
}

/// Índice de paraderos con nombre, construido una vez por catálogo.
@MainActor
final class IndiceLocalDestinos {
    static let shared = IndiceLocalDestinos()

    private struct Paradero {
        let id: String
        let titulo: String
        let normalizado: String
        let lineas: [String]
        let coordenada: CLLocationCoordinate2D
    }

    private var catalogo: GTFSRouteCatalog?
    private var paraderos: [Paradero] = []
    /// Cambia cada vez que se rehace el índice (p. ej. al pasar a Buses UTP).
    private(set) var revision = 0

    /// Paraderos con nombre del catálogo indexado (0 hasta prepararlo).
    var numeroParaderos: Int { paraderos.count }
    var preparado: Bool { catalogo != nil }

    /// Carga el catálogo local (no usa red) y rehace el índice si cambió.
    @discardableResult
    func preparar(_ repositorio: RutasGTFSProviding) async -> Bool {
        guard let nuevo = try? await repositorio.cargarCatalogo(reintentar: false) else {
            return catalogo != nil
        }
        if let catalogo, catalogo.sharesRevision(with: nuevo) { return true }
        var porID: [String: (paradero: ParaderoGTFS, lineas: Set<String>)] = [:]
        for ruta in nuevo.routes {
            for paradero in ruta.paraderos {
                porID[paradero.id, default: (paradero, [])].lineas.insert(ruta.lineaConLetra)
            }
        }
        paraderos = porID.values.compactMap { entrada in
            // Un paradero sin nombre no se puede buscar por texto.
            guard let nombre = GTFSNombreParser.nombreRegistrado(entrada.paradero.nombre) else { return nil }
            return Paradero(id: entrada.paradero.id, titulo: nombre,
                            normalizado: Self.normalizar(nombre),
                            lineas: entrada.lineas.sorted { $0.localizedStandardCompare($1) == .orderedAscending },
                            coordenada: entrada.paradero.coordinate)
        }
        catalogo = nuevo
        revision += 1
        return true
    }

    /// Lugares guardados primero; después paraderos, por coincidencia y cercanía.
    func buscar(_ texto: String, lugares: [LugarGuardado],
                cerca referencia: CLLocationCoordinate2D, limite: Int = 6) -> [SugerenciaLocal] {
        let consulta = Self.normalizar(texto)
        let palabras = consulta.split(separator: " ").map(String.init)
        guard !palabras.isEmpty else { return [] }
        let origen = CLLocation(latitude: referencia.latitude, longitude: referencia.longitude)

        let guardados: [SugerenciaLocal] = lugares.compactMap { lugar -> (SugerenciaLocal, Int)? in
            guard let lat = lugar.lat, let lon = lugar.lon else { return nil }
            let nombre = Self.normalizar(lugar.nombre)
            let completo = nombre + " " + Self.normalizar(lugar.direccion)
            guard palabras.allSatisfy({ completo.contains($0) }) else { return nil }
            let direccion = lugar.direccion.trimmingCharacters(in: .whitespacesAndNewlines)
            let sugerencia = SugerenciaLocal(
                id: "lugar-" + lugar.id.uuidString, tipo: .lugarGuardado, titulo: lugar.nombre,
                detalle: direccion.isEmpty ? L.t("Lugar guardado", "Saved place")
                    : L.f("Lugar guardado · {0}", "Saved place · {0}", [direccion]),
                coordenada: CLLocationCoordinate2D(latitude: lat, longitude: lon))
            return (sugerencia, nombre.hasPrefix(consulta) ? 0 : 1)
        }
        .sorted { $0.1 < $1.1 }
        .prefix(3)
        .map { $0.0 }

        let cercanos = paraderos.compactMap { paradero -> (Paradero, Int, CLLocationDistance)? in
            guard palabras.allSatisfy({ paradero.normalizado.contains($0) }) else { return nil }
            let distancia = origen.distance(from: CLLocation(latitude: paradero.coordenada.latitude,
                                                             longitude: paradero.coordenada.longitude))
            return (paradero, paradero.normalizado.hasPrefix(consulta) ? 0 : 1, distancia)
        }
        .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.2 < $1.2 }
        .prefix(max(0, limite - guardados.count))
        .map { entrada in
            let (paradero, _, distancia) = entrada
            return SugerenciaLocal(id: "paradero-" + paradero.id, tipo: .paradero, titulo: paradero.titulo,
                                   detalle: Self.detalle(lineas: paradero.lineas, distancia: distancia),
                                   coordenada: paradero.coordenada)
        }

        return guardados + cercanos
    }

    private static func detalle(lineas: [String], distancia: CLLocationDistance) -> String {
        let visibles = lineas.prefix(3).joined(separator: ", ")
        let resto = lineas.count > 3 ? " +\(lineas.count - 3)" : ""
        let kilometros = FormatoNumero.decimal(distancia / 1_000)
        return L.f("Paradero · {0}{1} · {2} km", "Stop · {0}{1} · {2} km", [visibles, resto, kilometros])
    }

    static func normalizar(_ texto: String) -> String {
        texto.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))
            .replacingOccurrences(of: ".", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

extension MapaViewModel {
    /// La búsqueda usa datos locales sin red o con el Modo offline.
    var usaBusquedaLocal: Bool { ConectividadService.shared.usarSoloDatosLocales }

    func buscarLocalmente(_ texto: String) {
        busquedaLocalTask?.cancel()
        avisoBusquedaLocal = nil
        guard !texto.isEmpty else {
            sugerenciasLocales = []
            buscandoLocal = false
            return
        }
        let referencia = userRealCoordinate ?? coordenadaInicio
        let repositorio = repositorioGTFS
        let indice = IndiceLocalDestinos.shared
        let revisionPrevia = indice.revision
        // Con el índice listo la búsqueda es inmediata; la primera vez se
        // prepara el catálogo y el panel muestra que está buscando.
        if indice.preparado {
            sugerenciasLocales = indice.buscar(texto, lugares: LugaresStore.cargar(), cerca: referencia)
            buscandoLocal = false
        } else {
            buscandoLocal = true
        }
        busquedaLocalTask = Task { @MainActor [weak self] in
            // El catálogo está en caché: solo rehace el índice si cambió.
            await indice.preparar(repositorio)
            guard !Task.isCancelled, let self else { return }
            if self.buscandoLocal || indice.revision != revisionPrevia {
                self.sugerenciasLocales = indice.buscar(texto, lugares: LugaresStore.cargar(), cerca: referencia)
            }
            self.buscandoLocal = false
        }
    }

    /// Al confirmar el texto sin red: el primer resultado local o un aviso.
    func buscarTextoLocal(_ texto: String) {
        let indice = IndiceLocalDestinos.shared
        let resultados = sugerenciasLocales.isEmpty
            ? indice.buscar(texto, lugares: LugaresStore.cargar(), cerca: userRealCoordinate ?? coordenadaInicio)
            : sugerenciasLocales
        if let primero = resultados.first {
            seleccionarSugerenciaLocal(primero)
            return
        }
        sugerenciasLocales = []
        let aviso = indice.preparado
            ? L.f("Sin conexión: ningún paradero ni lugar guardado coincide con «{0}».",
                  "No connection: no stop or saved place matches “{0}”.", [texto])
            : L.t("Sin conexión: todavía se están preparando los paraderos. Inténtalo de nuevo.",
                  "No connection: stops are still being prepared. Try again.")
        avisoBusquedaLocal = aviso
        AccessibilityNotification.Announcement(aviso).post()
    }

    func seleccionarSugerenciaLocal(_ sugerencia: SugerenciaLocal) {
        busquedaLocalTask?.cancel()
        buscandoLocal = false
        sugerenciasLocales = []
        avisoBusquedaLocal = nil
        seleccionarLugar(titulo: sugerencia.titulo, coordenada: sugerencia.coordenada)
    }
}
