import SwiftUI

struct RouteAlternativesSheet: View {
    let vm: MapaViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var consulta = ""

    private var opciones: [TransitItinerary] {
        let palabras = IndiceBusquedaRuta.normalizar(consulta).split(separator: " ")
        guard !palabras.isEmpty else { return vm.alternativasItinerario }
        return vm.alternativasItinerario.filter { plan in
            let texto = IndiceBusquedaRuta.normalizar(
                plan.route.lineaConLetra + " " + plan.route.empresa + " "
                + (plan.transfer.map { $0.route.lineaConLetra + " " + $0.route.empresa } ?? ""))
            return palabras.allSatisfy { texto.contains($0) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(L.t("Compara el tiempo estimado y cuánto necesitas caminar. Las distancias aproximadas se comprueban al elegir una ruta.",
                             "Compare estimated time and how far you need to walk. Approximate distances are checked when you choose a route."))
                        .font(.subheadline)
                        .foregroundStyle(Color.onSurfaceVariant)
                }
                if let mensaje = vm.mensajeAlternativa {
                    Section {
                        Label(L.aviso(mensaje), systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Color.onSurfaceVariant)
                    }
                }
                let directas = opciones.filter { $0.transfer == nil }
                let transbordos = opciones.filter { $0.transfer != nil }
                if !directas.isEmpty {
                    Section(L.t("Sin transbordos", "No transfers")) {
                        ForEach(directas, id: \.optionID) { plan in fila(plan) }
                    }
                }
                if !transbordos.isEmpty {
                    Section(L.t("1 transbordo", "1 transfer")) {
                        ForEach(transbordos, id: \.optionID) { plan in fila(plan) }
                    }
                }
                if opciones.isEmpty {
                    Text(L.t("No hay rutas que coincidan con tu búsqueda.", "No routes match your search."))
                        .foregroundStyle(Color.onSurfaceVariant)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .tint(Color.appPrimary)
            .navigationTitle(L.t("Ver otras rutas", "See other routes"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $consulta, prompt: L.t("Letra, línea o empresa", "Letter, line or company"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("Cerrar", "Close")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onChange(of: vm.itinerarioFocusTick) { _, _ in dismiss() }
        .onChange(of: vm.alternativasItinerario.isEmpty) { _, vacias in
            if vacias { dismiss() }
        }
        .onDisappear { vm.cancelarSeleccionAlternativa() }
    }

    private func fila(_ plan: TransitItinerary) -> some View {
        let seleccionada = vm.itinerario?.optionID == plan.optionID
        let comprobando = vm.seleccionandoAlternativa == plan.optionID
        return Button {
            if seleccionada { dismiss() } else { vm.seleccionarAlternativa(plan) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bus.fill")
                    .font(.title3)
                    .foregroundStyle(plan.route.color)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    let categories = vm.categorias(de: plan)
                    if !categories.isEmpty { RouteCategoryBadges(categories: categories) }
                    Text(plan.route.lineaConLetra)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.onSurface)
                    if let transfer = plan.transfer {
                        Text(L.t("Luego toma ", "Then take ") + transfer.route.lineaConLetra)
                            .font(.subheadline)
                            .foregroundStyle(Color.onSurface)
                    }
                    Text(plan.route.empresa)
                        .font(.caption)
                        .foregroundStyle(Color.onSurfaceVariant)
                    Label(L.f("{0} m para subir · {1} m al destino",
                              "{0} m to board · {1} m to destination",
                              ["\(Int(ceil(plan.walkToBoardMeters)))", "\(Int(ceil(plan.walkToDestinationMeters)))"]),
                          systemImage: "figure.walk")
                        .font(.caption)
                        .foregroundStyle(Color.onSurfaceVariant)
                    if let transfer = plan.transfer {
                        Text(L.f("{0} m a pie en el transbordo", "{0} m walking at the transfer",
                                 ["\(Int(ceil(transfer.walkMeters)))"]))
                            .font(.caption)
                            .foregroundStyle(Color.onSurfaceVariant)
                    }
                    Text("~" + L.f("{0} min", "{0} min", ["\(max(1, Int(ceil(plan.estimatedJourneySeconds / 60))))"]))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.onSurface)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if comprobando {
                    ProgressView()
                        .accessibilityLabel(L.t("Comprobando caminatas…", "Checking walks…"))
                } else if seleccionada {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.appPrimary)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(vm.seleccionandoAlternativa != nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(seleccionada ? .isSelected : [])
        .accessibilityHint(L.t("Muestra este recorrido en el mapa.", "Shows this route on the map."))
    }
}
