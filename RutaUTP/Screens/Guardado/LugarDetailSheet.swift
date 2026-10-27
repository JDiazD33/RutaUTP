//
//  LugarDetailSheet.swift
//  RutaUTP
//
//  Hoja de detalle de un lugar guardado.
//
//  Muestra el mapa, las acciones para planear la visita y la opción de
//  quitarlo de guardados.
//

import SwiftUI
import MapKit
import CoreLocation

// MARK: - Lugar Detail Sheet
struct LugarDetailSheet: View {
    let lugar: LugarGuardado
    var onEliminar: () -> Bool
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: AppRouter
    @State private var lugarCoord: CLLocationCoordinate2D?
    @State private var buscandoCoord = true
    @State private var intento = 0
    @State private var geocoder = CLGeocoder()
    @State private var navegando = false
    @State private var confirmarEliminar = false
    @State private var errorAlEliminar = false
    @State private var camera: MapCameraPosition = .region(MKCoordinateRegion(
        center: TransporteApp.referenciaInicio,
        span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)))

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Label(lugar.esParadero
                          ? L.t("PARADERO GUARDADO", "SAVED STOP")
                          : L.t("LUGAR GUARDADO", "SAVED PLACE"), systemImage: "bookmark.fill")
                        .font(.caption.weight(.bold)).foregroundStyle(Color.onSurfaceVariant)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.subheadline.bold())
                            .frame(width: 44, height: 44)
                            .background(Color.surfaceContainerLow, in: Circle())
                    }
                    .accessibilityLabel(L.t("Cerrar", "Close"))
                }

                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: lugar.icono)
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(Color.appAccent)
                        .frame(width: 58, height: 58)
                        .background(Color.appPrimary.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(lugar.nombre).font(.title2.bold())
                        Text(lugar.direccion).font(.subheadline)
                            .foregroundStyle(Color.onSurfaceVariant)
                        if lugar.esFrecuente {
                            Label(L.t("Frecuente", "Frequent"), systemImage: "star.fill")
                                .font(.caption.weight(.semibold)).foregroundStyle(Color.appAccent)
                        }
                    }
                }

                Group {
                    if let coord = lugarCoord {
                        Map(position: $camera, interactionModes: []) {
                            Annotation(lugar.nombre, coordinate: coord) {
                                Image(systemName: lugar.icono)
                                    .font(.title3.bold()).foregroundStyle(.onPrimaryFill)
                                    .padding(12).background(Color.primaryFill, in: Circle())
                                    .overlay(Circle().stroke(.white, lineWidth: 3))
                                    .shadow(color: .black.opacity(0.2), radius: 5, y: 3)
                            }
                        }
                        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                        .accessibilityLabel(L.t("Ubicación de ", "Location of ") + lugar.nombre)
                    } else {
                        VStack(spacing: 12) {
                            if buscandoCoord {
                                ProgressView()
                                Text(L.t("Localizando el lugar…", "Locating this place…"))
                            } else {
                                Image(systemName: "mappin.slash.circle").font(.largeTitle)
                                Text(L.t("No pudimos localizar esta dirección.", "We could not locate this address."))
                                Button(L.t("Reintentar", "Try again")) { intento += 1 }
                                    .fontWeight(.bold).foregroundStyle(Color.appAccent)
                            }
                        }
                        .font(.subheadline).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.surfaceContainerLow)
                    }
                }
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 22))

                VStack(alignment: .leading, spacing: 12) {
                    Text(L.t("Planea tu visita", "Plan your visit")).font(.headline)
                    accion(titulo: L.t("Transporte cerca de este lugar", "Transport near this place"),
                           detalle: L.t("Líneas con paradero a menos de 300 m del lugar.", "Routes with a stop within 300 m of this place."),
                           icono: "bus.fill", principal: true) {
                        abrirDestino(transporte: true)
                    }
                    accion(titulo: L.t("Cómo llegar", "How to get there"),
                           detalle: L.t("Traza el camino desde tu ubicación en el mapa.", "Plot the journey from your location on the map."),
                           icono: "arrow.triangle.turn.up.right.diamond.fill", principal: false) {
                        abrirDestino(transporte: false)
                    }
                }
                .disabled(lugarCoord == nil || navegando)
                .opacity(lugarCoord == nil ? 0.5 : 1)

                if lugar.esFijo {
                    Label(L.t("Lugar fijo de RutaUTP", "RutaUTP fixed place"), systemImage: "pin.fill")
                        .font(.caption).foregroundStyle(Color.onSurfaceVariant)
                } else {
                    Button(role: .destructive) { confirmarEliminar = true } label: {
                        Label(L.t("Quitar de mis lugares", "Remove from my places"), systemImage: "trash")
                            .font(.subheadline).frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
            }
            .padding(20)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.onSurface)
        .background(Color.appBackground)
        .presentationDragIndicator(.visible)
        .seguirTemaForzado()
        .task(id: intento) { await resolverCoordenadas() }
        .onDisappear { geocoder.cancelGeocode() }
        .confirmationDialog(L.t("¿Quitar este lugar de guardados?", "Remove this saved place?"),
                            isPresented: $confirmarEliminar, titleVisibility: .visible) {
            Button(L.t("Quitar lugar", "Remove place"), role: .destructive) {
                if onEliminar() {
                    dismiss()
                } else {
                    errorAlEliminar = true
                }
            }
            Button(L.t("Cancelar", "Cancel"), role: .cancel) { }
        }
        .alert(L.t("No se pudo quitar el lugar", "Unable to remove place"), isPresented: $errorAlEliminar) {
            Button(L.t("Aceptar", "OK"), role: .cancel) { }
        } message: {
            Text(L.t("Los datos guardados se conservaron. Revisa tus lugares en Guardado antes de volver a intentarlo.",
                     "Your saved data was preserved. Check your places in Saved before trying again."))
        }
    }

    private func accion(titulo: String, detalle: String, icono: String,
                        principal: Bool, ejecutar: @escaping () -> Void) -> some View {
        Button(action: ejecutar) {
            HStack(spacing: 12) {
                Image(systemName: icono).font(.title3)
                    .frame(width: 42, height: 42)
                    .background(principal ? Color.white.opacity(0.16) : Color.appPrimary.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 5) {
                    Text(titulo).font(.subheadline.bold())
                    Text(detalle).font(.caption).opacity(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.caption.bold())
            }
            .padding(16)
            .foregroundStyle(principal ? Color.onPrimaryFill : Color.onSurface)
            .background(principal ? Color.primaryFill : Color.surfaceContainerLowest,
                        in: RoundedRectangle(cornerRadius: 18))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
    }

    private func abrirDestino(transporte: Bool) {
        guard let coord = lugarCoord, !navegando else { return }
        navegando = true
        let destino = DestinoPendiente(titulo: lugar.nombre, lat: coord.latitude, lon: coord.longitude)
        if transporte {
            router.lugarCercanoPendiente = destino
        } else {
            router.destinoPendiente = destino
        }
        dismiss()
        router.navigate(to: transporte ? .rutas : .mapaPrincipal)
    }

    @MainActor
    private func resolverCoordenadas() async {
        buscandoCoord = true
        defer { buscandoCoord = false }
        if let coord = lugar.coordinate, CLLocationCoordinate2DIsValid(coord) {
            centrar(coord)
            return
        }
        do {
            let resultados = try await geocoder.geocodeAddressString("\(lugar.direccion), Trujillo, Perú")
            guard !Task.isCancelled,
                  let coord = resultados.first?.location?.coordinate,
                  CLLocationCoordinate2DIsValid(coord) else { return }
            centrar(coord)
        } catch {
            // Sin ubicación válida, las acciones permanecen deshabilitadas.
        }
    }

    private func centrar(_ coord: CLLocationCoordinate2D) {
        lugarCoord = coord
        camera = .region(MKCoordinateRegion(center: coord,
            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)))
    }
}
