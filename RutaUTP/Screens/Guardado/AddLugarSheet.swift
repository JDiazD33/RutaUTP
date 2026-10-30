//
//  AddLugarSheet.swift
//  RutaUTP
//
//  Hoja para dar de alta un lugar guardado, con mapa en vivo.
//

import SwiftUI
import MapKit
import CoreLocation

// MARK: - Add Lugar sheet (con mapa en vivo)
struct AddLugarSheet: View {
    let locationService: LocationServiceProtocol
    var onSave: (LugarGuardado) -> Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var ubicacion = UbicacionMapaLugar()

    @State private var nombre: String = ""
    @State private var direccion: String = ""
    @State private var categoria: CategoriaLugar = .otro
    @State private var iconoPersonalizado: String?
    @FocusState private var campoActivo: Campo?

    private enum Campo { case nombre, direccion }

    private var acento: Color { colorScheme == .dark ? .primaryFixed : .appPrimary }
    private var superficie: Color { Color(uiColor: .secondarySystemGroupedBackground) }

    private var iconoElegido: String {
        categoria == .personalizado ? (iconoPersonalizado ?? categoria.icono) : categoria.icono
    }
    private let spanCercano = MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)

    // Ubicación elegida (por geocodificación o toque en el mapa)
    @State private var coordElegida: CLLocationCoordinate2D? = nil
    @State private var buscandoUbicacion = false
    @State private var direccionNoEncontrada = false
    @State private var recentrarTrigger = 0
    @State private var geocodeTask: Task<Void, Never>?
    @State private var geocoderActivo: CLGeocoder?
    @State private var revisionUbicacion = UUID()
    @State private var direccionValidada: String?
    /// Marca el PRÓXIMO cambio de `direccion` como automático (viene del mapa)
    /// y no como escritura de la persona. Existe solo para que
    /// `programarGeocodificacion` no intente geocodificar lo que el sistema
    /// acaba de escribir por ella.
    @State private var rellenoDesdeMapa = false
    @State private var mapaExpandido = false
    @State private var errorAlGuardar = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    campoNombre
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L.t("Ubicación", "Location"))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.onSurface)
                            .accessibilityAddTraits(.isHeader)
                        VStack(alignment: .leading, spacing: 0) {
                            mapaElegir

                            VStack(alignment: .leading, spacing: 12) {
                                campoDireccion
                                estadoUbicacion
                                if let aviso = ubicacion.aviso {
                                    Text(aviso)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(20)
                        }
                        .background(superficie, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    selectorCategoria
                    if categoria == .personalizado { selectorIcono }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.appBackground.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                botonGuardar
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.appSurface)
                    .overlay(alignment: .top) { Divider() }
            }
            .navigationTitle(L.t("Añadir lugar", "Add place"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appSurface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("Cancelar", "Cancel")) {
                        cancelarGeocodificacion()
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L.t("Listo", "Done")) { campoActivo = nil }
                }
            }
        }
        .tint(acento)
        .onAppear { ubicacion.iniciar(desde: locationService) }
        .onDisappear {
            if !mapaExpandido {
                cancelarGeocodificacion()
                ubicacion.cancelar()
            }
        }
        .onChange(of: scenePhase) { _, fase in
            // El diálogo de permiso puede volver inactiva la escena; la
            // lectura solo se cancela al pasar realmente a segundo plano.
            if fase == .background { ubicacion.cancelar() }
        }
        .alert(L.t("No se pudo guardar el lugar", "Unable to save place"), isPresented: $errorAlGuardar) {
            Button(L.t("Aceptar", "OK"), role: .cancel) { }
        } message: {
            Text(L.t("Los datos anteriores se conservaron. Revisa tus lugares en Guardado antes de volver a intentarlo.",
                     "Your previous data was preserved. Check your places in Saved before trying again."))
        }
    }

    // MARK: Campos
    private var campoNombre: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
        return layout {
            Image(systemName: iconoElegido)
                .font(.title2)
                .foregroundStyle(acento)
                .frame(minWidth: 52, minHeight: 52)
                .background(Color.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(L.t("Nombre del lugar", "Place name"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(L.t("Ej. Mi casa o mi trabajo", "e.g. My home or workplace"), text: $nombre, axis: .vertical)
                    .font(.body)
                    .foregroundStyle(Color.onSurface)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($campoActivo, equals: .nombre)
                    .onSubmit { campoActivo = nil }
                    .accessibilityLabel(L.t("Nombre del lugar", "Place name"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .background(superficie, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var campoDireccion: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("Dirección", "Address"))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "mappin")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField(L.t("Toca el mapa y la dirección se escribe sola",
                              "Tap the map and the address fills in"), text: $direccion, axis: .vertical)
                    .font(.body)
                    .foregroundStyle(Color.onSurface)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .focused($campoActivo, equals: .direccion)
                    .submitLabel(.done)
                    .onSubmit { campoActivo = nil }
                    .accessibilityLabel(L.t("Dirección del lugar", "Place address"))
                    .accessibilityHint(L.t("Escribe una dirección o elige un punto con las acciones del mapa", "Enter an address or choose a point using the map actions"))
                    .onChange(of: direccion) { _, _ in programarGeocodificacion() }
                if buscandoUbicacion {
                    ProgressView()
                        .accessibilityLabel(L.t("Buscando dirección", "Looking up address"))
                }
            }
        }
    }

    /// Estado de la ubicación: encontrada / buscando / ajustada a mano.
    @ViewBuilder
    private var estadoUbicacion: some View {
        if buscandoUbicacion {
            Label(L.t("Buscando la dirección…", "Looking up the address…"), systemImage: "magnifyingglass")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if direccionNoEncontrada {
            Label(L.t("No encontramos esa dirección — toca el mapa para ubicarla tú", "We could not find that address — tap the map to place it yourself"), systemImage: "exclamationmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(Color.appError)
        } else if coordElegida != nil {
            Label(L.t("Ubicación lista", "Location ready"), systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(acento)
        } else {
            Label(L.t("Toca el mapa para ubicar el lugar", "Tap the map to place the place"), systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Mapa
    private var mapaElegir: some View {
        MapaElegirLugar(
            colorPin: .appPrimary,
            coordenada: coordElegida,
            onTocar: { coord in
                ubicacion.interactuar()
                campoActivo = nil
                AppHaptics.impact(.light)
                confirmarSeleccionManual()
                withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
                    coordElegida = coord
                }
                escribirDireccionDesdeMapa(coord)
            },
            recentrarTrigger: recentrarTrigger,
            spanInicial: spanCercano,
            spanRecentrado: spanCercano,
            iconoPin: iconoElegido,
            centroCamara: ubicacion.centro,
            recentrarCamaraTrigger: ubicacion.revisionCamara,
            onInteraccion: { ubicacion.interactuar() },
            mostrarControles: true,
            onExpandir: {
                // Abre el mismo selector de ubicación a pantalla completa.
                AppHaptics.impact(.light)
                campoActivo = nil
                mapaExpandido = true
            }
        )
        .frame(height: 280)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20, style: .continuous))
        .fullScreenCover(isPresented: $mapaExpandido) {
            MapaElegirExpandido(
                coordenada: $coordElegida,
                ubicacion: ubicacion,
                iconoPin: iconoElegido,
                onTocar: { nueva in
                    ubicacion.interactuar()
                    AppHaptics.impact(.light)
                    confirmarSeleccionManual()
                    escribirDireccionDesdeMapa(nueva)
                },
                onCerrar: { mapaExpandido = false }
            )
        }
    }

    private var selectorCategoria: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.t("Categoría", "Category"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.onSurface)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading),
                                     count: dynamicTypeSize.isAccessibilitySize ? 1 : 2),
                      alignment: .leading, spacing: 8) {
                ForEach(CategoriaLugar.allCases) { opcion in
                    let seleccionada = categoria == opcion
                    Button {
                        campoActivo = nil
                        categoria = opcion
                        AppHaptics.selection()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: opcion.icono)
                                .font(.body)
                                .foregroundStyle(seleccionada ? acento : Color(uiColor: .secondaryLabel))
                                .frame(minWidth: 24)
                                .accessibilityHidden(true)
                            Text(opcion.label)
                                .font(.subheadline)
                                .foregroundStyle(Color.onSurface)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(acento)
                                .opacity(seleccionada ? 1 : 0)
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .background(superficie, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(seleccionada ? acento : .clear, lineWidth: 1.5)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(opcion.label)
                    .accessibilityAddTraits(seleccionada ? .isSelected : [])
                }
            }
        }
    }

    private var selectorIcono: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.t("Icono personalizado", "Custom icon"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.onSurface)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 80 : 52), spacing: 10)], spacing: 10) {
                ForEach(IconoLugar.opciones) { opcion in
                    let seleccionado = iconoElegido == opcion.id
                    Button {
                        campoActivo = nil
                        iconoPersonalizado = opcion.id
                        AppHaptics.selection()
                    } label: {
                        Image(systemName: opcion.id)
                            .font(.title3)
                            .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 80 : 56)
                            .foregroundStyle(seleccionado ? Color.onPrimaryFill : Color.onSurface)
                            .background(seleccionado ? Color.primaryFill : .clear,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(alignment: .topTrailing) {
                                if seleccionado {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .heavy))
                                        .foregroundStyle(Color.onPrimaryFill)
                                        .padding(6)
                                        .accessibilityHidden(true)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(opcion.nombre)
                    .accessibilityAddTraits(seleccionado ? .isSelected : [])
                }
            }
            .padding(12)
            .background(superficie, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    // MARK: Guardar
    private var puedeGuardar: Bool {
        !nombre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && coordElegida != nil && direccionValidada == direccion && !buscandoUbicacion
    }

    private var botonGuardar: some View {
        Button {
            let revision = revisionUbicacion
            SeniasPresenter.shared.ejecutarTrasVerSenia(clave: "guardado.guardar_lugar") {
                // La seña retrasa el guardado: comprobar de nuevo que el
                // punto pertenece a la dirección actual y la hoja sigue activa.
                guard revision == revisionUbicacion, puedeGuardar, let coord = coordElegida else { return }
                let guardado = onSave(LugarGuardado(
                    nombre: nombre.trimmingCharacters(in: .whitespacesAndNewlines),
                    direccion: direccion.isEmpty ? L.t("Sin dirección", "No address") : direccion,
                    categoria: categoria,
                    lat: coord.latitude,
                    lon: coord.longitude,
                    iconoPersonalizado: categoria == .personalizado ? iconoPersonalizado : nil
                ))
                guard guardado else {
                    AppHaptics.warning()
                    errorAlGuardar = true
                    return
                }
                AppHaptics.success()
                dismiss()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "bookmark")
                    .font(.body.weight(.semibold))
                Text(coordElegida == nil
                     ? L.t("Ubica el lugar para guardar", "Pin the place to save")
                     : L.signable("guardado.guardar_lugar", "Guardar lugar", "Save place"))
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(puedeGuardar ? Color.onPrimaryFill : Color.onSurfaceVariant)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(puedeGuardar ? Color.primaryFill : Color.surfaceContainerHigh)
            )
        }
        .buttonStyle(.plain)
        .disabled(!puedeGuardar)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: puedeGuardar)
        .seniable(puedeGuardar ? "guardado.guardar_lugar" : nil, conGesto: false)
    }

    // MARK: Geocodificación con debounce
    /// Espera 0.7 s a que el usuario deje de escribir y geocodifica.
    private func programarGeocodificacion() {
        // `direccion` también cambia cuando la LLENA el propio mapa. En ese
        // caso no hay nada que geocodificar: el punto ya está colocado y
        // `programarGeocodificacion` haría `coordElegida = nil`, borrando
        // justo el pin que el usuario acaba de marcar. Sin esta guarda, cada
        // toque en el mapa se desharía a sí mismo ~0.7 s después.
        guard !rellenoDesdeMapa else {
            rellenoDesdeMapa = false
            return
        }
        ubicacion.interactuar()
        cancelarGeocodificacion()
        direccionNoEncontrada = false
        coordElegida = nil
        direccionValidada = nil

        let direccionSolicitada = direccion
        let texto = direccionSolicitada.trimmingCharacters(in: .whitespacesAndNewlines)
        guard texto.count >= 5 else { return }

        let revision = revisionUbicacion
        buscandoUbicacion = true
        geocodeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled, revision == revisionUbicacion else { return }
            await geocodificar(texto, direccionSolicitada: direccionSolicitada, revision: revision)
        }
    }

    private func cancelarGeocodificacion() {
        revisionUbicacion = UUID()
        geocodeTask?.cancel()
        geocodeTask = nil
        geocoderActivo?.cancelGeocode()
        geocoderActivo = nil
        buscandoUbicacion = false
    }

    private func confirmarSeleccionManual() {
        cancelarGeocodificacion()
        direccionNoEncontrada = false
        direccionValidada = direccion
        // Si el relleno acaba de dejar el campo con un texto IDENTICAL al que
        // había, SwiftUI no dispara `onChange` y el flag se quedaría armado:
        // el próximo texto que escriba la persona se trataría como automático
        // y no se geocodificaría. Se limpia aquí, en el único punto por el que
        // pasa todo toque en el mapa.
        rellenoDesdeMapa = false
    }

    /// Rellena la dirección con la calle del punto tocado en el mapa.
    ///
    /// Usa la MISMA revisión que la geocodificación por texto (`geocodeTask` y
    /// `revisionUbicacion`) a propósito: si el usuario toca el mapa y luego
    /// escribe algo, la respuesta tardía del mapa no debe pisar lo que acaba
    /// de escribir. Un solo par de tarea+revisión para las dos vías evita
    /// justo esa carrera.
    private func escribirDireccionDesdeMapa(_ coord: CLLocationCoordinate2D) {
        cancelarGeocodificacion()
        let revision = revisionUbicacion
        // Texto tal como estaba al tocar: si al volver la respuesta el campo
        // ya no dice esto, el usuario lo editó y su versión gana.
        let textoAlTocar = direccion
        buscandoUbicacion = true
        geocodeTask = Task { @MainActor in
            let nombre = await Geocodificacion.nombreDelLugar(coord)
            guard !Task.isCancelled, revision == revisionUbicacion else { return }
            geocodeTask = nil
            buscandoUbicacion = false
            if direccion == textoAlTocar {
                // Se avisa del cambio automático ANTES de asignar: el
                // `onChange` del campo lee este flag al dispararse.
                rellenoDesdeMapa = true
                direccion = nombre
                direccionValidada = nombre
            }
        }
    }

    private func geocodificar(_ texto: String, direccionSolicitada: String, revision: UUID) async {
        let geocoder = CLGeocoder()
        geocoderActivo = geocoder
        let resultados: [CLPlacemark]? = await withCheckedContinuation { continuidad in
            geocoder.geocodeAddressString("\(texto), Trujillo, Perú") { placemarks, _ in
                continuidad.resume(returning: placemarks)
            }
        }
        guard !Task.isCancelled, revision == revisionUbicacion,
              direccionSolicitada == direccion else { return }
        geocoderActivo = nil
        geocodeTask = nil
        buscandoUbicacion = false

        if let coord = resultados?.first?.location?.coordinate {
            direccionNoEncontrada = false
            withAnimation(reduceMotion ? nil : .spring(response: 0.35)) {
                coordElegida = coord
                direccionValidada = direccionSolicitada
                recentrarTrigger += 1
            }
        } else {
            coordElegida = nil
            direccionValidada = nil
            direccionNoEncontrada = true
        }
    }
}
