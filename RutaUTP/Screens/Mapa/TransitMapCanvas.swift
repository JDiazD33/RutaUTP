import SwiftUI
import MapKit

struct TransitMapCanvas: View {
    let vm: MapaViewModel
    @Binding var cameraPosition: MapCameraPosition
    let marcadorUsuario: CLLocationCoordinate2D?
    let marcadorEsDestinoActual: Bool
    @FocusState.Binding var campoEnfocado: Bool
    let onCameraChange: (CLLocationCoordinate2D) -> Void
    let onClearMarker: () -> Void

    private var destinoCoincideConReferencia: Bool {
        guard let destino = vm.busquedaResultado else { return false }
        let referencia = vm.utpComoReferencia ? GTFSRepository.coordenadaUTP : vm.sedeTrabajo?.coordinate
        guard let referencia else { return false }
        return abs(destino.coordenada.latitude - referencia.latitude) < 1e-9
            && abs(destino.coordenada.longitude - referencia.longitude) < 1e-9
    }

    var body: some View {
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
            if let plan = vm.itinerario {
                MapPolyline(coordinates: plan.walkToBoard)
                    .stroke(Color.secondary, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [3, 7]))
                MapPolyline(coordinates: plan.busDibujo)
                    .stroke(Color.appSurface, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: plan.busDibujo)
                    .stroke(plan.route.color, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                if let transfer = plan.transfer {
                    MapPolyline(coordinates: transfer.walk)
                        .stroke(Color.secondary, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [3, 7]))
                    MapPolyline(coordinates: transfer.busDibujo)
                        .stroke(Color.appSurface, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    MapPolyline(coordinates: transfer.busDibujo)
                        .stroke(transfer.route.color, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    Annotation(plan.firstAlight.nombre, coordinate: plan.firstAlight.coordinate, anchor: .bottom) {
                        TransitStopMarker(number: "2", title: L.t("BAJA", "EXIT"), color: .orange)
                    }
                    Annotation(transfer.board.nombre, coordinate: transfer.board.coordinate, anchor: .bottom) {
                        TransitStopMarker(number: "3", title: L.t("CAMBIA", "CHANGE"), color: transfer.route.color)
                    }
                }
                MapPolyline(coordinates: plan.walkToDestination)
                    .stroke(Color.secondary, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [3, 7]))
                Annotation(L.t("Sube aquí", "Board here"), coordinate: plan.board.coordinate, anchor: .bottom) {
                    TransitStopMarker(number: "1", title: L.t("SUBE", "BOARD"), color: .secondary)
                }
                Annotation(L.t("Baja aquí", "Get off here"), coordinate: plan.alight.coordinate, anchor: .bottom) {
                    TransitStopMarker(number: plan.transfer == nil ? "2" : "4", title: L.t("BAJA", "EXIT"), color: .appPrimary)
                }
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
                }
            }

            // 5. Marcadores de Buses Animados en Tiempo Real.
            // Tope de 8 en el mapa por rendimiento. El canal real conserva
            // la flota global; el panel filtra por rutas cercanas al destino.
            //
            // El marcador lleva el modelo 3D del bus y la etiqueta de la
            // línea encima. El ancla no es el centro de la vista: con la
            // etiqueta arriba, centrarla dejaría el vehículo dibujado por
            // debajo del punto real.
            ForEach(vm.busesAnimados.prefix(8)) { bus in
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
                            heading: bus.heading,
                            seleccionado: vm.busSeleccionado?.id == bus.id
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .mapControls {
            MapCompass().mapControlVisibility(.hidden)
            MapScaleView()
        }
        .ignoresSafeArea()
        // Cada movimiento reinicia la espera, incluido el deslizamiento
        // por inercia: nunca confirmar el centro anterior mientras se arrastra.
        .onMapCameraChange(frequency: .continuous) { context in
            onCameraChange(context.region.center)
        }
        // Las anotaciones gestionan sus toques; la ficha se cierra con su X.
        // Un gesto en el Map padre competía con la selección del micro.
    }
}
