// NavegacionRutaViewModel.swift
// Estado de la navegación sobre el recorrido de una línea: avance, paradero
// de bajada elegido y avisos de llegada.

import Foundation
import Combine
import CoreLocation

// MARK: - ViewModel
@MainActor
final class NavegacionRutaViewModel: ObservableObject {

    enum Estado: Equatable {
        case esperandoGPS
        case sinRecorrido
        case sinPermiso
        case enRuta
        case fueraDeRuta(metros: Double)
        case cercaDestino
        /// El avance superó el paradero elegido sin detenerse cerca de él.
        case destinoPasado
        case finalizado
    }

    /// Paradero situado sobre el recorrido, en orden de viaje.
    struct ParadaEnRuta: Identifiable, Equatable {
        /// Posición en el orden de viaje. Un recorrido circular repite
        /// paraderos, así que el `id` del feed no basta para distinguirlos.
        let id: Int
        let paradero: ParaderoGTFS
        /// Avance 0...1 del recorrido en el que se encuentra.
        let fraccion: Double
    }

    // Publicados para la UI
    @Published private(set) var estado: Estado = .esperandoGPS
    @Published private(set) var progreso: Double = 0
    @Published private(set) var distanciaRestanteM: Double = 0
    @Published private(set) var paraderoSiguiente: ParaderoGTFS?
    @Published private(set) var paraderosRestantes: Int = 0
    @Published private(set) var posicion: CLLocationCoordinate2D?
    @Published private(set) var heading: Double = 0
    @Published private(set) var paraderoCercano: ParaderoGTFS?
    @Published private(set) var distanciaParaderoM: Double?
    @Published private(set) var haEntradoEnRuta = false
    /// Paraderos sobre el recorrido, listos para elegir dónde bajar.
    @Published private(set) var paradas: [ParadaEnRuta] = []
    /// Paradero donde la persona quiere bajar. `nil`: el final de la línea.
    @Published private(set) var destino: ParadaEnRuta?
    @Published var modoDemo: Bool = false {
        didSet {
            guard modoDemo != oldValue else { return }
            reiniciarProgreso()
            if modoDemo { iniciarDemo() } else { detenerDemo(); iniciar() }
        }
    }

    let ruta: RutaOpcion
    let shape: [CLLocationCoordinate2D]          // decimada para matching
    let distanciaTotalM: Double

    private let locationService: LocationServiceProtocol
    private var locationTask: Task<Void, Never>?
    private var demoTask: Task<Void, Never>?
    private var actividadVisual = true
    private var demoProgreso: Double = 0
    /// Avance en el que la persona entró al recorrido: desde ahí se mide su viaje.
    private var fraccionSubida: Double?
    private var distanciasAcumuladas: [Double] = []

    init(ruta: RutaOpcion, locationService: LocationServiceProtocol) {
        self.ruta = ruta
        self.locationService = locationService
        let decimada = PolylineMatching.decimate(ruta.shape, maxPoints: 240)
        self.shape = decimada.count >= 2 ? decimada : ruta.shape
        self.distanciaTotalM = PolylineMatching.totalLengthMeters(self.shape)

        // Solo la longitud acumulada: es lineal sobre el trazado decimado y no
        // cuesta nada. La proyección de los paraderos se aplaza a `iniciar()`.
        distanciasAcumuladas = Self.longitudesAcumuladas(shape)
        self.distanciaRestanteM = distanciaTotalM
    }

    /// Hay un viaje en marcha que se perdería al cerrar la pantalla.
    var viajeEnCurso: Bool { haEntradoEnRuta && estado != .finalizado }

    /// Longitud acumulada (m) de cada punto del trazado respecto al inicio.
    private static func longitudesAcumuladas(_ puntos: [CLLocationCoordinate2D]) -> [Double] {
        guard !puntos.isEmpty else { return [] }
        var acumuladas: [Double] = [0]
        acumuladas.reserveCapacity(puntos.count)
        for i in 1..<puntos.count {
            acumuladas.append(
                acumuladas[i - 1] + PolylineMatching.distanceMeters(puntos[i - 1], puntos[i])
            )
        }
        return acumuladas
    }

    /// Proyecta cada paradero sobre el trazado (fracción 0...1).
    ///
    /// Se ejecuta FUERA del hilo principal. Antes se hacía en el `init`, dentro
    /// del `StateObject`: para la C-01 son ~59 000 proyecciones sobre el
    /// trazado, y bloqueaban la aparición de la pantalla sin que hubiera nada
    /// dibujado todavía que lo explicara.
    private func prepararParaderos() async {
        guard paradas.isEmpty, shape.count >= 2 else { return }
        let trazado = shape
        let paraderos = ruta.paraderos

        let calculadas = await Task.detached(priority: .userInitiated) {
            paraderos.compactMap { paradero -> (paradero: ParaderoGTFS, fraccion: Double)? in
                guard let m = PolylineMatching.match(point: paradero.coordinate,
                                                     on: trazado, thresholdMeters: 80) else { return nil }
                return (paradero, m.progressFraction)
            }
            .sorted { $0.fraccion < $1.fraccion }
        }.value

        guard !Task.isCancelled else { return }
        paradas = calculadas.enumerated().map {
            ParadaEnRuta(id: $0.offset, paradero: $0.element.paradero, fraccion: $0.element.fraccion)
        }
        actualizarParaderos()
    }

