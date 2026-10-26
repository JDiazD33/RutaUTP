//
//  RutasView.swift
//  RutaUTP
//
//  Vista de Rutas (tab "Rutas" del BottomNavBar).
//  - Estado 1 (sin ruta seleccionada): buscador y lista de rutas.
//  - Estado 2 (con ruta seleccionada): DetalleRutaView con transición slide.
//

import SwiftUI

// MARK: - Vista principal
struct RutasView: View {
    let locationService: LocationServiceProtocol
    @EnvironmentObject var router: AppRouter
    @StateObject private var viewModel = RutasViewModel()
    @State private var rutaSeleccionada: RutaOpcion? = nil
    @State private var mostrarTransportes3D = false

    #if DEBUG
    @State private var debugExplorador: Bool = false
    @State private var debugNavegacion: Bool = false
    #endif

    @Environment(\.bottomNavBarHeight) private var tabBarHeight
    @Environment(\.mainNavigationHostedExternally) private var navigationHostedExternally
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reducirMovimiento
    @FocusState private var busquedaEnfocada: Bool
    @ScaledMetric(relativeTo: .title) private var tamanoEstado = 28
    private var acento: Color { colorScheme == .dark ? .primaryFixed : .appPrimary }
    private var superficie: Color { Color(uiColor: .secondarySystemGroupedBackground) }

