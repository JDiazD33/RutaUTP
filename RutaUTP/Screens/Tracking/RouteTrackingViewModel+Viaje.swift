//
//  RouteTrackingViewModel+Viaje.swift
//  RutaUTP
//
//  Ciclo del viaje de Tracking: búsqueda de destino, inicio, recálculo,
//  instalación del itinerario y registro de la sesión.
//

import Foundation
import CoreLocation
import MapKit

extension RouteTrackingViewModel {

    func buscarDestino(_ text: String) async -> DestinoDemo? {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !buscandoDestino else { return nil }
        buscandoDestino = true
        defer { buscandoDestino = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query + ", Trujillo, Perú"
        request.region = MKCoordinateRegion(center: TransporteApp.referenciaInicio,
                                            span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3))
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let item = response.mapItems.first else {
                errorMessage = L.t("No encontramos ese lugar en Trujillo.", "No matching place found in Trujillo.")
                return nil
            }
            errorMessage = nil
            return DestinoDemo(id: 999, label: item.name ?? query, icon: "mappin.circle.fill",
                               coordinate: item.placemark.coordinate)
        } catch {
            errorMessage = L.t("No pudimos buscar ese destino. Comprueba tu conexión.",
                               "Could not search for that destination. Check your connection.")
            return nil
        }
    }

    // MARK: - Inicio de viaje

    func iniciar(destino: DestinoDemo) async {
        guard !Task.isCancelled, !calculandoRuta else { return }
        guard !TransporteApp.rutasUTPPendientes else {
            errorMessage = TransporteApp.mensajePendiente
            return
        }
        guard authStatus.isAuthorized else {
            errorMessage = L.t("Sin permiso de ubicación. Concédelo en Ajustes.",
                               "No location permission. Grant it in Settings.")
            return
        }
        guard let origen = posicion else {
            errorMessage = L.t("Aún no tenemos tu ubicación. Espera unos segundos.",
                               "We don't have your location yet. Wait a few seconds.")
            return
        }

        // Un inicio reemplaza cualquier recálculo todavía pendiente. Cerrar
        // esa fase aquí evita que su tarea antigua tenga que tocar el viaje nuevo.
        if recalculando { completarRecalculo() }
        let revision = UUID()
        routeRevision = revision
        errorMessage = nil
        destinoSeleccionado = destino
        tripInProgress = false
        installedItinerary = nil
        routePolyline = nil
        progreso = 0
        consecutiveOffRoute = 0
        resumen = nil

        calculandoRuta = true
        defer {
            // cancelTrip puede liberar el indicador y permitir otro inicio
            // antes de que termine esta espera. Solo su dueño puede cerrarlo.
            if revision == routeRevision { calculandoRuta = false }
        }
        await calcularRuta(desde: origen, hacia: destino.coordinate, revision: revision)
        guard revision == routeRevision else { return }
        guard !Task.isCancelled else {
            cancelTrip()
            return
        }
        completarInicioDeViaje(desde: origen, hacia: destino.coordinate)
    }

    /// Recalcular desde la posición actual hacia el destino guardado.
    func recalcular(desde origen: CLLocationCoordinate2D, revisionEsperada: UUID) async {
        guard !Task.isCancelled, revisionEsperada == routeRevision,
              let destino = destinoSeleccionado else { return }
        guard !recalculando, !calculandoRuta,
              Date().timeIntervalSince(lastRecalculation) >= 20 else { return }
        let revision = UUID()
        routeRevision = revision
        lastRecalculation = Date()
        recalculando = true
        tripRecorder?.actualizarEstado(.recalculating)

        defer {
            // También una cancelación de la tarea vigente debe limpiar su
            // indicador y devolver su recorder al estado de seguimiento.
            if revision == routeRevision { completarRecalculo() }
        }
        await calcularRuta(desde: origen, hacia: destino.coordinate, revision: revision)
    }

    /// Solo itinerarios de transporte del feed: nunca sustituye un micro por una ruta de auto.
    private func calcularRuta(desde origen: CLLocationCoordinate2D,
                              hacia destino: CLLocationCoordinate2D,
                              revision: UUID) async {
        guard revision == routeRevision, !Task.isCancelled else { return }
        guard !TransporteApp.rutasUTPPendientes else {
            errorMessage = TransporteApp.mensajePendiente
            return
        }
        let radio = radioParadero
        let catalog: GTFSRouteCatalog
        do {
            // Iniciar/recalcular es una acción concreta; no tratar el fallo
            // de lectura como ausencia de paraderos dentro del radio.
            catalog = try await repositorioGTFS.cargarCatalogo(reintentar: true)
            guard revision == routeRevision, !Task.isCancelled else { return }
        } catch {
            guard revision == routeRevision, !Task.isCancelled else { return }
            catalogoPendientePorFallo = true
            errorMessage = (error as? FalloCargaGTFS)?.mensajeUsuario
                ?? L.t("No se pudieron cargar las rutas. Vuelve a intentarlo.", "Couldn't load routes. Try again.")
            mensajeErrorCatalogo = errorMessage
            return
        }
        if catalogoPendientePorFallo {
            // Recuperar también las dependencias del inicio, conservando el
            // lector de vehículos y su stream registrados en E07.
            aplicarCatalogo(catalog.routes)
            (vehicleProvider as? SimulatedTrackingProvider)?.restaurarCatalogoTrasFallo(catalog.routes)
        }
        let candidates = await TransitPlanner.shared.candidates(in: catalog, origin: origen,
                                                     destination: destino, radius: radio)
        var selected: InstalledTransitItinerary?
        // Limita peticiones a MapKit; cada candidato conserva paraderos y sentido GTFS.
        for candidate in candidates.prefix(4) {
            guard !Task.isCancelled, revision == routeRevision else { return }
            let resolved = await candidate.withWalkingDirections(using: routeService)
            guard !Task.isCancelled, revision == routeRevision else { return }
            let installed = InstalledTransitItinerary(plan: resolved)
            let metrics = installed.metrics
            if metrics.walkToBoardMeters <= radio && metrics.walkToDestinationMeters <= radio && metrics.walkingWithinTransferLimit {
                selected = installed
                break
            }
        }
        guard revision == routeRevision, !Task.isCancelled else { return }
        guard let installed = selected else {
            // Compara contra el MAYOR radio que ofrece el selector, no contra
            // un número fijo: con el tope en 800, un usuario que ya estaba en
            // 800 veía "prueba otro destino" sin ninguna opción que probar.
            let maximo = Preferencia.radio.valoresPermitidos.max() ?? radio
            let sugerencia = radio < maximo
                ? L.t("Prueba un radio mayor u otro destino.", "Try a larger radius or another destination.")
                : L.t("Prueba otro destino.", "Try another destination.")
            errorMessage = L.f("No encontramos una ruta directa ni con un transbordo con paraderos a menos de {0} m de ambos extremos. ", "No direct or one-transfer route has stops within {0} m of both ends. ", ["\(Int(radio))"]) + sugerencia
            return
        }
        // La revisión ya fue comprobada. Instalar no suspende ni abre otro
        // cálculo; el cierre de inicio o recálculo pertenece a su llamador.
        instalarItinerario(installed)
    }

    // MARK: - Aplicación síncrona del itinerario y continuidad del viaje

    /// Publica el plan aceptado, su geometría y los efectos asociados juntos.
    /// Solo calcularRuta decide si una revisión todavía puede instalarse.
    private func instalarItinerario(_ installed: InstalledTransitItinerary) {
        errorMessage = nil
        installedItinerary = installed
        let plan = installed.plan
        let coordinates = plan.coordinates
        rutaGTFS = plan.route
        rutaAproximada = plan.walkingApproximate
        routePolyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        etaTotalSeg = installed.metrics.totalSeconds
        progreso = 0
        instalarShape(coordinates)
        distanciaRestanteM = distanciaTotalM
        (vehicleProvider as? SimulatedTrackingProvider)?.follow(routeID: plan.route.id, near: plan.board.coordinate)
        tripRecorder?.actualizarEstado(.inProgress)
    }

    /// Conserva el cierre del inicio según el estado instalado, incluso cuando
    /// un cálculo vigente retorna sin instalar. iniciar valida la revisión antes
    /// de llamar y conserva la propiedad de calculandoRuta hasta su defer.
    private func completarInicioDeViaje(desde origen: CLLocationCoordinate2D,
                                       hacia destino: CLLocationCoordinate2D) {
        if let plan = itinerary, routePolyline != nil {
            tripRecorder = TripRecorder(sesion: TripSession(linea: plan.lineDescription, empresa: plan.route.empresa,
                origen: TrackingPoint(lat: origen.latitude, lon: origen.longitude),
                destino: TrackingPoint(lat: destino.latitude, lon: destino.longitude),
                estado: .inProgress, startedAt: Date().timeIntervalSince1970))
            tripInProgress = true
            estado = .enRuta
            distanciaRestanteM = distanciaTotalM
        } else {
            tripInProgress = false
            destinoSeleccionado = nil
            estado = .listo
        }
    }

    /// Cierra la fase de recálculo sin sustituir la sesión existente. Se llama
    /// al reemplazarla sin suspender o desde el defer de su revisión vigente.
    private func completarRecalculo() {
        recalculando = false
        consecutiveOffRoute = 0
        if tripRecorder?.estado == .recalculating { tripRecorder?.actualizarEstado(.inProgress) }
    }

    // MARK: - Registro de la sesión (TripSession)

    func registrarPunto(_ coord: CLLocationCoordinate2D, rumbo: Double) {
        guard tripRecorder?.registrarPunto(coord, rumbo: rumbo) == true else { return }
        actualizarConteoPuntos()
    }

    func actualizarConteoPuntos() {
        let count = tripRecorder?.cantidadPuntos ?? 0
        if puntosGPSRegistrados != count { puntosGPSRegistrados = count }
    }

    func finalizarSesion(estado nuevo: TripState) {
        // Resumen con las métricas del viaje para la card de llegada.
        let inicio = tripRecorder?.startedAt ?? Date().timeIntervalSince1970
        let duracion = max(0, Date().timeIntervalSince1970 - inicio)
        let distancia = distanciaTotalM * progreso
        let puntos = tripRecorder?.cantidadPuntos ?? 0
        resumen = ResumenViaje(
            duracionS: duracion,
            distanciaM: distancia,
            puntos: puntos,
            velocidadKmh: duracion > 0 ? (distancia / duracion) * 3.6 : 0
        )
        tripRecorder?.finalizar(estado: nuevo)
    }
}
