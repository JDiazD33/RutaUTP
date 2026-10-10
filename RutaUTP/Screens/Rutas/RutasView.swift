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

    // MARK: - Lista de rutas
    private var listaScreen: some View {
        let rutas = viewModel.rutasFiltradas
        return VStack(spacing: 0) {
            header
            buscador
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L.signable("rutas.elegir", "Elige tu ruta", "Pick your route"))
                                .font(.headlineSm)
                                .foregroundStyle(Color.onSurface)
                                .seniable("rutas.elegir", distintivoDx: 10)
                                .accessibilityAddTraits(.isHeader)
                            Text(TransporteApp.rutasUTPPendientes
                                 ? L.t("Buses UTP · rutas próximamente", "UTP buses · routes coming soon")
                                 : L.t("Encuentra tu micro y revisa su recorrido", "Find your bus and check its route"))
                                .font(.bodySm)
                                .foregroundStyle(Color.onSurfaceVariant)
                        }
                        Spacer(minLength: 8)
                        if !viewModel.cargando && viewModel.errorCarga == nil && !viewModel.feedVacio {
                            Text("\(rutas.count)")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.onPrimaryContainer)
                                .padding(12)
                                .background(Color.primaryContainer, in: Capsule())
                                .accessibilityLabel(L.t("\(rutas.count) rutas encontradas", "\(rutas.count) routes found"))
                        }
                    }
                    .padding(.vertical, 6)

                    if viewModel.cargando {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(L.t("Cargando rutas…", "Loading routes…"))
                                .font(.bodySm)
                                .foregroundStyle(Color.onSurfaceVariant)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    } else if let error = viewModel.errorCarga {
                        VStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 26))
                            Text(error.mensajeUsuario)
                                .font(.bodySm)
                            Button(L.t("Reintentar", "Try again")) {
                                Task { await viewModel.cargar(reintentar: true) }
                            }
                            .frame(minHeight: 44)
                        }
                        .foregroundStyle(Color.onSurfaceVariant)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                        .multilineTextAlignment(.center)
                    } else if viewModel.feedVacio {
                        estadoVacio(TransporteApp.rutasUTPPendientes ? TransporteApp.mensajePendiente
                                    : L.t("El catálogo no contiene rutas.", "The catalog contains no routes."))
                    } else if rutas.isEmpty {
                        estadoVacio(viewModel.textoBusqueda.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    && viewModel.filtroCerca != nil
                                    ? L.t("No hay líneas con paradero a menos de \(Int(RutasViewModel.radioCercaMetros)) m de este lugar.", "No routes have a stop within \(Int(RutasViewModel.radioCercaMetros)) m of this place.")
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

    private func estadoVacio(_ mensaje: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "bus")
                .font(.system(size: 28))
                .accessibilityHidden(true)
            Text(mensaje)
                .font(.bodySm)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(Color.onSurfaceVariant)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Buscador de rutas
    private var buscador: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.onSurfaceVariant)
                    .accessibilityHidden(true)
                TextField(L.t("Letra, línea, empresa o avenida", "Letter, line, company or avenue"), text: $viewModel.textoBusqueda)
                    .font(.bodySm)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .accessibilityLabel(L.t("Buscar rutas por letra, línea, empresa o avenida", "Search routes by letter, line, company or avenue"))
                if !viewModel.textoBusqueda.isEmpty {
                    Button { viewModel.textoBusqueda = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.onSurfaceVariant)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L.t("Borrar búsqueda de rutas", "Clear route search"))
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .frame(minHeight: 52)
            .background(Color.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.outlineVariant.opacity(0.4), lineWidth: 1)
            }
            Text(L.t("Ejemplo: A · M-34 · empresa · Mansiche", "Example: A · M-34 · company · Mansiche"))
                .font(.caption)
                .foregroundStyle(Color.onSurfaceVariant)
                .padding(.horizontal, 3)
            if let cerca = viewModel.filtroCerca {
                HStack(spacing: 8) {
                    Image(systemName: "location.fill")
                        .accessibilityHidden(true)
                    Text(L.t("Cerca de ", "Near ") + cerca.titulo + " · \(Int(RutasViewModel.radioCercaMetros)) m")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        withAnimation { viewModel.limpiarFiltroCerca() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L.t("Quitar filtro de cercanía", "Clear nearby filter"))
                }
                .foregroundStyle(Color.onPrimaryContainer)
                .padding(.leading, 12)
                .background(Color.primaryContainer, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
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
