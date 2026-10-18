//
//  GuardadoSheets.swift
//  RutaUTP
//
//  Sheets de la pestaña Guardado: detalle y alta de lugares y de líneas.
//
//  Estaban dentro de `GuardadoView.swift`, que llegaba a 1 477 líneas
//  mezclando la pantalla con sus cuatro formularios. Se separan aquí para que
//  el archivo de la vista contenga la vista.
//
//  NO se mueven los tipos compartidos con otras pantallas, que siguen en
//  `GuardadoView.swift`: `PressableCapsuleStyle` (lo usan Reportar, Publicar,
//  Mapa y Seguridad), `MapaElegirLugar` (Mapa) y `LugarDetailSheet` (Seguridad).
//

import SwiftUI
import MapKit
import CoreLocation
import Combine

// MARK: - Linea Detail Sheet (línea GTFS real)
struct LineaDetailSheet: View {
    let linea: RutaOpcion
    var onExplorar: () -> Void
    var onQuitar: () -> Bool
    @State private var errorAlQuitar = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Header
                let headerLayout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
                headerLayout {
                    ZStack {
                        Circle().fill(linea.colorLinea.opacity(0.15)).frame(width: 64, height: 64)
                        Text(linea.linea)
                            .font(.system(size: 18, weight: .heavy))
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                            .foregroundStyle(linea.colorLinea)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(linea.empresa)
                            .font(.headlineSm)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 4) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 12))
                            Text(linea.frecuenciaTexto)
                                .font(.labelCapsMd)
                                .appTracking(AppTracking.wideLabel)
                        }
                        .foregroundStyle(linea.colorLinea)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(linea.colorLinea.opacity(0.12)))
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text(L.t("RECORRIDO", "ROUTE"))
                        .font(.labelCapsMd)
                        .foregroundStyle(.onSurfaceVariant)
                        .appTracking(AppTracking.wideLabel)
                    Text(linea.recorridoLocalizado)
                        .font(.bodyMd)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(.onSurface)
                }

                // Datos del feed GTFS
                ViewThatFits(in: .horizontal) {
                    if dynamicTypeSize <= .large {
                        HStack(alignment: .top, spacing: 12) {
                            datosLinea
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    LazyVGrid(columns: columnasDatos, alignment: .center, spacing: 12) {
                        datosLinea
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.surfaceContainerLow))

                VStack(alignment: .leading, spacing: 8) {
                    Text(L.t("EXTREMOS", "END POINTS"))
                        .font(.labelCapsMd)
                        .foregroundStyle(.onSurfaceVariant)
                        .appTracking(AppTracking.wideLabel)
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "play.fill").font(.system(size: 10)).foregroundStyle(linea.colorLinea)
                        Text(linea.paradaInicio)
                            .font(.bodySm)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "flag.fill").font(.system(size: 10)).foregroundStyle(.red)
                        Text(linea.paradaFin)
                            .font(.bodySm)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(spacing: 10) {
                    Button {
                        onExplorar()
                    } label: {
                        HStack {
                            Image(systemName: "map.fill")
                            Text(L.t("Ver recorrido en el mapa", "View route on map"))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primaryFill))
                        .foregroundStyle(.onPrimaryFill)
                        .font(.headlineSm)
                    }
                    .buttonStyle(.plain)

                    Button {
                        if onQuitar() { dismiss() } else { errorAlQuitar = true }
                    } label: {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text(L.t("Quitar de guardados", "Remove from saved"))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.errorContainer))
                        .foregroundStyle(.onErrorContainer)
                        .font(.bodyMdMedium)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .alert(L.t("No se pudo quitar la línea", "Unable to remove line"), isPresented: $errorAlQuitar) {
            Button(L.t("Aceptar", "OK"), role: .cancel) {}
        } message: {
            Text(L.t("Los datos originales se conservan. Reintenta su lectura desde Guardado.",
                     "The original data has been preserved. Retry reading it from Saved."))
        }
    }


    private var columnasDatos: [GridItem] {
        let cantidad = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), alignment: .top), count: cantidad)
    }

    @ViewBuilder
    private var datosLinea: some View {
        dato(icono: "clock.fill", valor: linea.tiempoTexto, etiqueta: L.t("Viaje", "Trip"))
        dato(icono: "creditcard.fill", valor: linea.costo, etiqueta: L.t("Tarifa", "Fare"))
        dato(icono: "mappin.and.ellipse", valor: "\(linea.numParaderos)", etiqueta: L.t("Paraderos", "Stops"))
        dato(icono: "point.topleft.down.curvedto.point.bottomright.up",
             valor: FormatoNumero.decimal(linea.distanciaKm) + " km", etiqueta: L.t("Longitud", "Length"))
    }

    private func dato(icono: String, valor: String, etiqueta: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icono)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.appPrimary)
            Text(valor)
                .font(.headlineBody)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.onSurface)
            Text(etiqueta.uppercased())
                .font(.labelCapsSm)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.onSurfaceVariant)
                .appTracking(AppTracking.wideLabel)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