    // MARK: - Paradero de bajada

    /// Avance del recorrido en el que termina el viaje de la persona.
    private var fraccionDestino: Double { destino?.fraccion ?? 1 }

    /// Nombre del paradero donde termina el viaje.
    var nombreDestino: String { destino?.paradero.nombreVisible ?? ruta.paradaFinVisible }

    /// Punto del mapa donde termina el viaje.
    var coordenadaDestino: CLLocationCoordinate2D? {
        guard shape.count >= 2 else { return nil }
        return destino == nil ? shape.last : coordenadaEnFraccion(fraccionDestino)
    }

    /// Un paradero que ya quedó atrás no se puede elegir para bajar.
    func yaPaso(_ parada: ParadaEnRuta) -> Bool {
        haEntradoEnRuta && parada.fraccion <= progreso + 0.001
    }

    /// Cambia el paradero de bajada. `nil` vuelve al final de la línea.
    func elegirDestino(_ parada: ParadaEnRuta?) {
        if let parada, yaPaso(parada) { return }
        destino = parada
        actualizarRestante()
        actualizarParaderos()
        guard estado != .sinRecorrido, estado != .sinPermiso, estado != .esperandoGPS else { return }
        // Una llegada o un aviso anteriores ya no corresponden al nuevo destino.
        if case .fueraDeRuta = estado { return }
        estado = distanciaRestanteM < 180 ? .cercaDestino : .enRuta
        if modoDemo { reanudarDemo() }
    }

    private func actualizarRestante() {
        distanciaRestanteM = max(0, distanciaTotalM * (fraccionDestino - progreso))
    }

    private func actualizarParaderos() {
        let pendientes = paradas.filter {
            $0.fraccion > progreso + 0.001 && $0.fraccion <= fraccionDestino + 0.0005
        }
        paraderosRestantes = pendientes.count
        paraderoSiguiente = pendientes.first?.paradero ?? destino?.paradero ?? paradas.last?.paradero
    }

    /// Avance 0...1 del viaje de la persona, desde donde subió hasta donde baja.
    var progresoViaje: Double {
        guard haEntradoEnRuta else { return 0 }
        let inicio = min(fraccionSubida ?? 0, progreso)
        let tramo = fraccionDestino - inicio
        guard tramo > 0.0005 else { return estado == .finalizado ? 1 : 0 }
        return max(0, min(1, (progreso - inicio) / tramo))
    }

