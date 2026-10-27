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
            Button { showDetails = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "bus.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.onPrimaryFill)
                        .frame(width: 36, height: 36)
                        .background(Color.primaryFill, in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L.t("Tu transporte público", "Your public transport"))
                            .font(.caption)
                            .foregroundStyle(Color.onSurfaceVariant)
                        Text(L.t("Línea ", "Line ") + route.lineaConLetra)
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
                Group {
                    if choosingLine {
                        TripSelectionSheet(coordinator: coordinator,
                                           locationService: locationService,
                                           suggestedRouteID: siguienteTramo?.id,
                                           itinerary: itinerary)
                    } else {
                        tripDetails
                    }
                }
                .presentationDetents(choosingLine ? [.large] : [.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var tripDetails: some View {
        NavigationStack {
            Form {
                if let route = coordinator.selectedTripRoute {
                    Section(L.t("Tu transporte público", "Your public transport")) {
                        LabeledContent(L.t("Línea", "Line"), value: route.linea)
                        LabeledContent(L.t("Letra del transporte", "Transport letter"),
                                       value: route.letraTransporte.isEmpty
                                        ? L.t("No especificada", "Not specified")
                                        : route.letraTransporte)
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
                    Section(L.t("Ocupación del micro", "Bus occupancy")) {
                        TripOccupancyControls(service: coordinator.tripOccupancy) {
                            coordinator.updateTripOccupancy($0)
                        }
                    }
                    Section(L.t("Estado del viaje", "Trip status")) {
                        Text(coordinator.confirmedLine != nil
                             ? L.t("Estás ayudando en esta línea.", "You're helping on this line.")
                             : L.t("Esperando detectar movimiento compatible con tu línea.",
                                   "Waiting for movement matching your line."))
                        if let statusMessage {
                            Label {
                                Text(L.aviso(statusMessage))
                            } icon: {
                                Circle().fill(statusColor).frame(width: 8, height: 8)
                            }
                        }
                        if coordinator.isEnabled, !coordinator.isRunning,
                           let fallo = coordinator.errorCargaRutas {
                            Text(fallo.mensajeUsuario)
                            Button(L.t("Reintentar detección", "Retry detection")) {
                                coordinator.setContributionEnabled(true)
                            }
                        }
                    }
                    Section {
                        if let siguienteTramo {
                            Button {
                                choosingLine = true
                            } label: {
                                Label(L.t("Tomar transbordo", "Take the transfer") + " · " + siguienteTramo.lineaConLetra,
                                      systemImage: "arrow.triangle.branch")
                                    .frame(minHeight: 44)
                            }
                        } else if itinerary == nil {
                            Button(L.t("Cambiar de línea", "Change line")) { choosingLine = true }
                                .frame(minHeight: 44)
                        }
                        Button(L.t("Finalizar viaje", "End trip"), role: .destructive) {
                            confirmEndTrip = true
                        }
                    }
                }
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
        }
    }
}

private struct TripOccupancyControls: View {
    @Environment(\.dynamicTypeSize) private var textSize
    @ObservedObject var service: OccupancyService
    let onSelect: (BusOccupancyState) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.t("¿Qué tan lleno va ahora?", "How full is it now?"))
                .font(.caption)
            // No comprimir las tres respuestas en una fila con letra grande.
            (textSize >= .xxxLarge
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(spacing: 8))) {
                ForEach(BusOccupancyState.allCases, id: \.self) { state in
                    Button { onSelect(state) } label: {
                        Text(state.title)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                        .buttonStyle(.bordered)
                        .disabled(service.sending)
                }
            }
            if let result = service.result {
                Text(result).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Conserva las líneas y paraderos del itinerario elegido para confirmar la subida.