/// Una lectura puntual del servicio compartido. La cámara y el pin elegido
/// son estados distintos; una respuesta tardía no deshace un gesto del mapa.
@MainActor
private final class UbicacionMapaLugar: ObservableObject {
    @Published private(set) var centro: CLLocationCoordinate2D?
    @Published private(set) var revisionCamara = 0
    @Published private(set) var buscando = false
    @Published private(set) var aviso: String?
    private var tarea: Task<Void, Never>?
    private var revision = UUID()
    private var inicioSolicitado = false
    private var huboInteraccion = false

    deinit { tarea?.cancel() }

    func iniciar(desde service: LocationServiceProtocol) {
        guard !inicioSolicitado else { return }
        inicioSolicitado = true
        if service.authorizationStatus.isAuthorized,
           let lectura = (service as? LocationService)?.lastKnownLocation,
           UbicacionPuntual.esValida(lectura, ahora: Date(), antiguedadMaxima: 10) {
            centro = lectura.coordinate
            revisionCamara &+= 1
        }
        buscar(desde: service, automatico: true)
    }

    func buscar(desde service: LocationServiceProtocol, automatico: Bool = false) {
        guard !automatico || !huboInteraccion else { return }
        cancelar()
        buscando = true
        aviso = nil
        let solicitud = revision
        tarea = Task { @MainActor [weak self] in
            let lectura = await UbicacionPuntual.obtener(desde: service, antiguedadMaxima: 10)
            guard let self, !Task.isCancelled, self.revision == solicitud else { return }
            self.tarea = nil
            self.buscando = false
            if let lectura {
                self.centro = lectura.coordinate
                self.revisionCamara &+= 1
            } else {
                self.aviso = service.authorizationStatus.isDenied
                    ? L.t("Activa la ubicación de la app en Ajustes para centrar el mapa.", "Enable the app's location access in Settings to center the map.")
                    : L.t("No pudimos obtener tu ubicación. Vuelve a tocar la flecha.", "We couldn't get your location. Tap the arrow again.")
            }
        }
    }

    func interactuar() {
        huboInteraccion = true
        cancelar()
    }

    func cancelar() {
        revision = UUID()
        tarea?.cancel()
        tarea = nil
        if buscando { buscando = false }
    }
}

private struct BotonUbicacionLugar: View {
    @ObservedObject var ubicacion: UbicacionMapaLugar
    let locationService: LocationServiceProtocol