    var body: some View {
        ZStack(alignment: .bottom) {
            if let ruta = rutaSeleccionada {
                DetalleRutaView(ruta: ruta, locationService: locationService, onBack: {
                    withAnimation(.spring(response: 0.3)) { rutaSeleccionada = nil }
                })
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal:   .move(edge: .trailing)
                ))
            } else {
                listaScreen
                    .transition(.opacity)
            }
            if !navigationHostedExternally { BottomNavBar() }
        }
        .ignoresSafeArea(edges: .bottom)
        .animation(.spring(response: 0.3), value: rutaSeleccionada == nil)
        .task {
            await viewModel.cargar()
            guard !Task.isCancelled else { return }
            procesarHookDebug()
            consumirLugarCercano()
            consumirRutaPendiente()
        }
        .onAppear {
            consumirLugarCercano()
            consumirRutaPendiente()
        }
        .onDisappear { busquedaEnfocada = false }
        .onChange(of: router.lugarCercanoPendiente) { _, _ in
            consumirLugarCercano()
        }
        .onChange(of: router.rutaPendiente) { _, _ in
            consumirRutaPendiente()
        }
        .sheet(isPresented: $mostrarTransportes3D) {
            Transportes3DView()
        }
        #if DEBUG
        .fullScreenCover(isPresented: $debugExplorador) {
            if let ruta = rutaSeleccionada { ExploradorRutaView(ruta: ruta) }
        }
        .fullScreenCover(isPresented: $debugNavegacion) {
            if let ruta = rutaSeleccionada {
                NavegacionRutaView(ruta: ruta, locationService: locationService,
                                   onFinish: { debugNavegacion = false })
            }
        }
        #endif
    }

    /// Recibe el "Buscar transporte cercano" de Guardado y filtra el GTFS.
    private func consumirLugarCercano() {
        guard router.currentScreen == .rutas,
              let lugar = router.lugarCercanoPendiente else { return }
        router.lugarCercanoPendiente = nil
        viewModel.limpiarFiltroCerca()
        viewModel.textoBusqueda = ""
        viewModel.activarFiltroCerca(destino: lugar)
    }

    /// Recibe el "Ver Ruta Completa" del popup de bus del Mapa y abre el
    /// detalle de esa línea exacta (route_id; por defecto, por línea).
    private func consumirRutaPendiente() {
        guard router.currentScreen == .rutas,
              !viewModel.cargando,
              let id = router.rutaPendiente else { return }
        guard let ruta = viewModel.rutas.first(where: { $0.id == id })
                ?? viewModel.rutas.first(where: { $0.linea == id }) else { return }
        router.rutaPendiente = nil
        withAnimation(.spring(response: 0.3)) {
            rutaSeleccionada = ruta
        }
    }

    #if DEBUG
    /// Hook de pruebas: `--ruta <n>` abre el detalle; `--vista explorador|navegacion`
    /// abre esa pantalla directamente sobre la ruta elegida.
    private func procesarHookDebug() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--ruta"), i + 1 < args.count,
              let indice = Int(args[i + 1]),
              viewModel.rutas.indices.contains(indice) else { return }
        rutaSeleccionada = viewModel.rutas[indice]
        if let j = args.firstIndex(of: "--vista"), j + 1 < args.count {
            switch args[j + 1] {
            case "explorador":  debugExplorador = true
            case "navegacion":  debugNavegacion = true
            default: break
            }
        }
    }
    #else
    private func procesarHookDebug() {}
    #endif

    // MARK: - Lista de rutas
    private var listaScreen: some View {
        let rutas = viewModel.rutasFiltradas
        return VStack(spacing: 0) {
            header
            buscador
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 14) {
                    accesoTransportes3D
                    encabezadoResultados(total: rutas.count)

                    if viewModel.cargando {
                        ProgressView(L.t("Cargando rutas…", "Loading routes…"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .tint(acento)
                            .frame(maxWidth: .infinity)
                            .padding(24)
                            .background(superficie, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    } else if let error = viewModel.errorCarga {
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text(error.mensajeUsuario)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            Button(L.t("Reintentar", "Try again")) {
                                Task { await viewModel.cargar(reintentar: true) }
                            }
                            .buttonStyle(.bordered)
                            .tint(acento)
                            .frame(minHeight: 44)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(24)
                        .background(superficie, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    } else if viewModel.feedVacio {
                        estadoVacio(TransporteApp.rutasUTPPendientes ? TransporteApp.mensajePendiente
                                    : L.t("El catálogo no contiene rutas.", "The catalog contains no routes."))
                    } else if rutas.isEmpty {
                        estadoVacio(viewModel.textoBusqueda.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    && viewModel.filtroCerca != nil
                                    ? L.f("No hay líneas con paradero a menos de {0} m de este lugar.", "No routes have a stop within {0} m of this place.", ["\(Int(RutasViewModel.radioCercaMetros))"])
                                    : L.t("No encontramos rutas para ", "No routes found for ") + "“\(viewModel.textoBusqueda)”")
                    } else {
                        ForEach(rutas) { ruta in
                            Button {
                                withAnimation(.spring(response: 0.3)) { rutaSeleccionada = ruta }
                            } label: {
                                RutaOpcionCard(ruta: ruta, distanciaLugar: viewModel.distanciaTexto(ruta: ruta))
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(L.t("Muestra el recorrido, paraderos y opciones de navegación", "Shows the route, stops and navigation options"))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, tabBarHeight + 30)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color.appBackground.ignoresSafeArea())
    }

    private var accesoTransportes3D: some View {
        Button {
            mostrarTransportes3D = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "cube.transparent")
                    .font(.title3)
                    .foregroundStyle(acento)
                    .frame(minWidth: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.t("Transportes en 3D", "Transport in 3D"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(L.t("Micro, combi y colectivo", "Bus, minibus and shared taxi"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .multilineTextAlignment(.leading)
            .padding(16)
            .contentShape(Rectangle())
            .background(superficie, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint(L.t("Abre los modelos para girarlos y ampliarlos", "Opens the models to rotate and zoom"))
    }

    private func encabezadoResultados(total: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 28) {
                    tituloResultados.fixedSize()
                    contadorResultados(total).fixedSize()
                }
                VStack(alignment: .leading, spacing: 6) {
                    tituloResultados
                    contadorResultados(total)
                }
            }
            if TransporteApp.rutasUTPPendientes {
                Text(L.t("Buses UTP · rutas próximamente", "UTP buses · routes coming soon"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    private var tituloResultados: some View {
        Text(L.signable("rutas.elegir", "Elige tu ruta", "Pick your route"))
            .font(.headline)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .seniable("rutas.elegir", distintivoDx: 10)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private func contadorResultados(_ total: Int) -> some View {
        if !viewModel.cargando && viewModel.errorCarga == nil && !viewModel.feedVacio {
            Text(total == 1 ? L.t("1 ruta encontrada", "1 route found")
                 : L.f("{0} rutas encontradas", "{0} routes found", ["\(total)"]))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func estadoVacio(_ mensaje: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "bus")
                .font(.system(size: min(tamanoEstado, 40), weight: .regular))
                .accessibilityHidden(true)
            Text(L.aviso(mensaje))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(superficie, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Buscador de rutas
    private var buscador: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField(L.t("Buscar rutas", "Search routes"), text: $viewModel.textoBusqueda)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .tint(acento)
                    .focused($busquedaEnfocada)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit { busquedaEnfocada = false }
                    .accessibilityLabel(L.t("Buscar rutas por letra, línea, empresa o avenida", "Search routes by letter, line, company or avenue"))
                if !viewModel.textoBusqueda.isEmpty {
                    Button { viewModel.textoBusqueda = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L.t("Borrar búsqueda de rutas", "Clear route search"))
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, viewModel.textoBusqueda.isEmpty ? 16 : 4)
            .frame(minHeight: 52)
            .background(superficie, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if busquedaEnfocada && viewModel.textoBusqueda.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(L.t("Ejemplo: A · M-34 · empresa · Mansiche", "Example: A · M-34 · company · Mansiche"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
            if let cerca = viewModel.filtroCerca {
                HStack(spacing: 12) {
                    Image(systemName: "location")
                        .foregroundStyle(acento)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.t("Cerca de ", "Near ") + cerca.titulo)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text(L.f("Hasta {0} m del lugar", "Within {0} m of this place", ["\(Int(RutasViewModel.radioCercaMetros))"]))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        withAnimation(reducirMovimiento ? nil : .easeInOut(duration: 0.2)) {
                            viewModel.limpiarFiltroCerca()
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L.t("Quitar filtro de cercanía", "Clear nearby filter"))
                }
                .padding(.leading, 16)
                .padding(.trailing, 4)
                .padding(.vertical, 6)
                .background(superficie, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Cabecera
    private var header: some View {
        HStack {
            Text(TransporteApp.busesUTPActivos ? L.t("Rutas UTP", "UTP routes")
                 : L.signable("rutas.titulo", "Rutas", "Routes"))
                .font(.title.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .seniable("rutas.titulo")
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 28)
            Image(systemName: "bus.fill")
                .font(.title3)
                .foregroundStyle(acento)
                .accessibilityHidden(true)
        }
        .foregroundStyle(Color.onSurface)
        .padding(.horizontal, 20)
        .frame(minHeight: 54)
    }

}

#Preview {
    RutasView(locationService: LocationService()).environmentObject(AppRouter())
}
