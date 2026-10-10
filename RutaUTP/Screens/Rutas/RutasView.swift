//
//  RutasView.swift
//  RutaUTP
//
//  Vista de Rutas (tab "Rutas" del BottomNavBar).
//  - Estado 1 (sin ruta seleccionada): mapa no interactivo + lista de rutas.
//  - Estado 2 (con ruta seleccionada): DetalleRutaView con transición slide.
//

import SwiftUI
import MapKit

// MARK: - Vista principal
struct RutasView: View {
    @EnvironmentObject var router: AppRouter
    @StateObject private var viewModel = RutasViewModel()
    @State private var rutaSeleccionada: RutaOpcion? = nil

    #if DEBUG
    @State private var debugExplorador: Bool = false
    @State private var debugNavegacion: Bool = false
    #endif

    private let tabBarHeight: CGFloat = 64

    var body: some View {
        ZStack(alignment: .bottom) {
            if let ruta = rutaSeleccionada {
                DetalleRutaView(ruta: ruta, onBack: {
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
            BottomNavBar()
        }
        .ignoresSafeArea(edges: .bottom)
        .animation(.spring(response: 0.3), value: rutaSeleccionada == nil)
        .task {
            await viewModel.cargar()
            procesarHookDebug()
            consumirLugarCercano()
            consumirRutaPendiente()
        }
        .onChange(of: router.lugarCercanoPendiente) { _, _ in
            consumirLugarCercano()
        }
        .onChange(of: router.rutaPendiente) { _, _ in
            consumirRutaPendiente()
        }
        #if DEBUG
        .fullScreenCover(isPresented: $debugExplorador) {
            if let ruta = rutaSeleccionada { ExploradorRutaView(ruta: ruta) }
        }
        .fullScreenCover(isPresented: $debugNavegacion) {
            if let ruta = rutaSeleccionada {
                NavegacionRutaView(ruta: ruta, onFinish: { debugNavegacion = false })
            }
        }
        #endif
    }

    /// Recibe el "Buscar transporte cercano" de Guardado y filtra el GTFS.
    private func consumirLugarCercano() {
        guard let lugar = router.lugarCercanoPendiente else { return }
        router.lugarCercanoPendiente = nil
        viewModel.limpiarFiltroCerca()
        viewModel.textoBusqueda = ""
        viewModel.activarFiltroCerca(destino: lugar)
    }

    /// Recibe el "Ver Ruta Completa" del popup de bus del Mapa y abre el
    /// detalle de esa línea exacta (route_id; por defecto, por línea).
    private func consumirRutaPendiente() {
        guard let id = router.rutaPendiente else { return }
        router.rutaPendiente = nil
        guard let ruta = viewModel.rutas.first(where: { $0.id == id })
                ?? viewModel.rutas.first(where: { $0.linea == id }) else { return }
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

    // MARK: - Lista screen
    private var listaScreen: some View {
        VStack(spacing: 0) {
            // Header
            header
            buscador
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    RutasMapView()
                        .frame(height: 280)

                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L.signable("rutas.elegir", "Elige tu ruta", "Pick your route"))
                                    .font(.headlineSm)
                                    .foregroundStyle(.onSurface)
                                    .seniable("rutas.elegir", distintivoDx: 10)
                                Text(TransporteApp.rutasUTPPendientes
                                     ? L.t("Buses UTP · rutas próximamente", "UTP buses · routes coming soon")
                                     : viewModel.cargando
                                     ? L.t("Cargando rutas oficiales…", "Loading official routes…")
                                     : (viewModel.filtroCerca != nil
                                        ? L.t("Líneas que pasan cerca de", "Lines passing near") + " \(viewModel.filtroCerca!.titulo)"
                                        : L.t("\(viewModel.rutas.count) rutas oficiales · ordenadas por cercanía a UTP", "\(viewModel.rutas.count) official routes · sorted by distance to UTP")))
                                    .font(.bodySm)
                                    .foregroundStyle(.onSurfaceVariant)
                            }
                            Spacer()
                        }
                        .padding(.top, 20)

                        if viewModel.cargando {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text(L.t("Parseando feed GTFS…", "Parsing GTFS feed…"))
                                    .font(.bodySm)
                                    .foregroundStyle(.onSurfaceVariant)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                        } else if let error = viewModel.errorCarga {
                            VStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 26))
                                    .foregroundStyle(.onSurfaceVariant)
                                Text(error.mensajeUsuario)
                                    .font(.bodySm)
                                    .foregroundStyle(.onSurfaceVariant)
                                Button(L.t("Reintentar", "Try again")) {
                                    Task { await viewModel.cargar(reintentar: true) }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                            .multilineTextAlignment(.center)
                        } else if viewModel.feedVacio {
                            Text(TransporteApp.rutasUTPPendientes ? TransporteApp.mensajePendiente
                                 : L.t("El catálogo no contiene rutas.", "The catalog contains no routes."))
                                .font(.bodySm)
                                .foregroundStyle(.onSurfaceVariant)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 32)
                        } else if viewModel.rutasFiltradas.isEmpty {
                            Text(viewModel.filtroCerca != nil
                                 ? L.t("Ninguna línea tiene paradero a menos de \(Int(RutasViewModel.radioCercaMetros)) m de este lugar", "No route has a stop within \(Int(RutasViewModel.radioCercaMetros)) m of this place")
                                 : L.t("No hay rutas que coincidan con ", "No routes match ") + "“\(viewModel.textoBusqueda)”")
                                .font(.bodySm)
                                .foregroundStyle(.onSurfaceVariant)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 32)
                                .multilineTextAlignment(.center)
                        } else {
                            ForEach(viewModel.rutasFiltradas) { ruta in
                                Button {
                                    withAnimation(.spring(response: 0.3)) {
                                        rutaSeleccionada = ruta
                                    }
                                } label: {
                                    RutaOpcionCard(ruta: ruta, distanciaLugar: viewModel.distanciaTexto(ruta: ruta))
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint(L.t("Muestra el recorrido, paraderos y opciones de navegación", "Shows the route, stops and navigation options"))
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, tabBarHeight + 30)
                }
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
    }

