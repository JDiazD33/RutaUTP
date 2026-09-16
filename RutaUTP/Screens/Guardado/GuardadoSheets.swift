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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack(spacing: 16) {
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
                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text(L.t("RECORRIDO", "ROUTE"))
                    .font(.labelCapsMd)
                    .foregroundStyle(.onSurfaceVariant)
                    .appTracking(AppTracking.wideLabel)
                Text(linea.recorrido)
                    .font(.bodyMd)
                    .foregroundStyle(.onSurface)
            }

            // Datos del feed GTFS
            HStack(spacing: 0) {
                dato(icono: "clock.fill", valor: linea.tiempoTexto, etiqueta: L.t("Viaje", "Trip"))
                divisor
                dato(icono: "creditcard.fill", valor: linea.costo, etiqueta: L.t("Tarifa", "Fare"))
                divisor
                dato(icono: "mappin.and.ellipse", valor: "\(linea.numParaderos)", etiqueta: L.t("Paraderos", "Stops"))
                divisor
                dato(icono: "point.topleft.down.curvedto.point.bottomright.up",
                     valor: String(format: "%.1f km", linea.distanciaKm), etiqueta: L.t("Longitud", "Length"))
            }
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.surfaceContainerLow))

            VStack(alignment: .leading, spacing: 8) {
                Text(L.t("EXTREMOS", "END POINTS"))
                    .font(.labelCapsMd)
                    .foregroundStyle(.onSurfaceVariant)
                    .appTracking(AppTracking.wideLabel)
                HStack(spacing: 10) {
                    Image(systemName: "play.fill").font(.system(size: 10)).foregroundStyle(linea.colorLinea)
                    Text(linea.paradaInicio).font(.bodySm).lineLimit(1)
                    Spacer()
                    Image(systemName: "flag.fill").font(.system(size: 10)).foregroundStyle(.red)
                    Text(linea.paradaFin).font(.bodySm).lineLimit(1)
                }
            }

            Spacer()

            VStack(spacing: 10) {
                Button {
                    onExplorar()
                } label: {
                    HStack {
                        Image(systemName: "map.fill")
                        Text(L.t("Ver recorrido en el mapa", "View route on map"))
                    }
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
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.errorContainer))
                    .foregroundStyle(.onErrorContainer)
                    .font(.bodyMdMedium)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
    }

    private var divisor: some View {
        Rectangle()
            .fill(Color.outlineVariant.opacity(0.35))
            .frame(width: 1, height: 34)
    }

    private func dato(icono: String, valor: String, etiqueta: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icono)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.appPrimary)
            Text(valor)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.onSurface)
            Text(etiqueta.uppercased())
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.onSurfaceVariant)
                .appTracking(AppTracking.wideLabel)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Add Lugar sheet (con mapa en vivo)
struct AddLugarSheet: View {
    var onSave: (LugarGuardado) -> Void
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
    @State private var ajusteManual = false
    @State private var mapaExpandido = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(coordElegida == nil
                         ? L.t("Ubica el lugar para guardar", "Pin the place to save")
                         : L.signable("guardado.guardar_lugar", "Guardar lugar", "Save place"))
                        .font(.headlineMd)
                        .seniable(coordElegida == nil ? nil : "guardado.guardar_lugar")

                    campoNombre
                    campoDireccion
                    estadoUbicacion
                    mapaElegir
                    selectorCategoria

                    botonGuardar
                }
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("Cancelar", "Cancel")) {
                        geocodeTask?.cancel()
                        dismiss()
                    }
                }
            }
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
                TextField(L.t("Ej. Av. España 123, Trujillo", "e.g. 123 España Ave, Trujillo"), text: $direccion)
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
        } else if direccionNoEncontrada {
            Label(L.t("No encontramos esa dirección — toca el mapa para ubicarla tú", "We could not find that address — tap the map to place it yourself"), systemImage: "exclamationmark.circle.fill")
                .font(.bodySm)
                .foregroundStyle(.orange)
        } else if coordElegida != nil {
            Label(L.t("Ubicación encontrada ✓", "Location found ✓"), systemImage: "checkmark.circle.fill")
                .font(.bodySm)
                .foregroundStyle(.green)
        } else {
            Label(L.t("Escribe la dirección para verla en el mapa", "Type the address to see it on the map"), systemImage: "info.circle")
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
                    geocodeTask?.cancel()
                    buscandoUbicacion = false
                    ajusteManual = true
                    withAnimation(.spring(response: 0.3)) {
                        coordElegida = coord
                    }
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
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .topTrailing) { botonExpandirMapa }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.outlineVariant.opacity(0.4), lineWidth: 1)
        )
        .fullScreenCover(isPresented: $mapaExpandido) {
            MapaElegirExpandido(
                coordenada: $coordElegida,
                onTocar: {
                    AppHaptics.impact(.light)
                    geocodeTask?.cancel()
                    buscandoUbicacion = false
                    ajusteManual = true
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
        !nombre.trimmingCharacters(in: .whitespaces).isEmpty && coordElegida != nil
    }

    private var botonGuardar: some View {
        Button {
            guard let coord = coordElegida else { return }
            SeniasPresenter.shared.ejecutarTrasVerSenia(clave: "guardado.guardar_lugar") {
                AppHaptics.success()
                onSave(LugarGuardado(
                    nombre: nombre.trimmingCharacters(in: .whitespaces),
                    direccion: direccion.isEmpty ? L.t("Sin dirección", "No address") : direccion,
                    categoria: categoria,
                    lat: coord.latitude,
                    lon: coord.longitude
                ))
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
        geocodeTask?.cancel()
        ajusteManual = false
        direccionNoEncontrada = false

        let texto = direccion.trimmingCharacters(in: .whitespaces)
        guard texto.count >= 5 else {
            if texto.isEmpty { coordElegida = nil }
            return
        }

        geocodeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            await geocodificar(texto)
        }
    }

    private func geocodificar(_ texto: String) async {
        buscandoUbicacion = true
        let geocoder = CLGeocoder()
        let resultados: [CLPlacemark]? = await withCheckedContinuation { continuidad in
            geocoder.geocodeAddressString("\(texto), Trujillo, Perú") { placemarks, _ in
                continuidad.resume(returning: placemarks)
            }
        }
        guard !Task.isCancelled else { return }
        buscandoUbicacion = false

        if let coord = resultados?.first?.location?.coordinate {
            direccionNoEncontrada = false
            withAnimation(.spring(response: 0.35)) {
                coordElegida = coord
                recentrarTrigger += 1
            }
        } else {
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
    var onTocar: () -> Void
    var onCerrar: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            MapaElegirLugar(
                coordenada: coordenada,
                onTocar: { coord in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        coordenada = coord
                    }
                    onTocar()
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
                } else if catalogo.isEmpty {
                    // El feed no llegó. Antes esta rama no existía y el usuario
                    // se quedaba en un "Cargando…" eterno.
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 26))
                            .foregroundStyle(.onSurfaceVariant)
                        Text(L.t("No se pudieron cargar las líneas del feed",
                                 "Couldn't load routes from the feed"))
                            .font(.bodySm)
                            .foregroundStyle(.onSurfaceVariant)
                            .multilineTextAlignment(.center)
                        Text(L.t("Cierra y vuelve a abrir esta pantalla para reintentar.",
                                 "Close and reopen this screen to try again."))
                            .font(.bodyXs)
                            .foregroundStyle(.onSurfaceVariant.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
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
