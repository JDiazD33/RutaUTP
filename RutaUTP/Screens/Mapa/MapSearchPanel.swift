import SwiftUI
import MapKit

struct MapSearchPanel: View {
    @Bindable var vm: MapaViewModel
    @FocusState.Binding var campoEnfocado: Bool
    @Binding var showDestinosGuardados: Bool
    @AccessibilityFocusState private var guardadosEnfocados: Bool

    /// Abre los mismos paraderos que se guardan desde Seguridad.
    private var botonDestinosGuardados: some View {
        Button {
            AppHaptics.impact(.light)
            campoEnfocado = false
            showDestinosGuardados = true
        } label: {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.appPrimary)
                .frame(width: 34, height: 34)
                .background(
                    Circle().fill(Color.surfaceContainerHighest)
                )
                .overlay(
                    Circle().stroke(Color.outlineVariant.opacity(0.5), lineWidth: 0.5)
                )
                .frame(width: 44, height: 44)
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
        VStack(spacing: 10) {
            // TextField
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.onSurfaceVariant)
                    .font(.system(size: 16))
                TextField(L.t("¿A dónde vas hoy?", "Where to today?"), text: $vm.textoBusqueda)
                    .font(.system(size: 15))
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

                botonDestinosGuardados
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.surfaceContainerLow))

            // Lista de Sugerencias Autocompletadas (ej. UPAO)
            if !vm.sugerenciasBusqueda.isEmpty && campoEnfocado {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(vm.sugerenciasBusqueda.prefix(5), id: \.self) { sug in
                        Button {
                            campoEnfocado = false
                            vm.seleccionarSugerencia(sug)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundStyle(Color.appPrimary)
                                    .font(.system(size: 16))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sug.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.onSurface)
                                        .lineLimit(1)
                                    if !sug.subtitle.isEmpty {
                                        Text(sug.subtitle)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.onSurfaceVariant)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(sug.title)
                        .accessibilityValue(sug.subtitle)
                        .accessibilityHint(L.t("Busca una ruta hasta este lugar", "Finds a route to this place"))

                        if sug != vm.sugerenciasBusqueda.prefix(5).last {
                            Divider()
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.surfaceContainerLowest))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.outlineVariant.opacity(0.3), lineWidth: 0.5)
                )
            }

            // Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.destinos) { destino in
                        chip(destino)
                    }
                }
                // Respiración para la manita del distintivo: el ScrollView
                // recorta todo lo que sale del contenido y la parte de arriba
                // (y la derecha del último chip) se veía a la mitad.
                .padding(.leading, 2)
                .padding(.trailing, 10)
                .padding(.top, 8)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.outlineVariant.opacity(0.30), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 2)
        .onChange(of: showDestinosGuardados) { _, abierto in
            if !abierto && vm.busquedaResultado == nil { guardadosEnfocados = true }
        }
    }

    private func chip(_ destino: DestinoChip) -> some View {
        let activo = vm.destinoSeleccionado?.id == destino.id
            && vm.destinoSeleccionado?.lat == destino.lat
            && vm.destinoSeleccionado?.lon == destino.lon
        let acento = Color.appPrimary
        return Button {
            SeniasPresenter.shared.ejecutarTrasVerSenia(clave: destino.claveSenia) {
                campoEnfocado = false
                vm.seleccionar(destino: destino)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: destino.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(acento)
                    .frame(width: 20)
                Text(destino.label)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                if activo {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(acento)
                }
            }
            .foregroundStyle(Color.onSurface)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(acento.opacity(activo ? 0.22 : 0.10), in: Capsule())
            .overlay(Capsule().stroke(acento.opacity(activo ? 0.8 : 0.25), lineWidth: 1))
            // Compacto a la vista, con un área cómoda para tocar.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
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