    var body: some View {
        Button {
            AppHaptics.impact(.light)
            ubicacion.buscar(desde: locationService)
        } label: {
            Group {
                if ubicacion.buscando {
                    ProgressView().tint(Color.onPrimaryFill)
                } else {
                    Image(systemName: "location.fill").font(.body.weight(.semibold))
                }
            }
            .foregroundStyle(Color.onPrimaryFill)
            .frame(width: 44, height: 44)
            .background(Color.primaryFill, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(ubicacion.buscando)
        .accessibilityLabel(ubicacion.buscando
                            ? L.t("Buscando tu ubicación…", "Finding your location…")
                            : L.t("Mi ubicación", "My location"))
        .accessibilityHint(L.t("Centra el mapa sin cambiar el lugar marcado", "Centers the map without changing the marked place"))
    }
}

// MARK: - Add Lugar sheet (con mapa en vivo)
struct AddLugarSheet: View {
    let locationService: LocationServiceProtocol
    var onSave: (LugarGuardado) -> Bool
    @Environment(\.dismiss) private var dismiss
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
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L.t("Ubicación", "Location"))
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        VStack(alignment: .leading, spacing: 12) {
                            mapaElegir
                            campoDireccion
                            estadoUbicacion
                            if let aviso = ubicacion.aviso {
                                Text(aviso).font(.caption).foregroundStyle(Color.onSurfaceVariant)
                            }
                        }
                        .padding(12)
                        .background(Color.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 24))
                    }
                    campoNombre
                    selectorCategoria
                    if categoria == .personalizado { selectorIcono }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.appBackground)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                botonGuardar
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.appBackground)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Color.outlineVariant.opacity(0.2)).frame(height: 0.5)
                    }
            }
            .navigationTitle(L.t("Añadir lugar", "Add place"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBackground, for: .navigationBar)
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
        .tint(.appPrimary)
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
        VStack(alignment: .leading, spacing: 12) {
            Text(L.t("Tu lugar", "Your place"))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(spacing: 14))
            layout {
                Image(systemName: iconoElegido)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.onPrimaryFill)
                    .frame(width: 56, height: 56)
                    .background(Color.primaryFill, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(L.t("Nombre del lugar", "Place name"))
                        .font(.caption)
                        .foregroundStyle(Color.onSurfaceVariant)
                    TextField(L.t("Ej. Mi casa o mi trabajo", "e.g. My home or workplace"), text: $nombre, axis: .vertical)
                        .font(.body.weight(.semibold))
                        .textFieldStyle(.plain)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($campoActivo, equals: .nombre)
                        .onSubmit { campoActivo = nil }
                        .accessibilityLabel(L.t("Nombre del lugar", "Place name"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .background(Color.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private var campoDireccion: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("Dirección", "Address"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.onSurfaceVariant)
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.body)
                    .foregroundStyle(.onSurfaceVariant)
                TextField(L.t("Toca el mapa y la dirección se escribe sola",
                              "Tap the map and the address fills in"), text: $direccion, axis: .vertical)
                    .font(.bodySm)
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
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.surfaceContainerLow))
        }
    }

    /// Estado de la ubicación: encontrada / buscando / ajustada a mano.
    @ViewBuilder
    private var estadoUbicacion: some View {
        if buscandoUbicacion {
            Label(L.t("Buscando la dirección…", "Looking up the address…"), systemImage: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.onSurfaceVariant)
        } else if direccionNoEncontrada {
            Label(L.t("No encontramos esa dirección — toca el mapa para ubicarla tú", "We could not find that address — tap the map to place it yourself"), systemImage: "exclamationmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Color.appError)
        } else if coordElegida != nil {
            Label(L.t("Ubicación lista", "Location ready"), systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.appPrimary)
        } else {
            Label(L.t("Toca el mapa para ubicar el lugar", "Tap the map to place the place"), systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.onSurfaceVariant)
        }
    }

    // MARK: Mapa
    private var mapaElegir: some View {
        ZStack(alignment: .bottom) {
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
                onInteraccion: { ubicacion.interactuar() }
            )

            Label(L.t("Toca el mapa para mover el pin", "Tap the map to move the pin"), systemImage: "hand.tap.fill")
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.onSurface)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(12)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 8) {
                botonExpandirMapa
                BotonUbicacionLugar(ubicacion: ubicacion, locationService: locationService)
            }
            .padding(8)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.outlineVariant.opacity(0.4), lineWidth: 1)
        )
        .fullScreenCover(isPresented: $mapaExpandido) {
            MapaElegirExpandido(
                coordenada: $coordElegida,
                ubicacion: ubicacion,
                locationService: locationService,
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

    /// Abre el mismo selector de ubicación a pantalla completa.
    private var botonExpandirMapa: some View {
        Button {
            AppHaptics.impact(.light)
            campoActivo = nil
            mapaExpandido = true
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(.onSurface)
                .frame(width: 44, height: 44)
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(
                    Circle().stroke(Color.outlineVariant.opacity(0.4), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L.t("Expandir mapa", "Expand map"))
    }

    private var selectorCategoria: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.t("Categoría", "Category"))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize
                      ? [GridItem(.flexible())]
                      : [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                ForEach(CategoriaLugar.allCases) { opcion in
                    let seleccionada = categoria == opcion
                    Button {
                        campoActivo = nil
                        categoria = opcion
                        AppHaptics.selection()
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: opcion.icono)
                                .font(.title3.weight(.semibold))
                                .accessibilityHidden(true)
                            Text(opcion.label)
                                .font(.caption.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 68)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 12)
                        .foregroundStyle(seleccionada ? Color.onPrimaryContainer : Color.onSurface)
                        .background(seleccionada ? Color.primaryContainer : Color.surfaceContainerLow,
                                    in: RoundedRectangle(cornerRadius: 16))
                        .overlay(alignment: .topTrailing) {
                            if seleccionada {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.onPrimaryContainer)
                                    .padding(7)
                                    .accessibilityHidden(true)
                            }
                        }
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
                .font(.headline)
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
                            .font(.title2.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 80 : 56)
                            .foregroundStyle(seleccionado ? Color.onPrimaryFill : Color.onSurface)
                            .background(seleccionado ? Color.primaryFill : Color.surfaceContainerLow,
                                        in: RoundedRectangle(cornerRadius: 16))
                            .overlay(alignment: .topTrailing) {
                                if seleccionado {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .heavy))
                                        .foregroundStyle(Color.onPrimaryFill)
                                        .padding(6)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(opcion.nombre)
                    .accessibilityAddTraits(seleccionado ? .isSelected : [])
                }
            }
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
                Image(systemName: "bookmark.fill")
                    .font(.body.weight(.semibold))
                Text(coordElegida == nil
                     ? L.t("Ubica el lugar para guardar", "Pin the place to save")
                     : L.signable("guardado.guardar_lugar", "Guardar lugar", "Save place"))
                    .font(.headlineSm)
            }
            .foregroundStyle(puedeGuardar ? Color.onPrimaryFill : Color.onSurfaceVariant)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(puedeGuardar ? Color.primaryFill : Color.surfaceContainerHigh)
            )
        }
        .buttonStyle(PressableCapsuleStyle())
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

