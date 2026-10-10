import SwiftUI
import CoreLocation

/// Selecciona destinos de la misma fuente que Guardado y Seguridad.
struct DestinosGuardadosSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let onSeleccionar: (LugarGuardado) -> Void
    let onAdministrarParaderos: () -> Void
    @State private var paraderos: [LugarGuardado] = []
    @State private var lugares: [LugarGuardado] = []
    @State private var catalogoParaderos: [ParaderoGTFS] = []
    @State private var datosInvalidos = false
    @State private var cargandoCatalogo = true
    @State private var errorCatalogo: String?
    @State private var revisionCatalogo = 0

    var body: some View {
        NavigationStack {
            List {
                if datosInvalidos {
                    Section {
                        Label(L.t("No pudimos leer tus guardados", "Couldn't read your saved destinations"),
                              systemImage: "exclamationmark.triangle")
                        Text(L.t("Tus datos se conservaron. Reintenta la lectura para recuperarlos.",
                                 "Your data was preserved. Retry reading it to recover your destinations."))
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button(L.t("Reintentar lectura", "Retry reading")) {
                            LugaresStore.invalidarCache()
                            cargarGuardados()
                        }
                    }
                } else {
                    Section {
                        if paraderos.isEmpty {
                            Text(L.t("Aún no tienes paraderos guardados.", "You haven't saved any stops yet."))
                                .foregroundStyle(Color.onSurfaceVariant)
                        }
                        ForEach(paraderos) { lugar in
                            fila(lugar, esParadero: true)
                        }
                        Button(action: onAdministrarParaderos) {
                            Label(L.t("Guardar nuevos paraderos", "Save new stops"), systemImage: "bus.fill")
                                .frame(minHeight: 44)
                        }
                    } header: {
                        Text(L.t("Paraderos guardados", "Saved stops"))
                    } footer: {
                        Text(L.t("Son los mismos que guardas en Seguridad. Elige uno para buscar cómo llegar desde tu ubicación.",
                                 "These are the stops you save in Safety. Choose one to find directions from your location."))
                    }

                    if !lugares.isEmpty {
                        Section(L.t("Lugares guardados", "Saved places")) {
                            ForEach(lugares) { lugar in
                                fila(lugar, esParadero: false)
                            }
                        }
                    }
                    if cargandoCatalogo {
                        Section {
                            ProgressView(L.t("Cargando paraderos…", "Loading stops…"))
                        }
                    } else if let errorCatalogo {
                        Section {
                            Text(errorCatalogo).font(.caption).foregroundStyle(Color.onSurfaceVariant)
                            Button(L.t("Reintentar carga de paraderos", "Retry loading stops")) {
                                revisionCatalogo += 1
                            }
                        }
                    }
                }
            }
            .tint(Color.appPrimary)
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle(L.t("Destinos guardados", "Saved destinations"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("Cerrar", "Close")) { dismiss() }
                        .accessibilityLabel(L.t("Cerrar destinos guardados", "Close saved destinations"))
                }
            }
        }
        .onAppear { cargarGuardados() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { cargarGuardados() }
        }
        .task(id: revisionCatalogo) {
            cargandoCatalogo = true
            errorCatalogo = nil
            defer { cargandoCatalogo = false }
            do {
                let rutas = try await TransporteApp.repositorio.cargarRutas(reintentar: revisionCatalogo > 0)
                guard !Task.isCancelled else { return }
                var vistos = Set<String>()
                catalogoParaderos = rutas.flatMap(\.paraderos).filter { vistos.insert($0.id).inserted }
                cargarGuardados()
            } catch {
                guard !Task.isCancelled else { return }
                errorCatalogo = (error as? FalloCargaGTFS)?.mensajeUsuario
                    ?? L.t("No pudimos cargar el catálogo de paraderos.", "Couldn't load the stop catalog.")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func cargarGuardados() {
        let guardados = LugaresStore.cargar()
        datosInvalidos = LugaresStore.datosLocalesInvalidos
        var nuevosParaderos: [LugarGuardado] = []
        var nuevosLugares: [LugarGuardado] = []
        // Resolver una vez por carga, sin recorrer todo el feed en cada render.
        for lugar in guardados {
            if lugar.esParaderoGuardado(en: catalogoParaderos) {
                nuevosParaderos.append(lugar)
            } else {
                nuevosLugares.append(lugar)
            }
        }
        paraderos = nuevosParaderos
        lugares = nuevosLugares
    }

    private func fila(_ lugar: LugarGuardado, esParadero: Bool) -> some View {
        let ubicacionValida = lugar.coordinate.map(CLLocationCoordinate2DIsValid) == true
        return Button { onSeleccionar(lugar) } label: {
            HStack(spacing: 12) {
                Image(systemName: esParadero ? "bus.fill" : lugar.icono)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.appPrimary)
                    .frame(width: 40, height: 40)
                    .background(Color.appPrimary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(lugar.nombre)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.onSurface)
                    if !lugar.direccion.isEmpty {
                        Text(lugar.direccion).font(.caption).foregroundStyle(Color.onSurfaceVariant)
                    }
                    if !ubicacionValida {
                        Text(L.t("Añade su ubicación en Guardado", "Add its location in Saved"))
                            .font(.caption).foregroundStyle(Color.onSurfaceVariant)
                    }
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.onSurfaceVariant)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!ubicacionValida)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((esParadero ? L.t("Paradero: ", "Stop: ") : L.t("Lugar: ", "Place: ")) + lugar.nombre)
        .accessibilityValue(ubicacionValida ? lugar.direccion : L.t("Sin ubicación guardada", "No saved location"))
        .accessibilityHint(L.t("Busca una ruta desde tu ubicación hasta este destino.",
                              "Finds directions from your location to this destination."))
    }
}