    // MARK: - Buscador de rutas
    private var buscador: some View {
        VStack(spacing: 8) {
            if let cerca = viewModel.filtroCerca {
                HStack(spacing: 8) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 13, weight: .semibold))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(L.t("Líneas cerca de", "Lines near") + " \(cerca.titulo)")
                            .font(.bodySm)
                            .fontWeight(.semibold)
                            .foregroundStyle(.onPrimaryContainer)
                        Text(String(format: L.t("%1$d de %2$d líneas con paradero a menos de %3$d m", "%1$d of %2$d routes have a stop within %3$d m"), viewModel.rutasFiltradas.count, viewModel.rutas.count, Int(RutasViewModel.radioCercaMetros)))
                            .font(.system(size: 10))
                            .foregroundStyle(.onPrimaryContainer.opacity(0.8))
                    }
                    Spacer()
                    Button {
                        withAnimation { viewModel.limpiarFiltroCerca() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(.onPrimaryContainer.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L.t("Quitar filtro", "Clear filter"))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primaryContainer)
                )
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.onSurfaceVariant)
                    TextField(L.t("Buscar línea, empresa o avenida", "Search line, company or avenue"), text: $viewModel.textoBusqueda)
                        .font(.bodySm)
                        .autocorrectionDisabled()
                    if !viewModel.textoBusqueda.isEmpty {
                        Button {
                            viewModel.textoBusqueda = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(.onSurfaceVariant.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L.t("Borrar búsqueda de rutas", "Clear route search"))
                        .frame(minWidth: 44, minHeight: 44)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.surfaceContainerLowest)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.outlineVariant.opacity(0.40), lineWidth: 1)
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "bus.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.appPrimary)
                .accessibilityHidden(true)
            Text(TransporteApp.busesUTPActivos ? L.t("Rutas UTP", "UTP routes")
                 : L.signable("rutas.titulo", "Rutas", "Routes"))
                .font(.headlineLgMobile)
                .foregroundStyle(.appPrimary)
                .seniable("rutas.titulo")
                .accessibilityAddTraits(.isHeader)
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
        .background(Color.appSurface)
        .overlay(
            Rectangle()
                .fill(Color.outlineVariant.opacity(0.25))
                .frame(height: 1),
            alignment: .bottom
        )
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}

#Preview {
    RutasView().environmentObject(AppRouter())
}