// MARK: - Mapa expandido para elegir ubicación (desde AddLugarSheet)
/// El mismo selector `MapaElegirLugar` a pantalla completa: comparte la
/// coordenada con el formulario vía binding y sincroniza cada toque.
private struct MapaElegirExpandido: View {
    @Binding var coordenada: CLLocationCoordinate2D?
    @ObservedObject var ubicacion: UbicacionMapaLugar
    let locationService: LocationServiceProtocol
    var iconoPin: String = "mappin.circle.fill"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Se dispara en cada toque del mapa, después de actualizar la coordenada.
    /// Recibe la coordenada tocada para poder geocodificarla.
    var onTocar: (CLLocationCoordinate2D) -> Void
    var onCerrar: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            MapaElegirLugar(
                colorPin: .appPrimary,
                coordenada: coordenada,
                onTocar: { coord in
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        coordenada = coord
                    }
                    onTocar(coord)
                },
                spanInicial: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006),
                spanRecentrado: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006),
                iconoPin: iconoPin,
                centroCamara: ubicacion.centro,
                recentrarCamaraTrigger: ubicacion.revisionCamara,
                onInteraccion: { ubicacion.interactuar() }
            )
            .ignoresSafeArea()

            VStack {
                barraSuperior
                Spacer()
                HStack {
                    Spacer()
                    BotonUbicacionLugar(ubicacion: ubicacion, locationService: locationService)
                }
                .padding(.horizontal, 20)
                if let aviso = ubicacion.aviso {
                    Text(aviso)
                        .font(.footnote)
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 20)
                }
                pie
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: coordenada == nil)
        }
    }

    private var barraSuperior: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "mappin.circle.fill")
                    .font(.body.weight(.semibold))
                Text(L.t("Elige la ubicación", "Pick the location"))
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Capsule().fill(Color.black.opacity(0.55)))

            Spacer()

            Button {
                onCerrar()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.onSurface)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.ultraThinMaterial))
                    .overlay(
                        Circle().stroke(Color.outlineVariant.opacity(0.4), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.t("Cerrar", "Close"))
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    /// Abajo: instrucción mientras no haya pin; botón de confirmar cuando sí.
    @ViewBuilder
    private var pie: some View {
        if coordenada != nil {
            Button {
                onCerrar()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                    Text(L.t("Usar esta ubicación", "Use this location"))
                        .font(.headlineSm)
                }
                .foregroundStyle(.onPrimaryFill)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.primaryFill)
                        .shadow(color: .appPrimary.opacity(0.35), radius: 12, x: 0, y: 6)
                )
            }
            .buttonStyle(PressableCapsuleStyle())
            .padding(.horizontal, 20)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "hand.tap.fill")
                    .font(.caption.weight(.semibold))
                Text(L.t("Toca el mapa para ubicar el lugar", "Tap the map to pin the location"))
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.black.opacity(0.55)))
        }
    }
}

// MARK: - Add Linea sheet (selector de líneas GTFS reales)
struct AddLineaSheet: View {
    let catalogo: [RutaOpcion]
    /// true mientras el feed no se ha intentado cargar. Sin esto, un catálogo
    /// vacío se mostraba siempre como "Cargando…", también cuando el feed
    /// había fallado, sin salida ni explicación.
    let cargando: Bool
    var errorCatalogo: FalloCargaGTFS? = nil
    var onRetry: () -> Void = {}
    let yaGuardadas: Set<String>
    var onSave: (RutaOpcion) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var texto: String = ""
    @State private var errorAlGuardar = false

