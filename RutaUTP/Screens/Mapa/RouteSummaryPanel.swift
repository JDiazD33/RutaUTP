import SwiftUI
import MapKit

struct RouteSummaryPanel: View {
    let vm: MapaViewModel
    let maximumPanelHeight: CGFloat
    @EnvironmentObject private var trackingCoordinator: PassiveTrackingCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onConfirmBoarding: () -> Void
    let onShowAlternatives: () -> Void
    let onDetailsPresentationChange: (Bool) -> Void
    @State private var visibleOptionID: [String] = []
    @State private var showDetails = false
    @State private var boardingAfterDetails: [String]?

    private var pages: [TransitItinerary] { vm.opcionesResumen }

    private var pageIndex: Int { pages.firstIndex { $0.optionID == visibleOptionID } ?? 0 }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 6) {
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
                        .foregroundStyle(Color.appPrimary)
                    }
                }
                if let mensaje = vm.mensajeAlternativa {
                    Label(L.aviso(mensaje), systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Color.onSurfaceVariant)
                }
            }
            .padding(10)
        }
        .scrollBounceBehavior(.basedOnSize)
        // El límite comprende cabecera, tarjeta y controles, no solo la guía.
        .frame(height: maximumPanelHeight)
        .font(.footnote)
        .foregroundStyle(Color.onSurface)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
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
        HStack {
            Text(vm.busquedaResultado.map { L.t("Hacia ", "To ") + $0.titulo } ?? "")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            Button { vm.limpiar() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.onSurfaceVariant)
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
        .frame(height: min(124, max(88, maximumPanelHeight - 108)))
    }

    private func compactSummary(_ plan: TransitItinerary) -> some View {
        let current = vm.itinerarioInstalado
        let metrics = (current?.plan.optionID == plan.optionID ? current?.metrics : nil)
            ?? ItineraryMetrics(plan: plan)
        let lines = plan.route.lineaConLetra
            + (plan.transfer.map { " → " + $0.route.lineaConLetra } ?? "")
        return VStack(alignment: .leading, spacing: 6) {
            RouteCategoryBadges(categories: vm.categorias(de: plan))
            Text(lines)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text("~" + L.f("{0} min en total", "{0} min total",
                           ["\(max(1, Int(ceil((metrics.totalSeconds + plan.boardingWaitSeconds) / 60))))"]))
                .font(.subheadline.weight(.semibold))
            Label(L.f("{0} min a pie para subir · {1} m", "{0} min walk to board · {1} m",
                      ["\(Int(ceil(metrics.walkToBoardMeters / 1.4 / 60)))", "\(Int(ceil(metrics.walkToBoardMeters)))"]),
                  systemImage: "figure.walk")
            Text(plan.transfer == nil ? L.t("Sin transbordos", "No transfers") : L.t("1 transbordo", "1 transfer"))
                .foregroundStyle(Color.onSurfaceVariant)
            if vm.seleccionandoAlternativa == plan.optionID {
                Label(L.t("Comprobando caminatas…", "Checking walks…"), systemImage: "ellipsis")
                    .font(.caption)
            }
        }
    }

    private var detailsSheet: some View {
        NavigationStack {
            ScrollView {
                if let plan = pages.first(where: { $0.optionID == visibleOptionID }) {
                    guide(plan)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
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
        .tint(Color.appPrimary)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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
        return VStack(alignment: .leading, spacing: 8) {
            RouteCategoryBadges(categories: vm.categorias(de: plan))
            Label(L.t("Toma la línea ", "Take line ") + plan.route.lineaConLetra + " · " + plan.route.precioTexto,
                  systemImage: "bus.fill")
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(L.f("{0} min a pie para subir · {1} m", "{0} min walk to board · {1} m",
                     ["\(Int(ceil(metrics.walkToBoardMeters / 1.4 / 60)))", "\(Int(ceil(metrics.walkToBoardMeters)))"]))
                .font(.subheadline.weight(.semibold))
            Text("~" + L.f("{0} min en total", "{0} min total",
                           ["\(max(1, Int(ceil((metrics.totalSeconds + plan.boardingWaitSeconds) / 60))))"]))
                .font(.subheadline.weight(.semibold))
            Label(plan.board.nombre, systemImage: "figure.walk")
            if let transfer = plan.transfer {
                Text(L.t("1 transbordo", "1 transfer")).fontWeight(.bold)
                Label(L.t("Baja en ", "Get off at ") + plan.firstAlight.nombre, systemImage: "mappin.and.ellipse")
                Label(L.t("Camina ", "Walk ") + "\(Int(ceil(metrics.transferWalkMeters))) m · " + transfer.board.nombre,
                      systemImage: "figure.walk")
                Label(L.t("Luego toma ", "Then take ") + transfer.route.lineaConLetra + " · " + transfer.route.precioTexto,
                      systemImage: "arrow.triangle.swap")
                    .fixedSize(horizontal: false, vertical: true)
                Text(L.t("El tiempo incluye una espera estimada para el segundo micro.",
                         "Time includes an estimated wait for the second bus."))
                    .foregroundStyle(Color.onSurfaceVariant)
            }
            Label(L.t("Baja en ", "Get off at ") + plan.alight.nombre, systemImage: "mappin.and.ellipse")
            Text(L.f("Luego camina {0} m hasta tu destino.", "Then walk {0} m to your destination.",
                     ["\(Int(ceil(metrics.walkToDestinationMeters)))"]))
                .foregroundStyle(Color.onSurfaceVariant)
            if plan.route.headwayMin > 0 {
                Text(L.f("Incluye ~{0} min de espera del primer micro.", "Includes ~{0} min waiting for the first bus.",
                         ["\(Int(ceil(plan.boardingWaitSeconds / 60)))"]))
                    .foregroundStyle(Color.onSurfaceVariant)
            } else {
                Text(L.t("Espera del primer micro no disponible.", "First bus waiting time unavailable."))
                    .foregroundStyle(Color.onSurfaceVariant)
            }
            if current {
                if plan.walkingApproximate { AvisoRutaAproximada() }
            } else {
                Text(L.t("Vista previa con caminatas aproximadas.", "Preview with approximate walks."))
                    .font(.caption)
                    .foregroundStyle(Color.onSurfaceVariant)
            }
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
    }

    private var pageNavigation: some View {
        HStack(spacing: 4) {
            if pages.count > 1 {
                navigationButton(previous: true)
                Text(L.f("Ruta {0} de {1}", "Route {0} of {1}", ["\(pageIndex + 1)", "\(pages.count)"]))
                    .font(.caption2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .accessibilityAdjustableAction { direction in
                        if direction == .increment { movePage(by: 1) }
                        if direction == .decrement { movePage(by: -1) }
                    }
                navigationButton(previous: false)
            }
            Button { showDetails = true } label: {
                Text(L.t("Ver detalles", "View details"))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if vm.alternativasItinerario.count > 1 {
                Button(action: onShowAlternatives) {
                    Image(systemName: "list.bullet")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.t("Ver otras rutas", "See other routes"))
            }
        }
        .foregroundStyle(Color.appPrimary)
    }

    private func navigationButton(previous: Bool) -> some View {
        Button { movePage(by: previous ? -1 : 1) } label: {
            Image(systemName: previous ? "chevron.left" : "chevron.right")
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(previous ? pageIndex == 0 : pageIndex + 1 >= pages.count)
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
                    .foregroundStyle(Color.appPrimary)
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
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.appPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.appPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            .fixedSize(horizontal: false, vertical: true)
    }
}
