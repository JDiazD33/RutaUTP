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

// MARK: - Linea Detail Sheet (línea GTFS real)
struct LineaDetailSheet: View {
    let linea: RutaOpcion
    var onExplorar: () -> Void
    var onQuitar: () -> Void
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
                    Text(linea.recorrido)
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
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.appPrimary))
                        .foregroundStyle(.white)
                        .font(.headlineSm)
                    }
                    .buttonStyle(.plain)

                    Button {
                        onQuitar()
                        dismiss()
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
             valor: String(format: "%.1f km", linea.distanciaKm), etiqueta: L.t("Longitud", "Length"))
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

// MARK: - Add Lugar sheet (con mapa en vivo)
struct AddLugarSheet: View {
    var onSave: (LugarGuardado) -> Bool
    @Environment(\.dismiss) private var dismiss

    @State private var nombre: String = ""
    @State private var direccion: String = ""
    @State private var categoria: CategoriaLugar = .otro

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
    @State private var ajusteManual = false
    @State private var mapaExpandido = false
    @State private var errorAlGuardar = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    // Con el mapa arriba, el rótulo ya no necesita pedir que se
                    // ubique: el gesto siguiente es tocarlo, y el propio mapa
                    // lo dice ("Toca el mapa para ubicar el lugar"). Este
                    // encabezado nombra la acción, no repite la instrucción.
                    Text(L.signable("guardado.guardar_lugar", "Guardar lugar", "Save place"))
                        .font(.headlineMd)
                        .seniable(coordElegida == nil ? nil : "guardado.guardar_lugar")

                    // Orden: el MAPA primero. El lugar se elige mirando el
                    // mapa, no escribiendo; la dirección sale sola de ahí.
                    // Antes el campo iba primero y el mapa al final, que
                    // obligaba a escribir para poder ver dónde era.
                    mapaElegir
                    campoDireccion
                    estadoUbicacion
                    campoNombre
                    selectorCategoria

