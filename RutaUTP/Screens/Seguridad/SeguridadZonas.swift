//
//  SeguridadZonas.swift
//  RutaUTP
//
//  Mapa de paraderos y lugares de ayuda cercanos.
//  
//  Estaba dentro de `SeguridadView.swift`.

import SwiftUI
import MapKit
import CoreLocation
// MARK: - Acceso al mapa de paraderos
struct AccesoParaderos: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var tamanoIcono = 28
    private var acento: Color { colorScheme == .dark ? .primaryFixed : .appPrimary }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(spacing: 16))
        layout {
            Image(systemName: "map")
                .font(.system(size: min(tamanoIcono, 36), weight: .medium))
                .foregroundStyle(acento)
                .frame(width: 56, height: 56)
                .background(Color(uiColor: .tertiarySystemGroupedBackground), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(L.t("Explorar paraderos", "Explore stops"))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(L.t("Encuentra tu próxima parada", "Find your next stop"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(acento)
                    .accessibilityHidden(true)
            }
        }
        .multilineTextAlignment(.leading)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

enum CategoriaAyudaCercana: String, CaseIterable, Identifiable {
    case comisarias, salud, bomberos
    var id: String { rawValue }
    var titulo: String {
        switch self {
        case .comisarias: return L.t("Comisarías", "Police stations")
        case .salud: return L.t("Salud", "Healthcare")
        case .bomberos: return L.t("Bomberos", "Fire stations")
        }
    }
    var icono: String {
        switch self {
        case .comisarias: return "shield.lefthalf.filled"
        case .salud: return "cross.case"
        case .bomberos: return "flame"
        }
    }
    var filtro: MKPointOfInterestFilter {
        switch self {
        case .comisarias: return MKPointOfInterestFilter(including: [.police])
        case .salud: return MKPointOfInterestFilter(including: [.hospital])
        case .bomberos: return MKPointOfInterestFilter(including: [.fireStation])
        }
    }

    // En Trujillo, la consulta por categoría `.fireStation` no devuelve nada
    // (MKError.placemarkNotFound a 5 y 15 km, comprobado el 15/11/2026), pero
    // la búsqueda por texto «bomberos» sí encuentra las compañías; algunas,
    // como Salvadora Trujillo 26, no tienen categoría asignada en Apple Maps.

    /// Comisarías y salud usan la búsqueda por categoría; bomberos, por texto.
    var buscaPorCategoria: Bool { self != .bomberos }

    /// Consultas de texto: sin filtro (compañías sin categoría) y con el
    /// filtro de estación de bomberos (las que Apple sí clasifica).
    var consultasTexto: [(texto: String, filtro: MKPointOfInterestFilter?)] {
        guard self == .bomberos else { return [] }
        return [("bomberos", nil), ("bomberos", filtro)]
    }

    /// Hay muchas menos compañías de bomberos que comisarías o centros de salud.
    var radioMetros: CLLocationDistance { self == .bomberos ? 20_000 : 5_000 }

    /// La búsqueda por texto también trae tiendas de extintores; alguna incluso
    /// figura como estación de bomberos.
    func admite(_ item: MKMapItem) -> Bool {
        guard self == .bomberos else { return true }
        let nombre = (item.name ?? "").folding(options: [.caseInsensitive, .diacriticInsensitive],
                                                locale: Locale(identifier: "es"))
        if nombre.contains("extint") { return false }
        return nombre.contains("bomber") || item.pointOfInterestCategory == .fireStation
    }
    /// Pista de VoiceOver del acceso en «Cerca de ti».
    var pista: String {
        switch self {
        case .comisarias: return L.t("Muestra las comisarías más cercanas en un mapa", "Shows the nearest police stations on a map")
        case .salud: return L.t("Muestra hospitales y centros de salud cercanos en un mapa", "Shows nearby hospitals and health centers on a map")
        case .bomberos: return L.t("Muestra las compañías de bomberos más cercanas en un mapa", "Shows the nearest fire stations on a map")
        }
    }
}

/// Búsqueda real de MapKit. El GPS es el mismo servicio compartido de la app;
/// si no hay permiso/fix, se identifica expresamente la referencia utilizada.
struct AyudaCercanaSheet: View {
    let categoria: CategoriaAyudaCercana
    let locationService: LocationServiceProtocol
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: AppRouter
    @Environment(\.accessibilityReduceMotion) private var reducirMovimiento
    @State private var resultados: [MKMapItem] = []
    @State private var indiceSeleccionado: Int?
    @State private var buscando = true
    @State private var error: String?
    @State private var revision = 0
    @State private var usaUbicacion = false
    @State private var centro = TransporteApp.referenciaInicio
    @State private var busqueda: MKLocalSearch?
    @State private var camara: MapCameraPosition = .region(MKCoordinateRegion(
        center: TransporteApp.referenciaInicio,
        span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)))

    private var referencia: String {
        if usaUbicacion { return L.t("Cerca de tu ubicación", "Near your location") }
        if TransporteApp.busesUTPActivos { return L.t("Desde el campus UTP", "From the UTP campus") }
        return TransporteApp.sedeVisible == nil
            ? L.t("Desde el centro", "From downtown")
            : L.t("Desde tu sede", "From your workplace")
    }

    var body: some View {
        NavigationStack {
            GeometryReader { espacio in
                VStack(alignment: .leading, spacing: 12) {
                    Text(referencia)
                        .font(.bodySm).foregroundStyle(Color.onSurfaceVariant)
                        .padding(.horizontal, 20)
                    mapa
                        .frame(height: min(230, max(120, espacio.size.height * 0.36)))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .padding(.horizontal, 20)
                    listado
                }
                .padding(.top, 12)
            }
            .background(Color.appBackground)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let lugarSeleccionado {
                    destinoSeleccionado(lugarSeleccionado)
                }
            }
            .navigationTitle(categoria.titulo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("Cerrar", "Close")) { dismiss() }
                }
            }
        }
        .tint(Color.appAccent)
        .seguirTemaForzado()
        .task(id: revision) { await cargar() }
        .onChange(of: indiceSeleccionado) { _, indice in
            if let indice, resultados.indices.contains(indice) {
                centrar(resultados[indice])
            }
        }
        .onDisappear { busqueda?.cancel() }
    }

    private var lugarSeleccionado: MKMapItem? {
        guard let indiceSeleccionado, resultados.indices.contains(indiceSeleccionado) else { return nil }
        return resultados[indiceSeleccionado]
    }

    private var mapa: some View {
        Map(position: $camara, selection: $indiceSeleccionado) {
            if usaUbicacion { UserAnnotation() }
            ForEach(Array(resultados.enumerated()), id: \.offset) { indice, item in
                Marker(item.name ?? categoria.titulo, systemImage: categoria.icono,
                       coordinate: item.placemark.coordinate)
                    .tint(Color.appAccent)
                    .tag(indice)
            }
        }
    }

    private var listado: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if buscando {
                    ProgressView(L.t("Buscando lugares…", "Finding places…"))
                        .frame(maxWidth: .infinity).padding(.vertical, 20)
                } else if let error {
                    Text(error).font(.bodySm).foregroundStyle(Color.onSurfaceVariant)
                    Button(L.t("Reintentar", "Retry")) { revision += 1 }
                        .buttonStyle(.bordered)
                } else if resultados.isEmpty {
                    Text(L.t("No encontramos lugares de esta categoría cerca de la referencia.",
                             "No places in this category were found near the reference location."))
                        .font(.bodySm).foregroundStyle(Color.onSurfaceVariant)
                    Button(L.t("Reintentar", "Retry")) { revision += 1 }
                        .buttonStyle(.bordered)
                } else {
                    Text(L.t("Toca un lugar para verlo en el mapa", "Tap a place to view it on the map"))
                        .font(.bodyXs).foregroundStyle(Color.onSurfaceVariant)
                        .padding(.bottom, 2)
                    ForEach(Array(resultados.enumerated()), id: \.offset) { indice, item in
                        Button {
                            AppHaptics.selection()
                            if indiceSeleccionado == indice { centrar(item) }
                            else { indiceSeleccionado = indice }
                        } label: {
                            ficha(item, seleccionada: indiceSeleccionado == indice)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(L.t("Ver ubicación en el mapa", "View location on map"))
                        .accessibilityAddTraits(indiceSeleccionado == indice ? .isSelected : [])
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    private func ficha(_ item: MKMapItem, seleccionada: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: categoria.icono)
                    .font(.bodySmMedium)
                    .frame(width: 32, height: 32)
                    .background(Color.primaryContainer, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(Color.onPrimaryContainer)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name ?? categoria.titulo)
                        .font(.bodyMdMedium).foregroundStyle(Color.onSurface)
                    Text(distancia(item)).font(.bodyXs).foregroundStyle(Color.onSurfaceVariant)
                }
                Spacer(minLength: 0)
                Image(systemName: seleccionada ? "checkmark.circle.fill" : "map")
                    .foregroundStyle(Color.appAccent)
                    .accessibilityHidden(true)
            }
            dato(direccion(item), icono: "mappin")
            if let telefono = textoDisponible(item.phoneNumber) {
                dato(telefono, icono: "phone")
            }
            if let sitio = textoDisponible(item.url?.host) {
                dato(sitio, icono: "globe")
            }
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(seleccionada ? Color.primaryContainer.opacity(0.45) : Color.surfaceContainerLowest,
                    in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(seleccionada ? Color.appAccent : .clear, lineWidth: 1.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }

    private func dato(_ texto: String, icono: String) -> some View {
        Label(texto, systemImage: icono)
            .font(.bodySm).foregroundStyle(Color.onSurfaceVariant)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func destinoSeleccionado(_ item: MKMapItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.name ?? categoria.titulo)
                .font(.bodySmMedium).foregroundStyle(Color.onSurface)
                .lineLimit(2)
            Button { irALaZona(item) } label: {
                Label(L.t("Ir a esta zona", "Go to this area"), systemImage: "location.fill")
                    .font(.bodyMdMedium)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(Color.onPrimaryFill)
                    .background(Color.primaryFill, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSurface)
        .overlay(alignment: .top) { Color.outlineVariant.opacity(0.45).frame(height: 1) }
    }

    private func textoDisponible(_ valor: String?) -> String? {
        guard let texto = valor?.trimmingCharacters(in: .whitespacesAndNewlines), !texto.isEmpty else { return nil }
        return texto
    }

    private func direccion(_ item: MKMapItem) -> String {
        textoDisponible(item.placemark.title) ?? L.t("Dirección no disponible", "Address unavailable")
    }

    private func centrar(_ item: MKMapItem) {
        withAnimation(reducirMovimiento ? nil : .easeInOut(duration: 0.3)) {
            camara = .region(MKCoordinateRegion(center: item.placemark.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)))
        }
    }

    @MainActor
    private func cargar() async {
        buscando = true
        error = nil
        indiceSeleccionado = nil
        resultados = []
        let ubicacion = await UbicacionPuntual.obtener(desde: locationService)
        guard !Task.isCancelled else { return }
        usaUbicacion = ubicacion != nil
        centro = ubicacion?.coordinate ?? TransporteApp.referenciaInicio
        camara = .region(MKCoordinateRegion(center: centro,
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)))
        defer { busqueda = nil; buscando = false }
        var encontrados: [MKMapItem] = []
        var falloRed = false
        if categoria.buscaPorCategoria {
            let request = MKLocalPointsOfInterestRequest(center: centro, radius: categoria.radioMetros)
            request.pointOfInterestFilter = categoria.filtro
            await ejecutar(MKLocalSearch(request: request), en: &encontrados, falloRed: &falloRed)
        }
        for consulta in categoria.consultasTexto {
            guard !Task.isCancelled else { return }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = consulta.texto
            request.region = MKCoordinateRegion(center: centro, latitudinalMeters: categoria.radioMetros * 2,
                                                longitudinalMeters: categoria.radioMetros * 2)
            request.resultTypes = .pointOfInterest
            request.pointOfInterestFilter = consulta.filtro
            await ejecutar(MKLocalSearch(request: request), en: &encontrados, falloRed: &falloRed)
        }
        guard !Task.isCancelled else { return }

        let origen = CLLocation(latitude: centro.latitude, longitude: centro.longitude)
        func metros(_ item: MKMapItem) -> CLLocationDistance {
            origen.distance(from: CLLocation(latitude: item.placemark.coordinate.latitude,
                                             longitude: item.placemark.coordinate.longitude))
        }
        var unicos: [MKMapItem] = []
        for item in encontrados where categoria.admite(item) && metros(item) <= categoria.radioMetros {
            // Las dos consultas de texto repiten lugares.
            let repetido = unicos.contains { otro in
                otro.name == item.name
                    || CLLocation(latitude: otro.placemark.coordinate.latitude,
                                  longitude: otro.placemark.coordinate.longitude)
                        .distance(from: CLLocation(latitude: item.placemark.coordinate.latitude,
                                                   longitude: item.placemark.coordinate.longitude)) < 60
            }
            if !repetido { unicos.append(item) }
        }
        resultados = unicos.sorted { metros($0) < metros($1) }
        // Sin resultados no es un fallo de red: el listado muestra su aviso.
        if resultados.isEmpty && falloRed {
            self.error = ConectividadService.shared.estado == .sinConexion
                ? L.t("Sin conexión. Esta búsqueda usa Apple Maps y necesita internet.",
                      "No connection. This search uses Apple Maps and needs internet.")
                : L.t("No pudimos buscar el lugar. Revisa tu conexión.",
                      "Could not find the location. Check your connection.")
        }
    }

    /// Ejecuta una búsqueda cancelable al cerrar la hoja. MapKit lanza
    /// `placemarkNotFound` cuando no hay resultados: eso no es un fallo de red.
    @MainActor
    private func ejecutar(_ search: MKLocalSearch, en encontrados: inout [MKMapItem],
                          falloRed: inout Bool) async {
        busqueda = search
        do {
            encontrados += try await search.start().mapItems
        } catch {
            let fallo = error as NSError
            let sinResultados = fallo.domain == MKErrorDomain
                && fallo.code == Int(MKError.Code.placemarkNotFound.rawValue)
            if !sinResultados { falloRed = true }
        }
    }

    private func distancia(_ item: MKMapItem) -> String {
        let origen = CLLocation(latitude: centro.latitude, longitude: centro.longitude)
        let destino = CLLocation(latitude: item.placemark.coordinate.latitude,
                                 longitude: item.placemark.coordinate.longitude)
        let kilometros = FormatoNumero.decimal(origen.distance(from: destino) / 1_000)
        return usaUbicacion
            ? L.f("{0} km de ti · en línea recta", "{0} km from you · straight line", [kilometros])
            : L.f("{0} km de la referencia · en línea recta", "{0} km from the reference · straight line", [kilometros])
    }

    private func irALaZona(_ item: MKMapItem) {
        let coordenada = item.placemark.coordinate
        router.destinoPendiente = DestinoPendiente(titulo: item.name ?? categoria.titulo,
            lat: coordenada.latitude, lon: coordenada.longitude)
        dismiss()
        router.navigate(to: .mapaPrincipal)
    }
}

#Preview {
    SeguridadView().environmentObject(AppRouter())
}
