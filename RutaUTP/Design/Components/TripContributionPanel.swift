//
//  TripContributionPanel.swift
//  RutaUTP
//
//  Panel de contribución durante un viaje: ocupación y fin del viaje.
//
//  Incluye los controles privados de ocupación que solo usa este panel.
//

import SwiftUI
import CoreLocation
import MapKit

struct TripContributionPanel: View {
    @ObservedObject var coordinator: PassiveTrackingCoordinator
    let locationService: LocationServiceProtocol
    var itinerary: TransitItinerary? = nil
    var statusMessage: String? = nil
    var statusColor: Color = .secondary
    var onEndTrip: () -> Void = {}
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showDetails = false
    @State private var choosingLine = false
    @State private var confirmEndTrip = false
    @State private var confirmarReinicioSubidas = false
    @State private var errorRecuperacionSubidas = false
    @State private var respaldoSubidas: URL?

    private var siguienteTramo: RutaGTFS? {
        guard let itinerary, coordinator.selectedTripRoute?.id == itinerary.route.id else { return nil }
        return itinerary.transfer?.route
    }

    var body: some View {
        if let route = coordinator.selectedTripRoute {
            Button {
                AppHaptics.selection()
                showDetails = true
            } label: {
                HStack(spacing: 10) {
                    distintivoLetra(route.letraTransporte, destacado: false)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L.t("Tu transporte público", "Your public transport"))
                            .font(.caption)
                            .foregroundStyle(Color.onSurfaceVariant)
                        Text(L.t("Línea ", "Line ") + codigoLinea(route))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.onSurface)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.onSurfaceVariant)
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.outlineVariant.opacity(0.3), lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L.t("Tu transporte público. Línea ", "Your public transport. Line ") + route.lineaConLetra)
            .accessibilityHint(L.t("Abre la ocupación y las opciones para cambiar de línea o finalizar el viaje.",
                                  "Opens occupancy and options to change line or end the trip."))
            .sheet(isPresented: $showDetails, onDismiss: { choosingLine = false }) {
                ZStack(alignment: .top) {
                    if choosingLine {
                        TripSelectionSheet(coordinator: coordinator,
                                           locationService: locationService,
                                           suggestedRouteID: siguienteTramo?.id,
                                           itinerary: itinerary)
                            .transition(.opacity)
                    } else {
                        tripDetails
                            .transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: choosingLine)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .seguirTemaForzado()
            }
        }
    }

    private var tripDetails: some View {
        NavigationStack {
            Form {
                if let route = coordinator.selectedTripRoute {
                    Section {
                        identidadViaje(route)
                        if let place = coordinator.boardingPlace {
                            Label(L.t("Subiste en: ", "Boarded at: ") + place, systemImage: "mappin")
                        }
                        if coordinator.boardingPoint != nil {
                            Label(coordinator.falloAlGuardarSubida
                                  ? L.t("Punto de subida seleccionado", "Boarding point selected")
                                  : L.t("Punto de subida guardado", "Boarding point saved"), systemImage: "mappin.and.ellipse")
                                .foregroundStyle(.secondary)
                        }
                        if coordinator.falloAlGuardarSubida {
                            Label(L.t("No pudimos guardar esta referencia de subida. Tus datos anteriores se conservan; puedes seguir ayudando durante este viaje.",
                                      "We couldn't save this boarding reference. Your previous data has been preserved; you can keep contributing during this trip."),
                                  systemImage: "exclamationmark.triangle")
                                .foregroundStyle(Color.appError)
                            Button(L.t("Reintentar guardado", "Retry saving")) {
                                coordinator.reintentarGuardarSubida()
                            }
                            if BoardingPlaceStore.datosInvalidos() {
                                Button(L.t("Respaldar y reiniciar notas de subida", "Back up and reset boarding notes")) {
                                    confirmarReinicioSubidas = true
                                }
                            }
                        }
                        if let respaldoSubidas {
                            ShareLink(item: respaldoSubidas) {
                                Label(L.t("Compartir respaldo de subidas", "Share boarding backup"),
                                      systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                    Section {
                        TripOccupancyControls(service: coordinator.tripOccupancy) {
                            coordinator.updateTripOccupancy($0)
                        }
                    } header: {
                        tituloSeccion(L.t("Ocupación del micro", "Bus occupancy"))
                    }
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Label {
                                Text(coordinator.confirmedLine != nil
                                     ? L.t("Estás ayudando en esta línea.", "You're helping on this line.")
                                     : L.t("Esperando detectar movimiento compatible con tu línea.",
                                           "Waiting for movement matching your line."))
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Color.onSurface)
                            } icon: {
                                Image(systemName: coordinator.confirmedLine != nil ? "checkmark.circle.fill" : "waveform.path")
                                    .foregroundStyle(statusColor)
                            }
                            if let statusMessage {
                                Text(L.aviso(statusMessage))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        if coordinator.isEnabled, !coordinator.isRunning,
                           let fallo = coordinator.errorCargaRutas {
                            Text(fallo.mensajeUsuario)
                            Button(L.t("Reintentar detección", "Retry detection")) {
                                coordinator.setContributionEnabled(true)
                            }
                        }
                    } header: {
                        tituloSeccion(L.t("Estado del viaje", "Trip status"))
                    }
                    if siguienteTramo != nil || itinerary == nil {
                        Section {
                            if let siguienteTramo {
                                Button {
                                    cambiarDeLinea()
                                } label: {
                                    Label(L.t("Tomar transbordo", "Take the transfer") + " · " + siguienteTramo.lineaConLetra,
                                          systemImage: "arrow.triangle.branch")
                                        .frame(minHeight: 44)
                                }
                            } else {
                                Button(L.t("Cambiar de línea", "Change line"), action: cambiarDeLinea)
                                    .frame(minHeight: 44)
                            }
                        }
                    }
                }
            }
            .listSectionSpacing(20)
            .scrollContentBackground(.hidden)
            .background(Color.appBackground.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if coordinator.selectedTripRoute != nil { botonFinalizar }
            }
            .navigationTitle(L.t("Tu viaje", "Your trip"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("Listo", "Done")) { showDetails = false }
                }
            }
            .alert(L.t("¿Empezar un nuevo historial de subidas?", "Start a new boarding history?"),
                   isPresented: $confirmarReinicioSubidas) {
                Button(L.t("Respaldar y reiniciar", "Back up and reset"), role: .destructive) {
                    do {
                        if let archivo = try BoardingPlaceStore.respaldarYReiniciar() { respaldoSubidas = archivo }
                        coordinator.reintentarGuardarSubida()
                    } catch { errorRecuperacionSubidas = true }
                }
                Button(L.t("Cancelar", "Cancel"), role: .cancel) {}
            } message: {
                Text(L.t("Se guardará una copia del historial original en tus documentos y se reintentará guardar la subida de este viaje.",
                         "A copy of the original history will be saved in your documents and saving this trip's boarding reference will be retried."))
            }
            .alert(L.t("No se pudo reiniciar", "Couldn't reset"), isPresented: $errorRecuperacionSubidas) {
                Button(L.t("Aceptar", "OK"), role: .cancel) {}
            } message: {
                Text(L.t("No se reiniciaron los datos. Reintenta la lectura y comprueba el espacio disponible.",
                         "The data was not reset. Retry reading and check available storage."))
            }
            .confirmationDialog(L.t("¿Finalizar este viaje?", "End this trip?"),
                                isPresented: $confirmEndTrip, titleVisibility: .visible) {
                Button(L.t("Finalizar viaje", "End trip"), role: .destructive) {
                    coordinator.endTrip()
                    showDetails = false
                    onEndTrip()
                }
                Button(L.t("Cancelar", "Cancel"), role: .cancel) { }
            } message: {
                Text(L.t("Se dejará de compartir la ubicación de este micro y volverás al mapa principal.",
                         "Sharing this bus's location will stop and you'll return to the main map."))
            }
            .tint(Color.appAccent)
        }
    }

    private func codigoLinea(_ route: DetectionRouteGeometry) -> String {
        GTFSNombreParser.identificacionTransporte(linea: route.linea, variante: route.variante).codigo
    }

    private func distintivoLetra(_ letra: String, destacado: Bool) -> some View {
        VStack(spacing: 2) {
            if destacado && !letra.isEmpty {
                Text(L.t("LETRA", "LETTER"))
                    .font(.caption2.weight(.semibold))
            }
            if letra.isEmpty {
                Image(systemName: "bus.fill")
                    .font(destacado ? .largeTitle : .title3)
            } else {
                Text(letra)
                    .font(destacado ? .largeTitle.weight(.bold) : .title3.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(Color.onPrimaryFill)
        .padding(destacado ? 12 : 8)
        .frame(minWidth: destacado ? 76 : 44, minHeight: destacado ? 76 : 44)
        .background(Color.primaryFill,
                    in: RoundedRectangle(cornerRadius: destacado ? 20 : 12, style: .continuous))
        .accessibilityHidden(true)
    }

    private var empresaDelViaje: String? {
        guard let itinerary, let id = coordinator.selectedTripRoute?.id else { return nil }
        let previstas = [itinerary.route] + (itinerary.transfer.map { [$0.route] } ?? [])
        return previstas.first { $0.id == id }?.empresa
    }

    private func identidadViaje(_ route: DetectionRouteGeometry) -> some View {
        let layout = textSize >= .xxLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
        return layout {
            distintivoLetra(route.letraTransporte, destacado: true)
            VStack(alignment: .leading, spacing: 6) {
                Text(L.t("Tu transporte público", "Your public transport"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(L.t("Línea ", "Line ") + codigoLinea(route))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.onSurface)
                if let empresaDelViaje, !empresaDelViaje.isEmpty {
                    Text(empresaDelViaje)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.t("Tu transporte público. Línea ", "Your public transport. Line ") + route.lineaConLetra)
        .accessibilityValue(empresaDelViaje ?? "")
        .accessibilityAddTraits(.isHeader)
    }

    private func tituloSeccion(_ titulo: String) -> some View {
        Text(titulo)
            .font(.headline)
            .foregroundStyle(Color.onSurface)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }

    private func cambiarDeLinea() {
        AppHaptics.selection()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { choosingLine = true }
    }

    private var botonFinalizar: some View {
        Button(role: .destructive) { confirmEndTrip = true } label: {
            Label(L.t("Finalizar viaje", "End trip"), systemImage: "stop.circle.fill")
                .font(.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(Color(light: "#FFFFFF", dark: "#3B0007"))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(Color.appError, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.appSurface)
        .overlay(alignment: .top) { Divider() }
    }
}

private struct TripOccupancyControls: View {
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var service: OccupancyService
    let onSelect: (BusOccupancyState) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.t("¿Qué tan lleno va ahora?", "How full is it now?"))
                .font(.subheadline)
            // No comprimir las tres respuestas en una fila con letra grande.
            if textSize >= .xxLarge {
                opcionesVerticales
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        ForEach(BusOccupancyState.allCases, id: \.self) { state in
                            opcion(state, compacta: true)
                        }
                    }
                    opcionesVerticales
                }
            }
            if let result = service.result {
                Text(L.aviso(result))
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(L.t("Puedes actualizarlo durante el viaje. El reporte vence en 3 minutos y necesita corroboración.",
                     "You can update it during your trip. The report expires in 3 minutes and needs corroboration."))
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: service.tripSelection)
    }

    private var opcionesVerticales: some View {
        VStack(spacing: 8) {
            ForEach(BusOccupancyState.allCases, id: \.self) { state in
                opcion(state, compacta: false)
            }
        }
    }

    private func opcion(_ state: BusOccupancyState, compacta: Bool) -> some View {
        let elegida = service.tripSelection == state
        return Button {
            AppHaptics.selection()
            // Una corrección sustituye la elección pendiente incluso durante
            // el envío. El servicio mantiene el plazo y el límite de intentos.
            onSelect(state)
        } label: {
            Group {
                if compacta {
                    VStack(spacing: 8) {
                        Image(systemName: state.iconoViaje).font(.title3)
                        Text(state.title).fixedSize(horizontal: true, vertical: false)
                    }
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: state.iconoViaje).font(.title3)
                        Text(state.title)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: elegida ? "checkmark.circle.fill" : "circle")
                            .accessibilityHidden(true)
                    }
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(elegida ? state.tintaViaje : Color(uiColor: .secondaryLabel))
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: compacta ? 82 : 52)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(elegida ? state.tintaViaje.opacity(0.12)
                          : Color(uiColor: .tertiarySystemGroupedBackground))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(elegida ? state.tintaViaje.opacity(0.6)
                                  : Color(uiColor: .separator).opacity(0.3))
            }
            .overlay(alignment: .topTrailing) {
                if compacta && elegida {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(state.tintaViaje)
                        .padding(6)
                        .transition(.opacity.combined(with: .scale))
                        .accessibilityHidden(true)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.title)
        .accessibilityAddTraits(elegida ? .isSelected : [])
    }
}

private extension BusOccupancyState {
    var iconoViaje: String {
        switch self {
        case .empty: return "person"
        case .space: return "person.2"
        case .full: return "person.3"
        }
    }

    var tintaViaje: Color {
        switch self {
        case .empty: return Color(light: "#1F6F45", dark: "#81DCA6")
        case .space: return Color(light: "#854A0E", dark: "#FFC078")
        case .full: return Color(light: "#B42330", dark: "#FF9A9F")
        }
    }
}

/// Conserva las líneas y paraderos del itinerario elegido para confirmar la subida.
