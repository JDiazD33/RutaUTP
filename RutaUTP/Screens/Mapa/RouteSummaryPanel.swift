import SwiftUI
import MapKit

struct RouteSummaryPanel: View {
    let vm: MapaViewModel
    let maximumPanelHeight: CGFloat
    @EnvironmentObject private var trackingCoordinator: PassiveTrackingCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize
    let onConfirmBoarding: () -> Void
    let onShowAlternatives: () -> Void
    let onDetailsPresentationChange: (Bool) -> Void
    @State private var visibleOptionID: [String] = []
    @State private var showDetails = false
    @State private var boardingAfterDetails: [String]?
    @State private var contentHeight: CGFloat?

    private var pages: [TransitItinerary] { vm.opcionesResumen }

    private var pageIndex: Int { pages.firstIndex { $0.optionID == visibleOptionID } ?? 0 }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 8) {
                header
                if !pages.isEmpty {
                    carousel
                    if trackingCoordinator.selectedTripRoute == nil { pageNavigation }
                } else if let mensaje = vm.mensajeRuta {
                    Text(L.aviso(mensaje)).foregroundStyle(Color.onSurfaceVariant)
                    if !vm.alternativasItinerario.isEmpty {
                        Button(action: onShowAlternatives) {
                            Label(L.t("Ver otras rutas", "See other routes"), systemImage: "list.bullet")
                                .frame(minHeight: 44)
                        }
                        .foregroundStyle(Color.appAccent)
                    }
                }
                if let mensaje = vm.mensajeAlternativa {
                    Label(L.aviso(mensaje), systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Color.onSurfaceVariant)
                }
            }
            .padding(14)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: RoutePanelHeightKey.self, value: geometry.size.height)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        // Ajustar la tarjeta a su contenido elimina el hueco bajo los controles.
        // La altura máxima sigue protegiendo el espacio visible del mapa.
        .frame(height: min(maximumPanelHeight, contentHeight ?? 244))
        .onPreferenceChange(RoutePanelHeightKey.self) { height in
            let rounded = ceil(height)
            if rounded > 0, contentHeight != rounded { contentHeight = rounded }
        }
        .font(.footnote)
        .foregroundStyle(Color.onSurface)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.35), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L.t("Guía de la ruta", "Route guide"))
        .sheet(isPresented: $showDetails, onDismiss: finishDetails) { detailsSheet }
        .onChange(of: showDetails) { _, presented in onDetailsPresentationChange(presented) }
        .onAppear { synchronizeSelection() }
        .onChange(of: vm.itinerario?.optionID) { _, _ in synchronizeSelection() }
        .onChange(of: pages.map(\.optionID)) { _, ids in
            if ids.isEmpty {
                boardingAfterDetails = nil
                showDetails = false
            }
            if !ids.contains(visibleOptionID) { synchronizeSelection() }
        }
        .onChange(of: vm.seleccionandoAlternativa) { _, pending in
            if pending == nil { synchronizeSelection() }
        }
        .onChange(of: trackingCoordinator.selectedTripRoute?.id) { _, route in
            if route != nil {
                boardingAfterDetails = nil
                showDetails = false
            }
        }
        .onChange(of: visibleOptionID) { _, ids in
            guard let plan = pages.first(where: { $0.optionID == ids }) else { return }
            vm.seleccionarAlternativa(plan, diferir: true)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(vm.busquedaResultado.map { L.t("Hacia ", "To ") + $0.titulo } ?? "")
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { vm.limpiar() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.t("Quitar ruta", "Clear route"))
        }
    }

    private var carousel: some View {
        TabView(selection: $visibleOptionID) {
            ForEach(pages, id: \.optionID) { plan in
                ScrollView(.vertical) {
                    compactSummary(plan)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 2)
                }
                .scrollBounceBehavior(.basedOnSize)
                .tag(plan.optionID)
                .accessibilityHidden(visibleOptionID != plan.optionID)
                .allowsHitTesting(visibleOptionID == plan.optionID)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: min(136, max(88, maximumPanelHeight - 132)))
    }

    private func compactSummary(_ plan: TransitItinerary) -> some View {
        let current = vm.itinerarioInstalado
        let metrics = (current?.plan.optionID == plan.optionID ? current?.metrics : nil)
            ?? ItineraryMetrics(plan: plan)
        return VStack(alignment: .leading, spacing: 8) {
            RouteCategoryBadges(categories: vm.categorias(de: plan))
            RouteJourneyLines(plan: plan)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("~" + L.f("{0} min", "{0} min",
                               ["\(max(1, Int(ceil((metrics.totalSeconds + plan.boardingWaitSeconds) / 60))))"]))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.onSurface)
                Text(plan.transfer == nil ? L.t("Sin transbordos", "No transfers") : L.t("1 transbordo", "1 transfer"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label(L.f("{0} min a pie para subir · {1} m", "{0} min walk to board · {1} m",
                      ["\(Int(ceil(metrics.walkToBoardMeters / 1.4 / 60)))", "\(Int(ceil(metrics.walkToBoardMeters)))"]),
                  systemImage: "figure.walk")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if vm.seleccionandoAlternativa == plan.optionID {
                Label(L.t("Comprobando caminatas…", "Checking walks…"), systemImage: "ellipsis")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var detailsSheet: some View {
        NavigationStack {
            ScrollView {
                if let plan = pages.first(where: { $0.optionID == visibleOptionID }) {
                    guide(plan)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                }
            }
            .background(Color.appBackground)
            .navigationTitle(L.t("Guía de la ruta", "Route guide"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("Cerrar", "Close")) { showDetails = false }
                }
            }
        }
        .tint(Color.appAccent)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .seguirTemaForzado()
    }

    private func finishDetails() {
        onDetailsPresentationChange(false)
        defer { boardingAfterDetails = nil }
        guard let option = boardingAfterDetails,
              option == vm.itinerario?.optionID, !vm.calculandoItinerario,
              trackingCoordinator.selectedTripRoute == nil else { return }
        onConfirmBoarding()
    }

    private func guide(_ plan: TransitItinerary) -> some View {
        let installed = vm.itinerarioInstalado
        let current = installed?.plan.optionID == plan.optionID
        let metrics = (current ? installed?.metrics : nil) ?? ItineraryMetrics(plan: plan)
        return VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                RouteCategoryBadges(categories: vm.categorias(de: plan))
                Text("~" + L.f("{0} min en total", "{0} min total",
                               ["\(max(1, Int(ceil((metrics.totalSeconds + plan.boardingWaitSeconds) / 60))))"]))
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(plan.transfer == nil ? L.t("Sin transbordos", "No transfers") : L.t("1 transbordo", "1 transfer"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Label(L.f("{0} min a pie para subir · {1} m", "{0} min walk to board · {1} m",
                          ["\(Int(ceil(metrics.walkToBoardMeters / 1.4 / 60)))", "\(Int(ceil(metrics.walkToBoardMeters)))"]),
                      systemImage: "figure.walk")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                guideStep(icon: "figure.walk", title: plan.board.nombreVisible)
                guideDivider
                guideStep(icon: "bus", title: L.t("Toma la línea ", "Take line ") + plan.route.lineaConLetra,
                          detail: plan.route.empresa + " · " + plan.route.precioTexto, color: plan.route.color)
                if let transfer = plan.transfer {
                    guideDivider
                    guideStep(icon: "mappin.and.ellipse", title: L.t("Baja en ", "Get off at ") + plan.firstAlight.nombreVisible)
                    guideDivider
                    guideStep(icon: "figure.walk", title: L.t("Camina ", "Walk ") + "\(Int(ceil(metrics.transferWalkMeters))) m",
                              detail: transfer.board.nombreVisible)
                    guideDivider
                    guideStep(icon: "bus", title: L.t("Luego toma ", "Then take ") + transfer.route.lineaConLetra,
                              detail: transfer.route.empresa + " · " + transfer.route.precioTexto, color: transfer.route.color)
                }
                guideDivider
                guideStep(icon: "mappin.and.ellipse", title: L.t("Baja en ", "Get off at ") + plan.alight.nombreVisible)
                guideDivider
                guideStep(icon: "flag", title: L.f("Luego camina {0} m hasta tu destino.", "Then walk {0} m to your destination.",
                                                  ["\(Int(ceil(metrics.walkToDestinationMeters)))"]))
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            VStack(alignment: .leading, spacing: 10) {
                if plan.transfer != nil {
                    Text(L.t("El tiempo incluye una espera estimada para el segundo micro.",
                             "Time includes an estimated wait for the second bus."))
                }
                if plan.route.headwayMin > 0 {
                    Text(L.f("Incluye ~{0} min de espera del primer micro.", "Includes ~{0} min waiting for the first bus.",
                             ["\(Int(ceil(plan.boardingWaitSeconds / 60)))"]))
                } else {
                    Text(L.t("Espera del primer micro no disponible.", "First bus waiting time unavailable."))
                }
                if current {
                    if plan.walkingApproximate { AvisoRutaAproximada() }
                } else {
                    Text(L.t("Vista previa con caminatas aproximadas.", "Preview with approximate walks."))
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                if vm.seleccionandoAlternativa == plan.optionID {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(L.t("Comprobando caminatas…", "Checking walks…"))
                    }
                    .frame(minHeight: 56)
                    .accessibilityElement(children: .combine)
                } else if current, !vm.calculandoItinerario, visibleOptionID == plan.optionID,
                          trackingCoordinator.selectedTripRoute == nil {
                    invitacionConfirmarViaje
                }
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: vm.seleccionandoAlternativa)
        }
        .foregroundStyle(Color.onSurface)
    }

    private var guideDivider: some View { Divider().padding(.leading, 56) }

    private func guideStep(icon: String, title: String, detail: String? = nil,
                           color: Color = .appAccent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.body.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .accessibilityElement(children: .combine)
    }

    private var pageNavigation: some View {
        let layout = textSize >= .xxxLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            if pages.count > 1 {
                HStack(spacing: 0) {
                    navigationButton(previous: true)
                    Text(L.f("Ruta {0} de {1}", "Route {0} of {1}", ["\(pageIndex + 1)", "\(pages.count)"]))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAdjustableAction { direction in
                            if direction == .increment { movePage(by: 1) }
                            if direction == .decrement { movePage(by: -1) }
                        }
                    navigationButton(previous: false)
                }
            }
            HStack(spacing: 8) {
                Button { showDetails = true } label: {
                    Text(L.t("Ver detalles", "View details"))
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(Color.appAccent)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 12))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if vm.alternativasItinerario.count > 1 {
                    Button(action: onShowAlternatives) {
                        Image(systemName: "list.bullet")
                            .font(.body)
                            .foregroundStyle(Color.appAccent)
                            .frame(width: 44, height: 44)
                            .background(Color.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 12))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L.t("Ver otras rutas", "See other routes"))
                }
            }
        }
    }

    private func navigationButton(previous: Bool) -> some View {
        let disabled = previous ? pageIndex == 0 : pageIndex + 1 >= pages.count
        return Button { movePage(by: previous ? -1 : 1) } label: {
            Image(systemName: previous ? "chevron.left" : "chevron.right")
                .font(.body.weight(.medium))
                .foregroundStyle(disabled ? Color(uiColor: .tertiaryLabel) : Color.appAccent)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(previous ? L.t("Ruta anterior", "Previous route") : L.t("Ruta siguiente", "Next route"))
    }

    private func movePage(by offset: Int) {
        let next = pageIndex + offset
        guard pages.indices.contains(next) else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.32)) {
            visibleOptionID = pages[next].optionID
        }
    }

    private func synchronizeSelection() {
        let selected = vm.itinerario?.optionID ?? pages.first?.optionID ?? []
        guard visibleOptionID != selected else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.32)) {
            visibleOptionID = selected
        }
    }

    private var invitacionConfirmarViaje: some View {
        Button {
            guard !vm.calculandoItinerario,
                  vm.itinerario?.optionID == visibleOptionID,
                  trackingCoordinator.selectedTripRoute == nil else { return }
            boardingAfterDetails = visibleOptionID
            showDetails = false
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "bus.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.appAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.t("¿Ya subiste?", "Already on board?"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.onSurface)
                    Text(L.t("Confirma tu línea", "Confirm your line"))
                        .font(.caption)
                        .foregroundStyle(Color.onSurfaceVariant)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.onSurfaceVariant)
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
        .accessibilityLabel(L.t("¿Ya subiste? Confirma tu línea", "Already on board? Confirm your line"))
    }
}

