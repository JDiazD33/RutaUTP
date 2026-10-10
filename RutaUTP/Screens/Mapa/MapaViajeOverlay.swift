import SwiftUI

/// Controles del viaje confirmado; deja libre el centro del mapa.
struct MapaViajeOverlay<ReportButton: View, LocationButton: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var coordinator: PassiveTrackingCoordinator
    let locationService: LocationServiceProtocol
    let destino: String?
    @Binding var mostrarAviso: Bool
    @Binding var mostrarDrawer: Bool
    let statusColor: Color
    let onEndTrip: () -> Void
    let reportButton: ReportButton
    let locationButton: LocationButton
    @AccessibilityFocusState private var menuFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
                        mostrarDrawer = true
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.onSurface)
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.t("Abrir menú", "Open menu"))
                .accessibilityFocused($menuFocused)

                Group {
                    if mostrarAviso, let inicio = coordinator.tripStartedAt {
                        AvisoViajeIniciado(destino: destino, inicio: inicio) {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                                mostrarAviso = false
                            }
                        }
                    } else {
                        TripContributionPanel(coordinator: coordinator,
                                              locationService: locationService,
                                              statusMessage: coordinator.statusMessage,
                                              statusColor: statusColor,
                                              onEndTrip: onEndTrip)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer(minLength: 20)

            HStack {
                reportButton
                Spacer(minLength: 12)
                locationButton
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 34)
        }
        .onChange(of: mostrarDrawer) { _, open in
            if !open { menuFocused = true }
        }
    }
}

private struct AvisoViajeIniciado: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverOn
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let destino: String?
    let inicio: Date
    let onDismiss: () -> Void
    @State private var progreso: CGFloat = 1
    @State private var segundosRestantes = 6
    @GestureState private var desplazamiento = CGSize.zero

    private let duracion: TimeInterval = 6
    private var titulo: String {
        destino.map { L.t("Hacia ", "To ") + $0 } ?? L.t("Viaje iniciado", "Trip started")
    }
    private var cierreAutomatico: Date? {
        scenePhase == .active && !voiceOverOn ? inicio.addingTimeInterval(duracion) : nil
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(titulo)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.onSurface)
                    .fixedSize(horizontal: false, vertical: true)
                Text(voiceOverOn
                     ? L.t("Desliza para ver tu transporte", "Swipe to see your transport")
                     : L.t("Viaje iniciado · Se ocultará", "Trip started · Closing soon"))
                    .font(.caption)
                    .foregroundStyle(Color.onSurfaceVariant)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !voiceOverOn {
                ZStack {
                    Circle().stroke(Color.outlineVariant.opacity(0.5), lineWidth: 3)
                    Circle().trim(from: 0, to: progreso)
                        .stroke(Color.appPrimary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(segundosRestantes)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.onSurface)
                }
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.outlineVariant.opacity(0.3), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .offset(x: desplazamiento.width, y: min(0, desplazamiento.height))
        .gesture(
            DragGesture(minimumDistance: 15)
                .updating($desplazamiento) { value, state, _ in state = value.translation }
                .onEnded { value in
                    if value.translation.height < -40 || abs(value.translation.width) > 60 {
                        onDismiss()
                    }
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(titulo + L.t(". Viaje iniciado.", ". Trip started."))
        .accessibilityHint(L.t("Usa la acción Ocultar aviso para ver tu transporte público.",
                              "Use the Hide notice action to see your public transport."))
        .accessibilityAction(.escape) { onDismiss() }
        .accessibilityAction(named: Text(L.t("Ocultar aviso", "Hide notice"))) { onDismiss() }
        .task(id: cierreAutomatico) {
            guard !Task.isCancelled, let cierre = cierreAutomatico else { return }
            let restante = max(0, cierre.timeIntervalSinceNow)
            guard restante > 0 else { onDismiss(); return }
            progreso = CGFloat(restante / duracion)
            segundosRestantes = Int(ceil(restante))
            if !reduceMotion {
                withAnimation(.linear(duration: restante)) { progreso = 0 }
            }
            do {
                // Solo este aviso usa la cuenta atrás; la tarea se cancela al salir.
                while !Task.isCancelled {
                    let intervalo = cierre.timeIntervalSinceNow
                    guard intervalo > 0 else { onDismiss(); return }
                    try await Task.sleep(for: .seconds(min(1, intervalo)))
                    try Task.checkCancellation()
                    let segundos = max(0, cierre.timeIntervalSinceNow)
                    segundosRestantes = Int(ceil(segundos))
                    if reduceMotion { progreso = CGFloat(segundos / duracion) }
                }
            } catch { return }
        }
    }
}
