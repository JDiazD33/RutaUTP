import SwiftUI
import MapKit

struct TransitMapCanvas: View {
    let vm: MapaViewModel
    let rutaViaje: DetectionRouteGeometry?
    @Binding var cameraPosition: MapCameraPosition
    let marcadorUsuario: CLLocationCoordinate2D?
    let marcadorEsDestinoActual: Bool
    let modoColocarMarcador: Bool
    @FocusState.Binding var campoEnfocado: Bool
    let onCameraChange: (MapCameraUpdateContext) -> Void
    let onPlacementPointChange: (CLLocationCoordinate2D?) -> Void
    let onCameraEnd: () -> Void
    let onClearMarker: () -> Void
    /// La cámara está lo bastante cerca para mostrar los avisos con su icono.
    var mapaAcercado: Bool = false

    /// Caminatas punteadas y recorrido del transporte en línea continua, en
    /// orden de dibujo. En viaje, solo el tramo del pasajero: desde donde sube
    /// hasta donde baja; sin un destino que coincida con la línea, el recorrido
    /// completo.
    private var trazosRuta: [TrazoMapa] {
        let caminata = StrokeStyle(lineWidth: 4, lineCap: .round, dash: [3, 7])
        let contorno = StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)
        let linea = StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
        var trazos: [TrazoMapa] = []
        func agregar(_ id: String, _ coordenadas: [CLLocationCoordinate2D], _ color: Color, _ estilo: StrokeStyle) {
            guard coordenadas.count >= 2 else { return }
            trazos.append(TrazoMapa(id: id, coordenadas: coordenadas, color: color, estilo: estilo))
        }
        if let rutaViaje {
            let tramo = TramoViaje(plan: vm.itinerario, rutaViaje: rutaViaje)
            let bus = tramo?.bus ?? rutaViaje.shape
            agregar("viaje-contorno-\(rutaViaje.id)", bus, .appSurface, contorno)
            agregar("viaje-linea-\(rutaViaje.id)", bus, .appPrimary, linea)
            if let transfer = tramo?.transbordo {
                agregar("viaje-caminata-transbordo", transfer.walk, .secondary, caminata)
                agregar("viaje-contorno-\(transfer.route.id)", transfer.busDibujo, .appSurface, contorno)
                agregar("viaje-linea-\(transfer.route.id)", transfer.busDibujo, transfer.route.color, linea)
            }
            if let tramo {
                agregar("viaje-caminata-final", tramo.caminata, .secondary, caminata)
            }
        } else if let plan = vm.itinerario {
            agregar("plan-caminata-subida", plan.walkToBoard, .secondary, caminata)
            agregar("plan-contorno-\(plan.route.id)", plan.busDibujo, .appSurface, contorno)
            agregar("plan-linea-\(plan.route.id)", plan.busDibujo, plan.route.color, linea)
            if let transfer = plan.transfer {
                agregar("plan-caminata-transbordo", transfer.walk, .secondary, caminata)
                agregar("plan-contorno-\(transfer.route.id)", transfer.busDibujo, .appSurface, contorno)
                agregar("plan-linea-\(transfer.route.id)", transfer.busDibujo, transfer.route.color, linea)
            }
            agregar("plan-caminata-final", plan.walkToDestination, .secondary, caminata)
        }
        return trazos
    }

    /// Por debajo de este alto visible (en grados) los avisos se ven con icono.
    static let zoomDetalleAvisos: Double = 0.03

    /// Con ruta o viaje, los avisos que llegan al mapa ya son los que les
    /// afectan; el que el usuario abre también se dibuja entero.
    private func avisoConLineas(_ cambio: CambioRutaEnMapa) -> Bool {
        rutaViaje != nil || vm.itinerario != nil
            || vm.cambiosSeleccionados?.avisos.contains(where: { $0.id == cambio.id }) == true
    }

    private func avisoConIcono(_ cambio: CambioRutaEnMapa) -> Bool {
        avisoConLineas(cambio) || mapaAcercado
    }

    private var destinoCoincideConReferencia: Bool {
        guard let destino = vm.busquedaResultado else { return false }
        let referencia = vm.utpComoReferencia ? GTFSRepository.coordenadaUTP : vm.sedeTrabajo?.coordinate
        guard let referencia else { return false }
        return abs(destino.coordenada.latitude - referencia.latitude) < 1e-9
            && abs(destino.coordenada.longitude - referencia.longitude) < 1e-9
    }

    var body: some View {
        GeometryReader { geometry in
            let punto = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            MapReader { proxy in
                mapa
                    .overlay {
                        if modoColocarMarcador {
                            PinEnColocacion().position(punto)
                        }
                    }
                    .onMapCameraChange(frequency: .continuous) { context in
                        onCameraChange(context)
                        onPlacementPointChange(proxy.convert(punto, from: .local))
                    }
                    .onMapCameraChange(frequency: .onEnd) { context in
                        onCameraChange(context)
                        onPlacementPointChange(proxy.convert(punto, from: .local))
                        onCameraEnd()
                    }
                    .onChange(of: modoColocarMarcador) { _, colocando in
                        if colocando {
                            onPlacementPointChange(proxy.convert(punto, from: .local))
                            onCameraEnd()
                        }
                    }
                    .onChange(of: geometry.size) { _, _ in
                        onPlacementPointChange(proxy.convert(punto, from: .local))
                        onCameraEnd()
                    }
            }
        }
        .ignoresSafeArea()
    }

    private var mapa: some View {
        Map(position: $cameraPosition) {

            if vm.utpComoReferencia {
                Annotation(L.t("Campus UTP Trujillo", "UTP Trujillo campus"),
                           coordinate: GTFSRepository.coordenadaUTP) {
                    MarcadorCampusUTP(busesUTPActivos: vm.busesUTPActivos)
                }
            } else if let sede = vm.sedeTrabajo {
                Annotation(sede.nombre, coordinate: sede.coordinate, anchor: .bottom) {
                    MarcadorSedeTrabajo(sede: sede)
                }
            }

            // 2. Marcador del Usuario (GPS Real o Peatón)
            if let userCoord = vm.userRealCoordinate {
                Annotation(L.t("Mi Ubicación", "My Location"), coordinate: userCoord) {
                    PulsingUserMarker()
                }
            }

            // Caminatas punteadas y recorrido del transporte en línea continua.
            ForEach(trazosRuta) { trazo in
                MapPolyline(coordinates: trazo.coordenadas)
                    .stroke(trazo.color, style: trazo.estilo)
            }
            if let rutaViaje {
                if let resto = TramoViaje(plan: vm.itinerario, rutaViaje: rutaViaje) {
                    if let transfer = resto.transbordo {
                        Annotation(transfer.board.nombreVisible, coordinate: transfer.board.coordinate, anchor: .bottom) {
                            TransitStopMarker(number: "3", title: L.t("CAMBIA", "CHANGE"), color: transfer.route.color)
                        }
                    }
                    Annotation(L.t("Baja aquí", "Get off here"), coordinate: resto.bajada.coordinate, anchor: .bottom) {
                        TransitStopMarker(number: resto.numeroBajada, title: L.t("BAJA", "EXIT"), color: .appPrimary)
                    }
                }
            } else if let plan = vm.itinerario {
                if let transfer = plan.transfer {
                    Annotation(plan.firstAlight.nombreVisible, coordinate: plan.firstAlight.coordinate, anchor: .bottom) {
                        TransitStopMarker(number: "2", title: L.t("BAJA", "EXIT"), color: .orange)
                    }
                    Annotation(transfer.board.nombreVisible, coordinate: transfer.board.coordinate, anchor: .bottom) {
                        TransitStopMarker(number: "3", title: L.t("CAMBIA", "CHANGE"), color: transfer.route.color)
                    }
                }
                Annotation(L.t("Sube aquí", "Board here"), coordinate: plan.board.coordinate, anchor: .bottom) {
                    TransitStopMarker(number: "1", title: L.t("SUBE", "BOARD"), color: .secondary)
                }
                Annotation(L.t("Baja aquí", "Get off here"), coordinate: plan.alight.coordinate, anchor: .bottom) {
                    TransitStopMarker(number: plan.transfer == nil ? "2" : "4", title: L.t("BAJA", "EXIT"), color: .appPrimary)
                }
            }

            // 3b. Cambios confirmados por la comunidad. El tramo que la línea
            // deja de recorrer se pinta punteado SOBRE su trazo continuo: el
            // contorno claro lo borra y el punteado indica que ya no pasa.
            // Mapa libre: un punto pequeño por aviso. El icono aparece al acercar
            // el mapa; las líneas, al tocarlo o cuando afecta a la ruta o al viaje.
            ForEach(vm.cambiosEnMapa) { cambio in
                if avisoConLineas(cambio), cambio.tramo.count >= 2 {
                    MapPolyline(coordinates: cambio.tramo)
                        .stroke(Color.appSurface, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    MapPolyline(coordinates: cambio.tramo)
                        .stroke(cambio.aviso.motivo.tinta,
                                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round, dash: [2, 9]))
                }
                // Calle nueva: línea continua del mismo color. Punteado es «ya
                // no pasa»; continuo es «ahora pasa por aquí».
                if avisoConLineas(cambio), cambio.calleNueva.count >= 2 {
                    MapPolyline(coordinates: cambio.calleNueva)
                        .stroke(Color.appSurface, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    MapPolyline(coordinates: cambio.calleNueva)
                        .stroke(cambio.aviso.motivo.tinta,
                                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
                Annotation(cambio.aviso.motivo.tituloAviso, coordinate: cambio.aviso.coordenada) {
                    Button {
                        campoEnfocado = false
                        vm.cambiosSeleccionados = SeleccionCambiosRuta(avisos: [cambio.aviso])
                    } label: {
                        if avisoConIcono(cambio) {
                            MarcadorCambioRuta(motivo: cambio.aviso.motivo)
                        } else {
                            PuntoCambioRuta(motivo: cambio.aviso.motivo)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(cambio.aviso.motivo.tituloAviso + ". "
                                        + (cambio.aviso.textoVia ?? cambio.aviso.place))
                    .accessibilityHint(L.t("Muestra los cambios confirmados en esta ruta.",
                                           "Shows the confirmed changes on this route."))
                }
                .annotationTitles(avisoConLineas(cambio) ? .automatic : .hidden)
            }

            // 4. Marcador del Destino Buscado (ej. UPAO, Casa, Mall Plaza)
            if let res = vm.busquedaResultado, !marcadorEsDestinoActual,
               !destinoCoincideConReferencia {
                Annotation(res.titulo, coordinate: res.coordenada) {
                    MarcadorDestinoBuscado(titulo: res.titulo)
                }
            }

            // 4b. Marcador dejado por el usuario. Va POR ENCIMA del
            // marcador pulsante de su posición, que es decorativo: si
            // coinciden, el pin es el que informa.
            if let marcador = marcadorUsuario {
                Annotation(L.t("Mi punto", "My point"),
                           coordinate: marcador,
                           anchor: MarcadorPin.ancla) {
                    MarcadorPin { onClearMarker() }
                        .allowsHitTesting(rutaViaje == nil)
                        .accessibilityHidden(rutaViaje != nil)
                }
            }

            // 5. Marcadores de Buses Animados en Tiempo Real.
            // La preferencia limita los marcadores. El panel conserva su filtro
            // por rutas cercanas al destino, independiente de los marcadores.
            //
            // El marcador lleva el modelo 3D del bus y la etiqueta de la
            // línea encima. El ancla no es el centro de la vista: con la
            // etiqueta arriba, centrarla dejaría el vehículo dibujado por
            // debajo del punto real.
            ForEach(rutaViaje == nil ? vm.busesEnMapa : []) { bus in
                Annotation(L.t("Línea", "Line") + " \(bus.linea)",
                           coordinate: bus.coordinate,
                           anchor: BusMarker3D.ancla) {
                    Button {
                        campoEnfocado = false
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            vm.busSeleccionado = bus
                        }
                    } label: {
                        BusMarker3D(
                            linea: bus.linea,
                            color: bus.color,
                            heading: bus.heading >= 0 ? bus.heading : 0,
                            seleccionado: vm.busSeleccionado?.id == bus.id
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .mapControls {
            MapCompass().mapControlVisibility(.hidden)
            if rutaViaje == nil { MapScaleView() }
        }
        // Las anotaciones gestionan sus toques; la ficha se cierra con su X.
        // Un gesto en el Map padre competía con la selección del micro.
    }
}

/// Una línea del mapa con identidad propia. MapKit reconoce cada `MapPolyline`
/// por su posición en el contenido y, si ahí ya había una línea con las mismas
/// coordenadas, conserva el estilo anterior: al empezar un viaje, la línea del
/// viaje heredaba el contorno blanco de la guía y no se veía el color. Con un
/// id por papel (guía o viaje) y línea, cada cambio crea una línea nueva.
private struct TrazoMapa: Identifiable {
    let id: String
    let coordenadas: [CLLocationCoordinate2D]
    let color: Color
    let estilo: StrokeStyle
}

/// El tramo del pasajero durante el viaje: desde donde sube hasta donde baja,
/// con el transbordo y la caminata final si los hay. `nil` si no hay destino o
/// si la línea del viaje no es la de la ruta calculada.
private struct TramoViaje {
    let bus: [CLLocationCoordinate2D]
    let transbordo: TransitTransfer?
    let caminata: [CLLocationCoordinate2D]
    let bajada: ParaderoGTFS
    let numeroBajada: String

    init?(plan: TransitItinerary?, rutaViaje: DetectionRouteGeometry) {
        guard let plan else { return nil }
        if plan.route.id == rutaViaje.id {
            bus = plan.busDibujo
            transbordo = plan.transfer
        } else if let transfer = plan.transfer, transfer.route.id == rutaViaje.id {
            // Ya hizo el transbordo: solo queda la segunda línea.
            bus = transfer.busDibujo
            transbordo = nil
        } else {
            return nil
        }
        guard bus.count >= 2 else { return nil }
        caminata = plan.walkToDestination
        bajada = plan.alight
        numeroBajada = plan.transfer == nil ? "2" : "4"
    }
}
