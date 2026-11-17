import SwiftUI
import MapKit

struct MapSearchPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var vm: MapaViewModel
    @FocusState.Binding var campoEnfocado: Bool
    @Binding var showDestinosGuardados: Bool
    @AccessibilityFocusState private var guardadosEnfocados: Bool

    private var acento: Color { colorScheme == .dark ? .primaryFixed : .appPrimary }
    private var animacionBusqueda: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.25)
    }
    private var sugerenciasVisibles: [[String]] {
        guard campoEnfocado else { return [] }
        if vm.usaBusquedaLocal { return vm.sugerenciasLocales.prefix(5).map { [$0.titulo, $0.detalle] } }
        return vm.sugerenciasBusqueda.prefix(5).map { [$0.title, $0.subtitle] }
    }

    /// Hay texto escrito mientras se busca sin red.
    private var mostrarResultadosLocales: Bool {
        campoEnfocado && vm.usaBusquedaLocal
            && !vm.textoBusqueda.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Abre los mismos paraderos que se guardan desde Seguridad.
    private var botonDestinosGuardados: some View {
        Button {
            AppHaptics.impact(.light)
            campoEnfocado = false
            showDestinosGuardados = true
        } label: {
            Image(systemName: "bookmark.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(acento)
                .frame(minWidth: 30, minHeight: 30)
                .background(
                    Circle().fill(Color.surfaceContainer)
                )
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L.t("Paraderos y lugares guardados", "Saved stops and places"))
        .accessibilityFocused($guardadosEnfocados)
        .accessibilityHint(L.t("Elige un destino guardado para calcular cómo llegar.",
                              "Choose a saved destination to find directions."))
    }

    // MARK: - Search panel
    var body: some View {
        VStack(spacing: 8) {
            // TextField
            barraBusqueda

            // Lista de Sugerencias Autocompletadas (ej. UPAO)
            listaSugerencias

            // Sin red: resultado vacío al confirmar el texto
            if let aviso = vm.avisoBusquedaLocal, !campoEnfocado {
                Label(aviso, systemImage: "wifi.slash")
                    .font(.footnote)
                    .foregroundStyle(Color.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }

            // Chips
            destinosRapidos
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.outlineVariant.opacity(0.30), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
        .animation(animacionBusqueda, value: sugerenciasVisibles)
        .animation(animacionBusqueda, value: vm.avisoBusquedaLocal)
        .animation(animacionBusqueda, value: vm.destinos.map(\.id))
        // Si la red cambia mientras se escribe, la lista cambia de fuente.
        .onChange(of: vm.usaBusquedaLocal) { _, _ in
            guard campoEnfocado else { return }
            vm.actualizarTextoBusqueda(vm.textoBusqueda)
        }
        .onChange(of: showDestinosGuardados) { _, abierto in
            if !abierto && vm.busquedaResultado == nil { guardadosEnfocados = true }
        }
    }

    private var barraBusqueda: some View {
        HStack(spacing: 10) {
            Image(systemName: vm.usaBusquedaLocal ? "wifi.slash" : "magnifyingglass")
                .foregroundStyle(.onSurfaceVariant)
                .font(.body)
                .frame(minWidth: 22)
                .accessibilityHidden(true)
            campoBusqueda
            estadoBusqueda

            botonDestinosGuardados
        }
        // El botón de guardados ya aporta los 44 pt táctiles: la barra no
        // necesita relleno vertical extra para cumplirlos.
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.surfaceContainerLow))
    }

    private var campoBusqueda: some View {
        TextField(vm.usaBusquedaLocal
                  ? L.t("Paradero o lugar guardado", "Stop or saved place")
                  : L.t("¿A dónde vas hoy?", "Where to today?"),
                  text: $vm.textoBusqueda)
            .font(.body)
            .accessibilityHint(vm.usaBusquedaLocal
                ? L.t("Sin conexión: busca entre los paraderos y tus lugares guardados",
                      "No connection: searches stops and your saved places")
                : "")
            .foregroundStyle(.onSurface)
            .focused($campoEnfocado)
            .submitLabel(.search)
            .onSubmit {
                campoEnfocado = false
                vm.buscarTexto(vm.textoBusqueda)
            }
            .onChange(of: vm.textoBusqueda) { _, nuevo in
                // Solo se autocompleta mientras el usuario escribe en
                // el campo. Cuando el texto lo pone el código (al
                // elegir un chip, un resultado o un lugar guardado) el
                // campo no está enfocado y no hay que consultar nada.
                guard campoEnfocado else { return }
                vm.actualizarTextoBusqueda(nuevo)
            }
    }

    @ViewBuilder
    private var estadoBusqueda: some View {
        if vm.buscando {
            ProgressView()
                .scaleEffect(0.8)
                .accessibilityLabel(L.t("Buscando destino", "Searching for destination"))
        } else if !vm.textoBusqueda.isEmpty {
            Button {
                vm.limpiar()
                campoEnfocado = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.onSurfaceVariant.opacity(0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.t("Borrar destino y ruta", "Clear destination and route"))
            .frame(minWidth: 44, minHeight: 44)
        }
    }

    @ViewBuilder
    private var listaSugerencias: some View {
        if mostrarResultadosLocales {
            listaLocal
        } else if !vm.sugerenciasBusqueda.isEmpty && campoEnfocado {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(vm.sugerenciasBusqueda.prefix(5), id: \.self) { sug in
                    botonSugerencia(sug)

                    if sug != vm.sugerenciasBusqueda.prefix(5).last {
                        Divider()
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.surfaceContainerLowest))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.outlineVariant.opacity(0.3), lineWidth: 0.5)
            )
            .transition(.opacity)
        }
    }

    /// Resultados sin red. El encabezado explica de dónde salen.
    private var listaLocal: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(ConectividadService.shared.estado == .sinConexion
                  ? L.t("Sin conexión · datos del iPhone", "No connection · data on this iPhone")
                  : L.t("Modo offline · datos del iPhone", "Offline mode · data on this iPhone"),
                  systemImage: "wifi.slash")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.onSurfaceVariant)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)
            if vm.buscandoLocal && vm.sugerenciasLocales.isEmpty {
                ProgressView(L.t("Buscando en el iPhone…", "Searching on this iPhone…"))
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            } else if vm.sugerenciasLocales.isEmpty {
                Text(L.t("Ningún paradero ni lugar guardado coincide. Prueba con el nombre de una avenida o de un paradero.",
                         "No stop or saved place matches. Try the name of an avenue or a stop."))
                    .font(.subheadline)
                    .foregroundStyle(Color.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            } else {
                ForEach(vm.sugerenciasLocales.prefix(5)) { sugerencia in
                    Divider()
                    botonSugerenciaLocal(sugerencia)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.surfaceContainerLowest))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.outlineVariant.opacity(0.3), lineWidth: 0.5)
        )
        .transition(.opacity)
    }

    private func botonSugerenciaLocal(_ sugerencia: SugerenciaLocal) -> some View {
        Button {
            campoEnfocado = false
            vm.seleccionarSugerenciaLocal(sugerencia)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: sugerencia.icono)
                    .foregroundStyle(acento)
                    .font(.body)
                    .frame(minWidth: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(sugerencia.titulo)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.onSurface)
                        .lineLimit(2)
                    Text(sugerencia.detalle)
                        .font(.subheadline)
                        .foregroundStyle(.onSurfaceVariant)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sugerencia.titulo)
        .accessibilityValue(sugerencia.detalle)
        .accessibilityHint(L.t("Busca una ruta hasta este lugar con los datos del iPhone",
                               "Finds a route to this place using data on this iPhone"))
    }

    private func botonSugerencia(_ sug: MKLocalSearchCompletion) -> some View {
        Button {
            campoEnfocado = false
            vm.seleccionarSugerencia(sug)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(acento)
                    .font(.body)
                VStack(alignment: .leading, spacing: 2) {
                    Text(sug.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.onSurface)
                        .lineLimit(1)
                    if !sug.subtitle.isEmpty {
                        Text(sug.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.onSurfaceVariant)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .transition(.opacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sug.title)
        .accessibilityValue(sug.subtitle)
        .accessibilityHint(L.t("Busca una ruta hasta este lugar", "Finds a route to this place"))
    }

    private var destinosRapidos: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(vm.destinos) { destino in
                    chip(destino)
                        .transition(.opacity)
                }
            }
            // Respiración para la manita del distintivo: el ScrollView
            // recorta todo lo que sale del contenido y la parte de arriba
            // (y la derecha del último chip) se veía a la mitad.
            .padding(.leading, 2)
            .padding(.trailing, 10)
            .padding(.top, 6)
        }
    }

    private func chip(_ destino: DestinoChip) -> some View {
        let activo = vm.destinoSeleccionado?.id == destino.id
            && vm.destinoSeleccionado?.lat == destino.lat
            && vm.destinoSeleccionado?.lon == destino.lon
        return Button {
            SeniasPresenter.shared.ejecutarTrasVerSenia(clave: destino.claveSenia) {
                campoEnfocado = false
                vm.seleccionar(destino: destino)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: destino.icon)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(acento)
                    .frame(minWidth: 20)
                Text(destino.label)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if activo {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(acento)
                        .transition(.opacity)
                }
            }
            .foregroundStyle(Color.onSurface)
            .padding(.horizontal, 10)
            .frame(minHeight: 34)
            .background(activo ? acento.opacity(0.12) : Color.surfaceContainerLow, in: Capsule())
            .overlay(Capsule().stroke(activo ? acento.opacity(0.45) : Color.clear, lineWidth: 0.5))
            // Compacto a la vista, con un área cómoda para tocar.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .animation(animacionBusqueda, value: activo)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(destino.label)
        .accessibilityValue(activo ? L.t("Seleccionado", "Selected") : "")
        .accessibilityAddTraits(activo ? .isSelected : [])
        .accessibilityHint(L.t("Mostrar este destino en el mapa", "Show this destination on the map"))
        .seniable(destino.claveSenia, conGesto: false)
    }
}
