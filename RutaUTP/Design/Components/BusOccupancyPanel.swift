import SwiftUI
import CoreLocation

/// La ficha pública muestra corroboraciones; los votos se envían desde el viaje.
struct BusOccupancyPanel: View {
    let vehicleID: String?
    @StateObject private var service = OccupancyService()

    private var reading: OccupancyReading? {
        service.buses.first { $0.vehicleId == vehicleID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(L.t("Ocupación", "Occupancy"), systemImage: "person.2.fill")
                Spacer()
                Text(reading?.state.title ?? (service.ready
                    ? L.t("Sin confirmar", "Unconfirmed")
                    : L.t("Sin datos recientes", "No recent data")))
                    .fontWeight(.semibold)
            }
            if let reading {
                Text(L.t("\(reading.confirmations) personas coinciden", "\(reading.confirmations) people agree"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(vehicleID == nil
                 ? L.t("Disponible para vehículos reales.", "Available for real vehicles.")
                 : L.t("Para indicar cómo va tu micro, usa «Estoy en un micro» en el mapa.",
                       "To report your bus occupancy, use ‘I'm on a bus’ on the map."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 12))
        .onAppear { if vehicleID != nil { service.start() } }
        .onDisappear { service.stop() }
    }
}

struct TripContributionPanel: View {
    @ObservedObject var coordinator: PassiveTrackingCoordinator
    @State private var showTrip = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let route = coordinator.selectedTripRoute {
                HStack {
                    Label(L.t("Tu micro: línea ", "Your bus: line ") + route.linea, systemImage: "bus.fill")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button(L.t("Ya bajé", "I've got off")) { coordinator.endTrip() }
                        .buttonStyle(.bordered)
                }
                Text(coordinator.confirmedLine != nil
                     ? L.t("Estás ayudando en esta línea. Mantén la app abierta.",
                           "You're helping on this line. Keep the app open.")
                     : L.t("Esperando detectar movimiento compatible con tu línea.",
                           "Waiting for movement matching your line."))
                    .font(.caption).foregroundStyle(.secondary)
                if let place = coordinator.boardingPlace {
                    Label(L.t("Subiste en: ", "Boarded at: ") + place, systemImage: "mappin")
                        .font(.caption).lineLimit(2)
                }
                TripOccupancyControls(service: coordinator.tripOccupancy) { coordinator.updateTripOccupancy($0) }
                Button(L.t("Cambiar de línea", "Change line")) { showTrip = true }
                    .font(.caption)
            } else {
                Button { showTrip = true } label: {
                    Label(L.t("Estoy en un micro", "I'm on a bus"), systemImage: "bus.fill")
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .sheet(isPresented: $showTrip) { TripSelectionSheet(coordinator: coordinator) }
    }
}

private struct TripOccupancyControls: View {
    @ObservedObject var service: OccupancyService
    let onSelect: (BusOccupancyState) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.t("¿Qué tan lleno va ahora?", "How full is it now?"))
                .font(.caption)
            HStack {
                ForEach(BusOccupancyState.allCases, id: \.self) { state in
                    Button(state.title) { onSelect(state) }
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

private struct TripSelectionSheet: View {
    @ObservedObject var coordinator: PassiveTrackingCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var routes: [RutaGTFS] = []
    @State private var selected: RutaGTFS?
    @State private var search = ""
    @State private var occupancy = ""
    @State private var boardingPlace = ""
    @State private var loading = true

    private var filtered: [RutaGTFS] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return routes.filter {
            query.isEmpty || "\($0.linea) \($0.empresa) \($0.variante)"
                .localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let route = selected {
                    Form {
                        Section(L.t("Tu micro", "Your bus")) {
                            Text(L.t("Línea ", "Line ") + route.linea).font(.headline)
                            Text(route.empresa + " · " + route.variante).font(.subheadline)
                            Button(L.t("Elegir otra línea", "Choose another line")) { selected = nil }
                        }
                        Section {
                            TextField(L.t("Calle, cruce o referencia", "Street, intersection or landmark"),
                                      text: $boardingPlace, axis: .vertical)
                                .lineLimit(1...3)
                                .onChange(of: boardingPlace) { _, value in
                                    boardingPlace = String(value.prefix(120))
                                }
                        } header: {
                            Text(L.t("¿Dónde subiste? (opcional)", "Where did you board? (optional)"))
                        } footer: {
                            Text(L.t("Puedes indicar un paradero de alumnos. Por ahora guardamos esta referencia solo en tu teléfono, para poder aprovecharla más adelante. Puedes dejarla vacía.",
                                     "You can name an informal student stop. For now, this reference stays on your phone for future use. You can leave it blank."))
                        }
                        Section {
                            Picker(L.t("Ocupación", "Occupancy"), selection: $occupancy) {
                                Text(L.t("Prefiero no indicar", "Skip for now")).tag("")
                                ForEach(BusOccupancyState.allCases, id: \.rawValue) { state in
                                    Text(state.title).tag(state.rawValue)
                                }
                            }
                            .pickerStyle(.inline)
                        } header: {
                            Text(L.t("¿Qué tan lleno va? (opcional)", "How full is it? (optional)"))
                        } footer: {
                            Text(L.t("No necesitas indicar dónde subiste. Usaremos la hora y ubicación del teléfono al detectar tu viaje. La ocupación necesita corroboración y vence en 3 minutos.",
                                     "No need to say where you boarded. We'll use your phone's time and location when your trip is detected. Occupancy needs corroboration and expires in 3 minutes."))
                        }
                        Button(L.t("Comenzar a ayudar", "Start helping")) {
                            coordinator.beginTrip(route: DetectionRouteGeometry(route: route),
                                                  occupancy: BusOccupancyState(rawValue: occupancy),
                                                  boardingPlace: boardingPlace)
                            dismiss()
                        }
                        .disabled(!coordinator.isEnabled || !coordinator.isPublisherConfigured)
                    }
                } else {
                    List {
                        if loading {
                            ProgressView(L.t("Cargando líneas…", "Loading lines…"))
                        } else if filtered.isEmpty {
                            Text(L.t("No encontramos esa línea.", "No matching line found."))
                        }
                        Section(coordinator.latestLocation == nil
                                ? L.t("Elige la línea que tomaste", "Choose your line")
                                : L.t("Líneas cercanas primero", "Nearby lines first")) {
                            ForEach(filtered) { route in
                                Button { selected = route } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(L.t("Línea ", "Line ") + route.linea).font(.headline)
                                        Text(route.empresa + " · " + route.variante)
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .searchable(text: $search, prompt: L.t("Línea o empresa", "Line or operator"))
                }
            }
            .navigationTitle(L.t("Estoy en un micro", "I'm on a bus"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("Cancelar", "Cancel")) { dismiss() }
                }
            }
            .task {
                let feed = await GTFSRepository.shared.rutas()
                if let location = coordinator.latestLocation {
                    let distances = Dictionary(uniqueKeysWithValues: feed.map { route in
                        (route.id, RouteCandidateMatcher.closestMatch(for: location,
                            routes: [DetectionRouteGeometry(route: route)])?.distanceToRoute ?? .infinity)
                    })
                    routes = feed.sorted { (distances[$0.id] ?? .infinity) < (distances[$1.id] ?? .infinity) }
                } else {
                    routes = feed.sorted { $0.linea.localizedStandardCompare($1.linea) == .orderedAscending }
                }
                loading = false
            }
        }
    }
}
