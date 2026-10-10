import SwiftUI
import MapKit

struct TrackingMapCanvas: View {
    let vm: RouteTrackingViewModel
    @Binding var cameraPosition: MapCameraPosition
    @Binding var vehiculoSeleccionadoID: String?
    let destinoActual: RouteTrackingViewModel.DestinoDemo

    private var colorRuta: Color {
        vm.rutaGTFS?.color ?? Color.primaryContainer
    }

    // MARK: - Mapa (iOS 17+)

    var body: some View {
        Map(position: $cameraPosition) {
            // Destinos del demo = chips fijos del Mapa.
            ForEach(vm.destinos) { destino in
                Annotation(destino.label, coordinate: destino.coordinate) {
                    if destino.id == CatalogoSedesTrabajo.idChipSede,
                       let sede = TransporteApp.sedeVisible {
                        MarcadorSedeTrabajo(sede: sede)
                    } else {
                        MarcadorDestinoBuscado(titulo: destino.label)
                    }
                }
            }

            // Posición actual (GPS real o simulada por el modo demo) con
            // cono de rumbo estilo navegación.
            if let pos = vm.posicion {
                Annotation(L.t("Mi posición", "My position"), coordinate: pos) {
                    UserNavMarker(heading: vm.rumbo)
                }
            }

            if let plan = vm.itinerary {
                MapPolyline(coordinates: plan.walkToBoard)
                    .stroke(Color.secondary, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [3, 7]))
                MapPolyline(coordinates: plan.busDibujo)
                    .stroke(Color.appSurface, style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: plan.busDibujo)
                    .stroke(colorRuta, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
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
            } else if let stop = vm.nearestStop {
                Annotation(stop.nombre, coordinate: stop.coordinate, anchor: .bottom) {
                    TransitStopMarker(number: "", title: L.t("PARADERO", "STOP"), color: .secondary)
                }
            }
            // Si la sede cambió durante un viaje, conservar su destino anterior.
            if !vm.destinos.contains(where: {
                abs($0.coordinate.latitude - destinoActual.coordinate.latitude) < 1e-9
                    && abs($0.coordinate.longitude - destinoActual.coordinate.longitude) < 1e-9
            }) {
                Annotation(destinoActual.label, coordinate: destinoActual.coordinate) {
                    Image(systemName: "flag.checkered.circle.fill")
                        .font(.system(size: 30)).foregroundStyle(Color.appPrimary)
                        .background(Circle().fill(Color.appSurface))
                }
            }

            // Vehículos en tiempo real vía provider: tap → popup en vivo.
            ForEach(vm.vehiculos) { vehiculo in
                Annotation(L.t("Línea", "Line") + " \(vehiculo.linea)", coordinate: vehiculo.coordinate) {
                    Button {
                        AppHaptics.impact(.light)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            // Toggle: segundo tap sobre el mismo bus cierra.
                            vehiculoSeleccionadoID = (vehiculoSeleccionadoID == vehiculo.id)
                                ? nil : vehiculo.id
                            vm.negocioSeleccionado = nil
                        }
                    } label: {
                        AnimatedBusMarker(linea: vehiculo.linea,
                                          color: colorDeLinea(vehiculo.linea), heading: vehiculo.heading)
                            .scaleEffect(vehiculoSeleccionadoID == vehiculo.id ? 1.15 : 1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: vehiculoSeleccionadoID)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L.t("Micro de la línea ", "Bus on line ") + vehiculo.linea)
                    .accessibilityValue(vm.fuenteVehiculos == .simulated ? L.t("Demostración", "Demo") : L.t("Posición recibida", "Received position"))
                    .accessibilityAddTraits(vehiculoSeleccionadoID == vehiculo.id ? .isSelected : [])
                    .accessibilityHint(L.t("Muestra o cierra los detalles de este micro", "Shows or closes this bus's details"))
                }
            }

            // Catálogo demo espaciado según el área visible, también al explorar la ciudad.
            ForEach(vm.negociosCerca) { negocio in
                Annotation(negocio.nombre, coordinate: negocio.coordinate, anchor: .bottom) {
                    Button {
                        AppHaptics.impact(.light)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            vm.negocioSeleccionado = negocio
                            vehiculoSeleccionadoID = nil
                        }
                    } label: {
                        NegocioBubbleMarker(negocio: negocio, seleccionado: vm.negocioSeleccionado?.id == negocio.id)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(vm.negocioSeleccionado?.id == negocio.id ? .isSelected : [])
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .onMapCameraChange(frequency: .onEnd) { context in
            // El cálculo de si el movimiento «cuenta» vive en el ViewModel.
            vm.actualizarViewport(
                center: context.region.center,
                radius: max(500, min(16000, context.region.span.latitudeDelta * 111_320 * 0.6))
            )
        }
        // Publicar anotaciones fuera del callback de MapKit; agrupar movimientos rápidos.
        .task(id: vm.businessViewportRevision) {
            do { try await Task.sleep(for: .milliseconds(180)) }
            catch { return }
            guard !Task.isCancelled else { return }
            vm.refrescarNegocios(force: true)
        }
        .mapControls {
            MapCompass()
            MapScaleView()
            MapPitchToggle()
        }
        .ignoresSafeArea()
        // SIN .onTapGesture aquí: un gesto de tap sobre el Map entero compite
        // con los taps de las Annotations y las burbujas dejaban de responder.
        // Las cards se cierran con su botón X o tocando otra burbuja.
    }

    /// Color de la línea, tomado del `route_color` del feed GTFS.
    ///
    /// Antes se derivaba de un hash del nombre de la línea, así que la misma
    /// línea aparecía con un color en Rutas y en el Mapa y con otro aquí. El
    /// gris neutro solo salta si la línea no está en el feed, que no debería
    /// ocurrir: los vehículos se generan a partir de rutas del propio feed.
    private func colorDeLinea(_ linea: String) -> Color {
        guard let hex = vm.coloresPorLinea[linea] else { return .secondary }
        return Color.colorRuta(hex: hex)
    }
}