private enum RoutePanelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension TransitRouteCategory {
    var title: String {
        switch self {
        case .recommended: return L.t("Recomendada", "Recommended")
        case .fastest: return L.t("Más rápida", "Fastest")
        case .closestBoarding: return L.t("Más cercana", "Closest boarding")
        }
    }
}

struct RouteCategoryBadges: View {
    let categories: [TransitRouteCategory]

    var body: some View {
        Text(categories.isEmpty ? L.t("Tu elección", "Your choice") : categories.map(\.title).joined(separator: " · "))
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.onSurfaceVariant)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// La identidad de la línea siempre se lee en tinta neutra; su color GTFS
/// queda en el indicador para no perder legibilidad con líneas muy oscuras.
struct RouteLineIdentity: View {
    let route: RutaGTFS
    var showsOperator = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Capsule().fill(route.color).frame(width: 4, height: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(route.lineaConLetra)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.onSurface)
                    .fixedSize(horizontal: false, vertical: true)
                if showsOperator {
                    Text(route.empresa).font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

struct RouteJourneyLines: View {
    let plan: TransitItinerary
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        let layout = textSize >= .xxxLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        return layout {
            RouteLineIdentity(route: plan.route)
            if let transfer = plan.transfer {
                Image(systemName: textSize >= .xxxLarge ? "arrow.down" : "arrow.right")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(L.t("1 transbordo", "1 transfer"))
                RouteLineIdentity(route: transfer.route)
            }
        }
    }
}
