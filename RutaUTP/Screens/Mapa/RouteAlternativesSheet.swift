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
                let filtradas = opciones
                Section {
                    HStack(alignment: .top, spacing: 16) {
                        Text(L.t("Ver otras rutas", "See other routes"))
                            .font(.largeTitle.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityAddTraits(.isHeader)
                        Image(systemName: "list.bullet")
                            .font(.title2)
                            .foregroundStyle(Color.appAccent)
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityHidden(true)
                    }
                    Text(L.t("Compara el tiempo estimado y cuánto necesitas caminar. Las distancias aproximadas se comprueban al elegir una ruta.",
                             "Compare estimated time and how far you need to walk. Approximate distances are checked when you choose a route."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                if let mensaje = vm.mensajeAlternativa {
                    Section {
                        Label(L.aviso(mensaje), systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                let directas = filtradas.filter { $0.transfer == nil }
                let transbordos = filtradas.filter { $0.transfer != nil }
                if !directas.isEmpty {
                    Section {
                        ForEach(directas, id: \.optionID) { plan in fila(plan) }
                    } header: {
                        Text(L.t("Sin transbordos", "No transfers"))
                            .font(.headline).textCase(nil)
                    }
                }
                if !transbordos.isEmpty {
                    Section {
                        ForEach(transbordos, id: \.optionID) { plan in fila(plan) }
                    } header: {
                        Text(L.t("1 transbordo", "1 transfer"))
                            .font(.headline).textCase(nil)
                    }
                }
                if filtradas.isEmpty {
                    Text(L.t("No hay rutas que coincidan con tu búsqueda.", "No routes match your search."))
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .tint(Color.appAccent)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $consulta, prompt: L.t("Letra, línea o empresa", "Letter, line or company"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("Cerrar", "Close")) { dismiss() }
                        .frame(minHeight: 44)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .seguirTemaForzado()
        .onChange(of: vm.itinerarioFocusTick) { _, _ in dismiss() }
        .onChange(of: vm.alternativasItinerario.isEmpty) { _, vacias in
            if vacias { dismiss() }
        }
        .onDisappear { vm.cancelarSeleccionAlternativa() }
    }

    private func fila(_ plan: TransitItinerary) -> some View {
        let metrics = ItineraryMetrics(plan: plan)
        let seleccionada = vm.itinerario?.optionID == plan.optionID
        let comprobando = vm.seleccionandoAlternativa == plan.optionID
        return Button {
            if seleccionada { dismiss() } else { vm.seleccionarAlternativa(plan) }
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        let categories = vm.categorias(de: plan)
                        if !categories.isEmpty { RouteCategoryBadges(categories: categories) }
                        Text("~" + L.f("{0} min", "{0} min",
                                      ["\(max(1, Int(ceil((metrics.totalSeconds + plan.boardingWaitSeconds) / 60))))"]))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.onSurface)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if comprobando {
                        ProgressView()
                            .accessibilityLabel(L.t("Comprobando caminatas…", "Checking walks…"))
                    } else if seleccionada {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.appAccent)
                            .accessibilityHidden(true)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    RouteLineIdentity(route: plan.route, showsOperator: true)
                    if let transfer = plan.transfer {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "arrow.down")
                                .font(.footnote)
                                .frame(width: 14)
                                .accessibilityHidden(true)
                            Text(L.f("{0} m a pie en el transbordo", "{0} m walking at the transfer",
                                     ["\(Int(ceil(metrics.transferWalkMeters)))"]))
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(.secondary)
                        RouteLineIdentity(route: transfer.route, showsOperator: true)
                    }
                }
                Label(L.f("{0} m para subir · {1} m al destino",
                          "{0} m to board · {1} m to destination",
                          ["\(Int(ceil(metrics.walkToBoardMeters)))",
                           "\(Int(ceil(metrics.walkToDestinationMeters)))"]),
                      systemImage: "figure.walk")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(vm.seleccionandoAlternativa != nil)
        .listRowBackground(seleccionada ? Color.appAccent.opacity(0.08)
                           : Color(uiColor: .secondarySystemGroupedBackground))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(seleccionada ? .isSelected : [])
        .accessibilityHint(L.t("Muestra este recorrido en el mapa.", "Shows this route on the map."))
    }
}