    // MARK: - Ciclo de vida
    func iniciar() {
        locationTask?.cancel()
        guard shape.count >= 2, distanciaTotalM > 0 else {
            estado = .sinRecorrido
            return
        }
        if modoDemo {
            reanudarDemo()
            return
        }
        estado = .esperandoGPS
        locationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Proyección de paraderos fuera del hilo principal, antes del GPS.
            await self.prepararParaderos()
            guard !Task.isCancelled else { return }
            let status = await self.locationService.requestPermission()
            guard !Task.isCancelled else { return }
            if status.isDenied {
                self.estado = .sinPermiso
                return
            }
            if status.isAuthorized {
                let stream = self.locationService.currentLocation(requirement: .navigation)
                self.locationService.startUpdating()
                for await location in stream {
                    guard !Task.isCancelled else { break }
                    if self.modoDemo { continue }   // el demo toma el control
                    guard UbicacionPuntual.esValida(location, ahora: Date(),
                                                   antiguedadMaxima: 30, precisionMaxima: 65) else { continue }
                    self.procesar(coordenada: location.coordinate, rumbo: location.course)
                }
            }
        }
    }

    func terminar() {
        locationTask?.cancel()
        locationTask = nil
        detenerDemo()
    }

    // MARK: - Procesamiento de fixes
    private func procesar(coordenada: CLLocationCoordinate2D, rumbo: Double, progresoDemo: Double? = nil) {
        guard estado != .finalizado else { return }
        guard let match = PolylineMatching.match(point: coordenada, on: shape,
                                                 thresholdMeters: 60) else { return }

        posicion = coordenada
        heading = rumbo
        if let cercano = ruta.paraderos.min(by: {
            PolylineMatching.distanceMeters(coordenada, $0.coordinate) <
            PolylineMatching.distanceMeters(coordenada, $1.coordinate)
        }) {
            paraderoCercano = cercano
            distanciaParaderoM = PolylineMatching.distanceMeters(coordenada, cercano.coordinate)
        }
        // Una proyección lejana no representa avance ni llegada.
        guard match.isOnRoute else {
            estado = .fueraDeRuta(metros: match.distanceToRoute)
            return
        }
        haEntradoEnRuta = true
        if fraccionSubida == nil { fraccionSubida = progresoDemo ?? match.progressFraction }

        // Anti-jitter: el progreso no retrocede por pequeños saltos de GPS;
        // sí se recalcula si el usuario "re-embarca" mucho más atrás.
        let nuevo = progresoDemo ?? match.progressFraction
        if nuevo >= progreso || (progreso - nuevo) > 0.03 {
            progreso = nuevo
        }

        if let subida = fraccionSubida, progreso < subida { fraccionSubida = progreso }

        actualizarRestante()
        actualizarParaderos()

        let distanciaFinal = coordenadaDestino.map {
            PolylineMatching.distanceMeters(coordenada, $0)
        } ?? .infinity
        if distanciaRestanteM <= 25 && distanciaFinal <= 35 {
            estado = .finalizado
            detenerDemo()
        } else if destino != nil, (progreso - fraccionDestino) * distanciaTotalM > 60 {
            // Con el final de la línea no puede ocurrir: el avance termina ahí.
            estado = .destinoPasado
        } else if distanciaRestanteM < 180 {
            estado = .cercaDestino
        } else {
            estado = .enRuta
        }
    }

    var minutosRestantes: Int {
        estado == .finalizado
            ? 0 : max(1, Int(ceil(Double(ruta.duracionMin) * max(0, fraccionDestino - progreso))))
    }

    var distanciaRestanteTexto: String {
        distanciaRestanteM >= 1000
            ? FormatoNumero.decimal(distanciaRestanteM / 1000) + " km"
            : "\(Int(distanciaRestanteM)) m"
    }

    var distanciaProximoParaderoTexto: String? {
        guard let proximo = paradas.first(where: { $0.fraccion > progreso + 0.001 }) else { return nil }
        let metros = max(0, (proximo.fraccion - progreso) * distanciaTotalM)
        return metros >= 1000 ? FormatoNumero.decimal(metros / 1000) + " km" : "\(Int(metros)) m"
    }

    private func reiniciarProgreso() {
        progreso = 0
        posicion = nil
        haEntradoEnRuta = false
        fraccionSubida = nil
        actualizarRestante()
        actualizarParaderos()
        paraderoCercano = nil
        distanciaParaderoM = nil
        estado = shape.count >= 2 ? .esperandoGPS : .sinRecorrido
    }

    // MARK: - Modo demo
    private func iniciarDemo() {
        detenerDemo()
        guard shape.count >= 2, distanciaTotalM > 0 else { return }
        demoProgreso = 0
        reanudarDemo()
    }

    /// Pausa la demo sin reiniciar el recorrido ni detener el GPS real.
    func actualizarActividadVisual(_ activa: Bool) {
        actividadVisual = activa
        if activa { reanudarDemo() } else { detenerDemo() }
    }

    private func reanudarDemo() {
        guard actividadVisual, modoDemo, estado != .finalizado,
              shape.count >= 2, distanciaTotalM > 0, demoTask == nil else { return }
        // Una sola tarea que duerme entre pasos. Antes era un `Timer` que
        // creaba un `Task` nuevo por tick — doce por segundo — solo para saltar
        // al hilo principal.
        demoTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 80_000_000)
                guard !Task.isCancelled, let self, self.actividadVisual else { return }
                self.demoProgreso = min(1.0, self.demoProgreso + 1.0 / 900.0)  // ~72 s todo el viaje
                let coord = self.coordenadaEnFraccion(self.demoProgreso)
                let siguiente = self.coordenadaEnFraccion(min(1.0, self.demoProgreso + 0.002))
                let rumbo = atan2(siguiente.longitude - coord.longitude,
                                  siguiente.latitude - coord.latitude) * 180 / .pi
                self.procesar(coordenada: coord, rumbo: rumbo, progresoDemo: self.demoProgreso)
            }
        }
    }

    private func detenerDemo() {
        demoTask?.cancel()
        demoTask = nil
    }

    private func coordenadaEnFraccion(_ fraccion: Double) -> CLLocationCoordinate2D {
        guard shape.count >= 2 else { return ruta.shape.first ?? CLLocationCoordinate2D() }
        let objetivo = max(0, min(1, fraccion)) * (distanciasAcumuladas.last ?? 0)
        // Búsqueda binaria del segmento que contiene la distancia objetivo
        var bajo = 0, alto = distanciasAcumuladas.count - 1
        while bajo < alto - 1 {
            let medio = (bajo + alto) / 2
            if distanciasAcumuladas[medio] <= objetivo { bajo = medio } else { alto = medio }
        }
        let longitudSeg = distanciasAcumuladas[alto] - distanciasAcumuladas[bajo]
        let t = longitudSeg > 0 ? (objetivo - distanciasAcumuladas[bajo]) / longitudSeg : 0
        let a = shape[bajo], b = shape[alto]
        return CLLocationCoordinate2D(
            latitude: a.latitude + (b.latitude - a.latitude) * t,
            longitude: a.longitude + (b.longitude - a.longitude) * t
        )
    }
}
