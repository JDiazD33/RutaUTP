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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.self) private var entorno
    @ScaledMetric(relativeTo: .title) private var tamanoInsignia = 76

    private var acento: Color { colorScheme == .dark ? .primaryFixed : .appPrimary }
    private var superficie: Color { Color(uiColor: .secondarySystemGroupedBackground) }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    resumen
                    datosDelViaje
                    paraderos
                    quitarDeGuardados
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle(L.t("Línea guardada", "Saved line"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appSurface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .tint(acento)
                    .accessibilityLabel(L.t("Cerrar", "Close"))
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                verRecorrido
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.appSurface)
                    .overlay(alignment: .top) { Divider() }
            }
        }
        .alert(L.t("No se pudo quitar la línea", "Unable to remove line"), isPresented: $errorAlQuitar) {
            Button(L.t("Aceptar", "OK"), role: .cancel) {}
        } message: {
            Text(L.t("Los datos originales se conservan. Reintenta su lectura desde Guardado.",
                     "The original data has been preserved. Retry reading it from Saved."))
        }
    }

    private var resumen: some View {
        VStack(alignment: .leading, spacing: 16) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
            layout {
                insignia

                VStack(alignment: .leading, spacing: 5) {
                    Text(linea.empresa)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.onSurface)
                        .accessibilityAddTraits(.isHeader)
                    Text(L.t("Línea ", "Line ") + linea.lineaConLetra)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(linea.recorridoLocalizado)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    tituloFrecuencia
                    Spacer(minLength: 8)
                    valorFrecuencia
                }
                VStack(alignment: .leading, spacing: 6) {
                    tituloFrecuencia
                    valorFrecuencia
                }
            }
        }
        .padding(20)
        .background(superficie, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var insignia: some View {
        VStack(spacing: 2) {
            if linea.letraTransporte.isEmpty {
                Image(systemName: "bus.fill")
                    .font(.title)
            } else {
                Text(L.t("Letra", "Letter"))
                    .font(.caption2.weight(.medium))
                Text(linea.letraTransporte)
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .foregroundStyle(colorTextoLetra)
        .padding(8)
        .frame(width: tamanoInsignia, height: tamanoInsignia)
        .background(linea.colorLinea, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityHidden(true)
    }

    private var colorTextoLetra: Color {
        let color = linea.colorLinea.resolve(in: entorno)
        let luminancia = 0.2126 * color.linearRed + 0.7152 * color.linearGreen + 0.0722 * color.linearBlue
        let contrasteNegro = (luminancia + 0.05) / 0.05
        let contrasteBlanco = 1.05 / (luminancia + 0.05)
        return contrasteNegro >= contrasteBlanco ? .black : .white
    }

    private var tituloFrecuencia: some View {
        Label(L.t("Frecuencia", "Frequency"), systemImage: "clock")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var valorFrecuencia: some View {
        Text(linea.frecuenciaTexto)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.onSurface)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var datosDelViaje: some View {
        LazyVGrid(columns: columnasDatos, alignment: .leading, spacing: 20) {
            datosLinea
        }
        .padding(20)
        .background(superficie, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var columnasDatos: [GridItem] {
        let cantidad = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), alignment: .leading), count: cantidad)
    }

    @ViewBuilder
    private var datosLinea: some View {
        dato(icono: "clock", valor: linea.tiempoTexto, etiqueta: L.t("Tiempo de viaje", "Travel time"))
        dato(icono: "banknote", valor: linea.costo, etiqueta: L.t("Pasaje", "Fare"))
        dato(icono: "mappin", valor: "\(linea.numParaderos)", etiqueta: L.t("Paraderos", "Stops"))
        dato(icono: "point.topleft.down.curvedto.point.bottomright.up",
             valor: FormatoNumero.decimal(linea.distanciaKm) + " km", etiqueta: L.t("Distancia", "Distance"))
    }

    private func dato(icono: String, valor: String, etiqueta: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(etiqueta, systemImage: icono)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(valor)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(Color.onSurface)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var paraderos: some View {
        VStack(spacing: 0) {
            paradero(icono: "circle.circle", titulo: L.t("Paradero inicial", "First stop"),
                     nombre: linea.paradaInicioVisible)
            Divider().padding(.leading, 68)
            paradero(icono: "flag.checkered", titulo: L.t("Paradero final", "Last stop"),
                     nombre: linea.paradaFinVisible)
        }
        .background(superficie, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func paradero(icono: String, titulo: String, nombre: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icono)
                .font(.body.weight(.medium))
                .foregroundStyle(acento)
                .frame(minWidth: 36, minHeight: 36)
                .background(Color.surfaceContainerLow, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(titulo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(nombre)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.onSurface)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .accessibilityElement(children: .combine)
    }

    private var quitarDeGuardados: some View {
        Button(role: .destructive) {
            if onQuitar() { dismiss() } else { errorAlQuitar = true }
        } label: {
            Label(L.t("Quitar de guardados", "Remove from saved"), systemImage: "trash")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(minHeight: 52)
                .background(superficie, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(uiColor: .systemRed))
    }

    private var verRecorrido: some View {
        Button {
            onExplorar()
        } label: {
            Label(L.t("Ver recorrido en el mapa", "View route on map"), systemImage: "map")
                .font(.headline)
                .foregroundStyle(Color.onPrimaryFill)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(Color.primaryFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
    @Environment(\.colorScheme) private var colorScheme

    private var acento: Color { colorScheme == .dark ? .primaryFixed : .appPrimary }

    var body: some View {
        Button {
            AppHaptics.impact(.light)
            ubicacion.buscar(desde: locationService)
        } label: {
            Group {
                if ubicacion.buscando {
                    ProgressView().tint(acento)
                } else {
                    Image(systemName: "location.fill").font(.body.weight(.semibold))
                }
            }
            .foregroundStyle(acento)
            .frame(minWidth: 44, minHeight: 44)
            .background(.regularMaterial, in: Circle())
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
            onInteraccion: { ubicacion.interactuar() }
        )
        .frame(height: 280)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20, style: .continuous))
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 8) {
                botonExpandirMapa
                BotonUbicacionLugar(ubicacion: ubicacion, locationService: locationService)
            }
            .padding(12)
        }
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
                .foregroundStyle(acento)
                .frame(minWidth: 44, minHeight: 44)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L.t("Expandir mapa", "Expand map"))
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
                    .padding(.bottom, 12)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: coordenada == nil)
        }
    }

    private var barraSuperior: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "mappin.circle.fill")
                    .font(.body.weight(.semibold))
                    .accessibilityHidden(true)
                Text(L.t("Elige la ubicación", "Pick the location"))
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Color.onSurface)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            Spacer()

            Button {
                onCerrar()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.onSurface)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(.regularMaterial, in: Circle())
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
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(Color.onPrimaryFill)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(Color.primaryFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "hand.tap.fill")
                    .font(.subheadline)
                    .accessibilityHidden(true)
                Text(L.t("Toca el mapa para ubicar el lugar", "Tap the map to pin the location"))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Color.onSurface)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Add Linea sheet (selector de líneas GTFS reales)
struct AddLineaSheet: View {
    let catalogo: [RutaOpcion]
    /// Distingue carga, fallo y catálogo vacío sin ocultar los errores del feed.
    let cargando: Bool
    var errorCatalogo: FalloCargaGTFS? = nil
    var onRetry: () -> Void = {}
    let yaGuardadas: Set<String>
    var onSave: (RutaOpcion) -> Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var texto = ""
    @State private var errorAlGuardar = false
    @FocusState private var busquedaEnfocada: Bool

    private var filtradas: [RutaOpcion] {
        let consulta = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !consulta.isEmpty else { return catalogo }
        return catalogo.filter {
            $0.linea.localizedCaseInsensitiveContains(consulta)
            || $0.empresa.localizedCaseInsensitiveContains(consulta)
            || $0.recorrido.localizedCaseInsensitiveContains(consulta)
        }
    }

    var body: some View {
        let rutas = filtradas
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                encabezado(total: rutas.count)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                buscador
                    .padding(.horizontal, 20)
                resultados(rutas)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle(L.t("Añadir línea", "Add line"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("Cancelar", "Cancel")) { dismiss() }
                }
            }
        }
        .tint(Color.appAccent)
        .alert(L.t("No se pudo guardar la línea", "Unable to save line"), isPresented: $errorAlGuardar) {
            Button(L.t("Aceptar", "OK"), role: .cancel) {}
        } message: {
            Text(L.t("Los datos originales se conservan. Reintenta su lectura desde Guardado.",
                     "The original data has been preserved. Retry reading it from Saved."))
        }
    }

    private func encabezado(total: Int) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return layout {
            VStack(alignment: .leading, spacing: 4) {
                Text(L.t("Elige tu ruta", "Pick your route"))
                    .font(.headlineSm)
                    .foregroundStyle(Color.onSurface)
                    .accessibilityAddTraits(.isHeader)
                Text(L.t("Toca una línea para guardarla.", "Tap a line to save it."))
                    .font(.bodySm)
                    .foregroundStyle(Color.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !cargando, errorCatalogo == nil, !catalogo.isEmpty {
                Text("\(total)")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.onPrimaryContainer)
                    .padding(12)
                    .background(Color.primaryContainer, in: Capsule())
                    .accessibilityLabel(L.f("{0} rutas encontradas", "{0} routes found", ["\(total)"]))
            }
        }
    }

    private var buscador: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.onSurfaceVariant)
                .accessibilityHidden(true)
            TextField(L.t("Buscar línea, empresa o avenida", "Search line, company or avenue"), text: $texto)
                .font(.bodySm)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .focused($busquedaEnfocada)
                .onSubmit { busquedaEnfocada = false }
                .accessibilityLabel(L.t("Buscar línea para guardar", "Search for a line to save"))
            if !texto.isEmpty {
                Button { texto = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.onSurfaceVariant)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.t("Borrar búsqueda", "Clear search"))
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .frame(minHeight: 52)
        .background(Color.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.outlineVariant.opacity(0.4), lineWidth: 1)
        }
    }

    private func resultados(_ rutas: [RutaOpcion]) -> some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 14) {
                if cargando {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(L.t("Cargando rutas…", "Loading routes…"))
                            .font(.bodySm)
                            .foregroundStyle(Color.onSurfaceVariant)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                } else if let error = errorCatalogo {
                    VStack(spacing: 12) {
                        estado(icono: "exclamationmark.triangle", mensaje: error.mensajeUsuario)
                        Button(L.t("Reintentar", "Try again"), action: onRetry)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.onPrimaryFill)
                            .padding(.horizontal, 20)
                            .frame(minHeight: 44)
                            .background(Color.primaryFill, in: Capsule())
                            .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else if catalogo.isEmpty {
                    estado(icono: "bus", mensaje: TransporteApp.rutasUTPPendientes
                           ? TransporteApp.mensajePendiente
                           : L.t("El catálogo no contiene líneas.", "The catalog contains no routes."))
                } else if rutas.isEmpty {
                    estado(icono: "magnifyingglass", mensaje:
                            L.t("Sin coincidencias para ", "No matches for ") + "“\(texto)”")
                } else {
                    ForEach(rutas) { ruta in
                        filaCatalogo(ruta)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func estado(icono: String, mensaje: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icono)
                .font(.title)
                .accessibilityHidden(true)
            Text(mensaje)
                .font(.bodySm)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.onSurfaceVariant)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private func filaCatalogo(_ ruta: RutaOpcion) -> some View {
        let guardada = yaGuardadas.contains(ruta.id)
        return Button {
            guard !guardada else { return }
            busquedaEnfocada = false
            guard onSave(ruta) else {
                errorAlGuardar = true
                return
            }
            AppHaptics.success()
            dismiss()
        } label: {
            RutaOpcionCard(ruta: ruta, accesorio: guardada ? .guardada : .añadir)
        }
        .buttonStyle(.plain)
        .disabled(guardada)
        .accessibilityHint(guardada ? "" : L.t("Añade esta línea a Guardado", "Adds this line to Saved"))
        .accessibilityAddTraits(guardada ? .isSelected : [])
    }
}