                    botonGuardar
                }
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("Cancelar", "Cancel")) {
                        cancelarGeocodificacion()
                        dismiss()
                    }
                }
            }
        }
        .onDisappear { cancelarGeocodificacion() }
        .alert(L.t("No se pudo guardar el lugar", "Unable to save place"), isPresented: $errorAlGuardar) {
            Button(L.t("Aceptar", "OK"), role: .cancel) { }
        } message: {
            Text(L.t("Los datos anteriores se conservaron. Revisa tus lugares en Guardado antes de volver a intentarlo.",
                     "Your previous data was preserved. Check your places in Saved before trying again."))
        }
    }

    // MARK: Campos
    private var campoNombre: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("NOMBRE", "NAME"))
                .font(.labelCapsMd)
                .foregroundStyle(.onSurfaceVariant)
                .appTracking(AppTracking.wideLabel)
            TextField(L.t("Ej. Mi trabajo", "e.g. My job"), text: $nombre)
                .textFieldStyle(.plain)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.surfaceContainerLow))
        }
    }

    private var campoDireccion: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("DIRECCIÓN", "ADDRESS"))
                .font(.labelCapsMd)
                .foregroundStyle(.onSurfaceVariant)
                .appTracking(AppTracking.wideLabel)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.onSurfaceVariant)
                TextField(L.t("Toca el mapa y la dirección se escribe sola",
                              "Tap the map and the address fills in"), text: $direccion)
                    .font(.bodySm)
                    .autocorrectionDisabled()
                    .onChange(of: direccion) { _, _ in programarGeocodificacion() }
                if buscandoUbicacion {
                    ProgressView().scaleEffect(0.8)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.surfaceContainerLow))
        }
    }

    /// Estado de la ubicación: encontrada / buscando / ajustada a mano.
    @ViewBuilder
    private var estadoUbicacion: some View {
        if ajusteManual {
            Label(L.t("Ubicación ajustada en el mapa", "Location adjusted on the map"), systemImage: "hand.tap.fill")
                .font(.bodySm)
                .foregroundStyle(.appPrimary)
        } else if buscandoUbicacion {
            Label(L.t("Buscando la dirección…", "Looking up the address…"), systemImage: "magnifyingglass")
                .font(.bodySm)
                .foregroundStyle(.onSurfaceVariant)
        } else if direccionNoEncontrada {
            Label(L.t("No encontramos esa dirección — toca el mapa para ubicarla tú", "We could not find that address — tap the map to place it yourself"), systemImage: "exclamationmark.circle.fill")
                .font(.bodySm)
                .foregroundStyle(.orange)
        } else if ajusteManual, !buscandoUbicacion {
            Label(direccion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  ? L.t("Toca el mapa para escribir la dirección", "Tap the map to fill in the address")
                  : L.t("Dirección del punto marcado ✓", "Address of the marked spot ✓"),
                  systemImage: direccion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  ? "hand.tap.fill" : "checkmark.circle.fill")
                .font(.bodySm)
                .foregroundStyle(direccion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                 ? Color.onSurfaceVariant : .green)
        } else if coordElegida != nil {
            Label(L.t("Ubicación encontrada ✓", "Location found ✓"), systemImage: "checkmark.circle.fill")
                .font(.bodySm)
                .foregroundStyle(.green)
        } else {
            Label(L.t("Toca el mapa para ubicar el lugar", "Tap the map to place the place"), systemImage: "info.circle")
                .font(.bodySm)
                .foregroundStyle(.onSurfaceVariant)
        }
    }

    // MARK: Mapa
    private var mapaElegir: some View {
        ZStack(alignment: .bottom) {
            MapaElegirLugar(
                coordenada: coordElegida,
                onTocar: { coord in
                    AppHaptics.impact(.light)
                    confirmarSeleccionManual()
                    withAnimation(.spring(response: 0.3)) {
                        coordElegida = coord
                    }
                    escribirDireccionDesdeMapa(coord)
                },
                recentrarTrigger: recentrarTrigger
            )

            HStack(spacing: 6) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 11, weight: .bold))
                Text(L.t("Toca el mapa para mover el pin", "Tap the map to move the pin"))
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.black.opacity(0.55)))
            .padding(.bottom, 10)
        }
        // Con el mapa al frente del formulario pasa a ser la pieza principal
        // de la pantalla: 210 pt obligaban a apretar los dedos para colocar un
        // punto con precisión, que es justo lo contrario de lo que se hace aquí.
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .topTrailing) { botonExpandirMapa }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.outlineVariant.opacity(0.4), lineWidth: 1)
        )
        .fullScreenCover(isPresented: $mapaExpandido) {
            MapaElegirExpandido(
                coordenada: $coordElegida,
                onTocar: { nueva in
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
            mapaExpandido = true
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.onSurface)
                .frame(width: 32, height: 32)
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(
                    Circle().stroke(Color.outlineVariant.opacity(0.4), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .padding(8)
        .accessibilityLabel(L.t("Expandir mapa", "Expand map"))
    }

    private var selectorCategoria: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("CATEGORÍA", "CATEGORY"))
                .font(.labelCapsMd)
                .foregroundStyle(.onSurfaceVariant)
                .appTracking(AppTracking.wideLabel)
            Picker("Categoría", selection: $categoria) {
                ForEach(CategoriaLugar.allCases) { c in
                    Text(c.label).tag(c)
                }
            }
            .pickerStyle(.menu)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.surfaceContainerLow))
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
                    nombre: nombre.trimmingCharacters(in: .whitespaces),
                    direccion: direccion.isEmpty ? L.t("Sin dirección", "No address") : direccion,
                    categoria: categoria,
                    lat: coord.latitude,
                    lon: coord.longitude
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
                Image(systemName: coordElegida == nil ? "location.slash.fill" : "mappin.and.ellipse")
                    .font(.system(size: 16, weight: .bold))
                Text(coordElegida == nil
                     ? L.t("Ubica el lugar para guardar", "Pin the place to save")
                     : L.signable("guardado.guardar_lugar", "Guardar lugar", "Save place"))
                    .font(.headlineSm)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: puedeGuardar
                                ? [.appPrimary, .appPrimary.opacity(0.78)]
                                : [Color.onSurfaceVariant.opacity(0.35), Color.onSurfaceVariant.opacity(0.25)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: puedeGuardar ? .appPrimary.opacity(0.35) : .clear,
                            radius: 10, x: 0, y: 5)
            )
        }
        .buttonStyle(PressableCapsuleStyle())
        .disabled(!puedeGuardar)
        .animation(.easeInOut(duration: 0.2), value: puedeGuardar)
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
            ajusteManual = true
            return
        }
        cancelarGeocodificacion()
        ajusteManual = false
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
        ajusteManual = true
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
            withAnimation(.spring(response: 0.35)) {
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
struct MapaElegirExpandido: View {
    @Binding var coordenada: CLLocationCoordinate2D?
    /// Se dispara en cada toque del mapa, después de actualizar la coordenada.
    /// Recibe la coordenada tocada para poder geocodificarla.
    var onTocar: (CLLocationCoordinate2D) -> Void
    var onCerrar: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            MapaElegirLugar(
                coordenada: coordenada,
                onTocar: { coord in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        coordenada = coord
                    }
                    onTocar(coord)
                }
            )
            .ignoresSafeArea()

            VStack {
                barraSuperior
                Spacer()
                pie
            }
            .animation(.easeInOut(duration: 0.2), value: coordenada == nil)
        }
    }

    private var barraSuperior: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                Text(L.t("Elige la ubicación", "Pick the location"))
                    .font(.system(size: 14, weight: .semibold))
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
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.onSurface)
                    .frame(width: 38, height: 38)
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
                        .font(.system(size: 16, weight: .bold))
                    Text(L.t("Usar esta ubicación", "Use this location"))
                        .font(.headlineSm)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.appPrimary)
                        .shadow(color: .appPrimary.opacity(0.35), radius: 12, x: 0, y: 6)
                )
            }
            .buttonStyle(PressableCapsuleStyle())
            .padding(.horizontal, 20)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 12, weight: .bold))
                Text(L.t("Toca el mapa para ubicar el lugar", "Tap the map to pin the location"))
                    .font(.system(size: 12, weight: .semibold))
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
    var onSave: (RutaOpcion) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var texto: String = ""

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
                    if !texto.isEmpty {
                        Button {
                            texto = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.onSurfaceVariant.opacity(0.6))
                        }
                        .buttonStyle(.plain)
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
                    Text(L.t("El catálogo no contiene líneas.", "The catalog contains no routes."))
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
    }

    private func filaCatalogo(_ ruta: RutaOpcion) -> some View {
        let guardada = yaGuardadas.contains(ruta.id)
        return Button {
            guard !guardada else { return }
            AppHaptics.success()
            onSave(ruta)
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
                    Text(ruta.recorrido)
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
    }
}