    private var filtradas: [RutaOpcion] {
        let t = texto.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return catalogo }
        return catalogo.filter {
            $0.linea.localizedCaseInsensitiveContains(t)
            || $0.empresa.localizedCaseInsensitiveContains(t)
            || $0.recorrido.localizedCaseInsensitiveContains(t)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(L.t("Guardar línea", "Save line"))
                    .font(.headlineMd)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.onSurfaceVariant)
                    TextField(L.t("Buscar línea, empresa o avenida", "Search line, company or avenue"), text: $texto)
                        .font(.bodySm)
                        .autocorrectionDisabled()
                        .accessibilityLabel(L.t("Buscar línea para guardar", "Search for a line to save"))
                    if !texto.isEmpty {
                        Button {
                            texto = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.onSurfaceVariant.opacity(0.6))
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L.t("Borrar búsqueda", "Clear search"))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.surfaceContainerLow))

                if cargando {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text(L.t("Cargando líneas oficiales…", "Loading official routes…"))
                            .font(.bodySm)
                            .foregroundStyle(.onSurfaceVariant)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorCatalogo {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 26))
                            .foregroundStyle(.onSurfaceVariant)
                        Text(error.mensajeUsuario)
                            .font(.bodySm)
                            .foregroundStyle(.onSurfaceVariant)
                            .multilineTextAlignment(.center)
                        Button(L.t("Reintentar", "Try again"), action: onRetry)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if catalogo.isEmpty {
                    Text(TransporteApp.rutasUTPPendientes ? TransporteApp.mensajePendiente
                         : L.t("El catálogo no contiene líneas.", "The catalog contains no routes."))
                        .font(.bodySm)
                        .foregroundStyle(.onSurfaceVariant)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(20)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 8) {
                            ForEach(filtradas) { ruta in
                                filaCatalogo(ruta)
                            }
                            if filtradas.isEmpty {
                                Text(L.t("Sin coincidencias para ", "No matches for ") + "“\(texto)”")
                                    .font(.bodySm)
                                    .foregroundStyle(.onSurfaceVariant)
                                    .padding(.vertical, 24)
                            }
                        }
                        .padding(.bottom, 12)
                    }
                }
            }
            .padding(20)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("Cancelar", "Cancel")) { dismiss() }
                }
            }
        }
        .alert(L.t("No se pudo guardar la línea", "Unable to save line"), isPresented: $errorAlGuardar) {
            Button(L.t("Aceptar", "OK"), role: .cancel) {}
        } message: {
            Text(L.t("Los datos originales se conservan. Reintenta su lectura desde Guardado.",
                     "The original data has been preserved. Retry reading it from Saved."))
        }
    }

    private func filaCatalogo(_ ruta: RutaOpcion) -> some View {
        let guardada = yaGuardadas.contains(ruta.id)
        return Button {
            guard !guardada else { return }
            guard onSave(ruta) else {
                errorAlGuardar = true
                return
            }
            AppHaptics.success()
            dismiss()
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(ruta.colorLinea)
                    .frame(width: 4, height: 42)
                ZStack {
                    Circle().fill(ruta.colorLinea.opacity(0.14)).frame(width: 38, height: 38)
                    Text(ruta.linea)
                        .font(.system(size: 12, weight: .heavy))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .foregroundStyle(ruta.colorLinea)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(ruta.empresa)
                        .font(.bodyMdMedium)
                        .foregroundStyle(.onSurface)
                        .lineLimit(1)
                    Text(ruta.recorridoLocalizado)
                        .font(.bodySm)
                        .foregroundStyle(.onSurfaceVariant)
                        .lineLimit(1)
                }
                Spacer()
                if guardada {
                    Label(L.t("Guardada", "Saved"), systemImage: "checkmark.circle.fill")
                        .font(.labelCapsMd)
                        .foregroundStyle(.onSurfaceVariant)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.appPrimary)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.surfaceContainerLowest)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.outlineVariant.opacity(0.3), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(guardada)
        .opacity(guardada ? 0.55 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.t("Línea ", "Line ") + ruta.linea + ", " + ruta.empresa)
        .accessibilityValue(ruta.recorridoLocalizado + (guardada ? L.t(", guardada", ", saved") : ""))
        .accessibilityHint(guardada ? "" : L.t("Añade esta línea a Guardado", "Adds this line to Saved"))
        .accessibilityAddTraits(guardada ? .isSelected : [])
    }
}
