//
//  SeguridadZonas.swift
//  RutaUTP
//
//  Zonas seguras de Trujillo: el modelo y el mini-mapa del banner.
//  
//  Estaba dentro de `SeguridadView.swift`.

import SwiftUI
import MapKit
import CoreLocation
// MARK: - Modelo de Ruta Segura
struct RutaSegura: Identifiable {
    let id: Int
    /// Nombre con el que se busca la zona en Apple Maps.
    ///
    /// Vive aquí, y no en un array paralelo indexado por `id` en la vista, para
    /// que el compilador obligue a declararlo en CADA zona: antes era
    /// `names[zona.id]` sobre un array de 10 posiciones, así que una undécima
    /// zona rompía la búsqueda con un índice fuera de rango.
    let consultaMapa: String
    let titulo: String
    let descripcion: String
    let icono: String
    let iconoBg: Color
    let iconoFg: Color
    let accent: Color?
}


// MARK: - Preview nocturno del banner de paraderos (mini-mapa con focos)
/// Ilustración animada: calles y focos con la temática elegida, pulsando en las
/// posiciones de los paraderos iluminados (si ya cargaron; si no, layout fijo).
struct BannerParaderosPreview: View {
    let cantidad: Int
    /// Paraderos cargados. Se pasan desde la vista padre en lugar de leerse de
    /// un `static var` compartido.
    var paraderos: [ParaderoGTFS] = []

    // Calles del mini-mapa (proporciones del contenedor)
    private static let calles: [(from: CGPoint, to: CGPoint)] = {
        let puntos = [(0.04, 0.78), (0.22, 0.62), (0.42, 0.70), (0.60, 0.46),
                      (0.78, 0.38), (0.97, 0.22), (0.12, 0.30), (0.35, 0.16),
                      (0.58, 0.10), (0.88, 0.72), (0.30, 0.90), (0.65, 0.82)]
        return [
            (p(0), p(1)), (p(1), p(2)), (p(2), p(3)), (p(3), p(4)), (p(4), p(5)),
            (p(6), p(7)), (p(7), p(8)), (p(2), p(7)), (p(3), p(8)),
            (p(1), p(6)), (p(4), p(9)), (p(10), p(2)), (p(11), p(9))
        ]
        func p(_ i: Int) -> CGPoint { CGPoint(x: puntos[i].0, y: puntos[i].1) }
    }()

    /// Focos en fracciones del contenedor: reales si hay paraderos cargados.
    ///
    /// Los paraderos llegan como parámetro. Antes se leían de un
    /// `static var paraderosCache` de `SeguridadView` que se escribía desde
    /// `.task` y se leía aquí durante el render: estado global mutable
    /// compartido entre el ciclo de carga y el de dibujo.
    private var focos: [CGPoint] {
        if !paraderos.isEmpty {
            let lats = paraderos.map(\.lat)
            let lons = paraderos.map(\.lon)
            guard let minLat = lats.min(), let maxLat = lats.max(),
                  let minLon = lons.min(), let maxLon = lons.max() else {
                return Self.focosDecorativos
            }
            let rangoLat = max(maxLat - minLat, 0.0001)
            let rangoLon = max(maxLon - minLon, 0.0001)
            return paraderos.map { p in
                CGPoint(x: 0.08 + (p.lon - minLon) / rangoLon * 0.84,
                        y: 0.85 - (p.lat - minLat) / rangoLat * 0.72)
            }
        }
        return Self.focosDecorativos
    }

    /// Fallback decorativo mientras carga el feed.
    private static let focosDecorativos: [CGPoint] = [
        (0.14, 0.62), (0.30, 0.48), (0.47, 0.58), (0.63, 0.32),
        (0.80, 0.26), (0.22, 0.24), (0.55, 0.78), (0.88, 0.55)
    ].map { CGPoint(x: $0.0, y: $0.1) }

    var body: some View {
        GeometryReader { geo in
            DecorativeAnimationScope { animar in
                TimelineView(.animation(minimumInterval: 0.5, paused: !animar)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    ZStack {
                        // Noche
                        LinearGradient(colors: [Color.primaryFill, Color.primaryContainer],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)

                        // Calles
                        Path { p in
                            for calle in Self.calles {
                                p.move(to: CGPoint(x: calle.from.x * geo.size.width, y: calle.from.y * geo.size.height))
                                p.addLine(to: CGPoint(x: calle.to.x * geo.size.width, y: calle.to.y * geo.size.height))
                            }
                        }
                        .stroke(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .padding(.horizontal, 8)

                        Path { p in
                            for calle in Self.calles {
                                p.move(to: CGPoint(x: calle.from.x * geo.size.width, y: calle.from.y * geo.size.height))
                                p.addLine(to: CGPoint(x: calle.to.x * geo.size.width, y: calle.to.y * geo.size.height))
                            }
                        }
                        .stroke(Color.onPrimaryContainer.opacity(0.35), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [3, 5]))
                        .padding(.horizontal, 8)

                        // Focos con pulso desfasado
                        ForEach(Array(focos.enumerated()), id: \.offset) { i, foco in
                            let fase = Double(i) * 0.9
                            let brillo = animar ? 0.55 + 0.45 * sin(t * 2.2 + fase) : 0.7
                            ZStack {
                                Circle()
                                    .fill(Color.secondaryContainer.opacity(0.22 * brillo))
                                    .frame(width: 34, height: 34)
                                Circle()
                                    .fill(Color.secondaryContainer)
                                    .frame(width: 12, height: 12)
                                    .shadow(color: Color.secondaryContainer.opacity(brillo), radius: 6)
                                Image(systemName: "lightbulb.fill")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(.onSecondaryContainer)
                                    .opacity(0.95)
                            }
                            .position(x: foco.x * geo.size.width, y: foco.y * geo.size.height)
                        }
                    }
                    .clipped()
                }
            }
        }
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 5) {
                Label(L.t("EXPLORA TU CIUDAD", "EXPLORE YOUR CITY"), systemImage: "map.fill")
                    .font(.system(size: 10, weight: .bold)).tracking(1.2)
                    .foregroundStyle(.white)
                Text(L.t("Encuentra tu próxima parada", "Find your next stop"))
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(.white).lineLimit(2)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Color.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
        }
        .overlay(alignment: .bottom) {
            // Cápsula de info
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                Text(L.f("{0} paraderos por explorar", "{0} stops to explore", ["\(cantidad)"]))
                    .font(.bodySm)
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "map.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(L.t("VER MAPA", "OPEN MAP"))
                    .font(.labelCapsSm)
                    .foregroundStyle(.white)
                    .appTracking(AppTracking.wideLabel)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.black.opacity(0.55)))
            .padding(12)
        }
        .frame(height: 212)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
    }
}

enum CategoriaAyudaCercana: String, CaseIterable, Identifiable {
    case comisarias, salud
    var id: String { rawValue }
    var titulo: String {
        self == .comisarias ? L.t("Comisarías", "Police stations") : L.t("Salud", "Healthcare")
    }
    var icono: String { self == .comisarias ? "shield.lefthalf.filled" : "cross.case" }
    var filtro: MKPointOfInterestFilter {
        MKPointOfInterestFilter(including: self == .comisarias ? [.police] : [.hospital])
    }
}

/// Búsqueda real de MapKit. El GPS es el mismo servicio compartido de la app;
/// si no hay permiso/fix, se identifica expresamente la referencia utilizada.
struct AyudaCercanaSheet: View {
    let categoria: CategoriaAyudaCercana
    let locationService: LocationServiceProtocol
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: AppRouter
    @State private var resultados: [MKMapItem] = []
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
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(referencia)
                        .font(.bodySm).foregroundStyle(Color.onSurfaceVariant)
                    Map(position: $camara) {
                        if usaUbicacion { UserAnnotation() }
                        ForEach(Array(resultados.enumerated()), id: \.offset) { _, item in
                            Marker(item.name ?? categoria.titulo, coordinate: item.placemark.coordinate)
                                .tint(Color.appPrimary)
                        }
                    }
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
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
                        ForEach(Array(resultados.enumerated()), id: \.offset) { _, item in
                            Button { abrir(item) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: categoria.icono)
                                        .foregroundStyle(Color.appPrimary)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.name ?? categoria.titulo).font(.bodyMdMedium)
                                        if let direccion = item.placemark.title {
                                            Text(direccion).font(.bodySm)
                                                .foregroundStyle(Color.onSurfaceVariant)
                                        }
                                        Text(distancia(item)).font(.caption)
                                            .foregroundStyle(Color.onSurfaceVariant)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "arrow.up.right").foregroundStyle(Color.appPrimary)
                                }
                                .multilineTextAlignment(.leading)
                                .foregroundStyle(Color.onSurface)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 16))
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(L.t("Ver ubicación en el mapa", "View location on map"))
                        }
                    }
                }
                .padding(20)
            }
            .background(Color.appBackground)
            .navigationTitle(categoria.titulo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("Cerrar", "Close")) { dismiss() }
                }
            }
        }
        .tint(Color.appPrimary)
        .seguirTemaForzado()
        .task(id: revision) { await cargar() }
        .onDisappear { busqueda?.cancel() }
    }

    @MainActor
    private func cargar() async {
        buscando = true
        error = nil
        resultados = []
        let ubicacion = await UbicacionPuntual.obtener(desde: locationService)
        guard !Task.isCancelled else { return }
        usaUbicacion = ubicacion != nil
        centro = ubicacion?.coordinate ?? TransporteApp.referenciaInicio
        camara = .region(MKCoordinateRegion(center: centro,
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)))
        let request = MKLocalPointsOfInterestRequest(center: centro, radius: 5_000)
        request.pointOfInterestFilter = categoria.filtro
        let search = MKLocalSearch(request: request)
        busqueda = search
        defer { busqueda = nil; buscando = false }
        do {
            let response = try await search.start()
            guard !Task.isCancelled else { return }
            let origen = CLLocation(latitude: centro.latitude, longitude: centro.longitude)
            resultados = response.mapItems.sorted {
                origen.distance(from: CLLocation(latitude: $0.placemark.coordinate.latitude,
                                                 longitude: $0.placemark.coordinate.longitude))
                < origen.distance(from: CLLocation(latitude: $1.placemark.coordinate.latitude,
                                                   longitude: $1.placemark.coordinate.longitude))
            }
        } catch {
            guard !Task.isCancelled else { return }
            self.error = L.t("No pudimos buscar el lugar. Revisa tu conexión.",
                             "Could not find the location. Check your connection.")
        }
    }

    private func distancia(_ item: MKMapItem) -> String {
        let origen = CLLocation(latitude: centro.latitude, longitude: centro.longitude)
        let destino = CLLocation(latitude: item.placemark.coordinate.latitude,
                                 longitude: item.placemark.coordinate.longitude)
        return L.f("{0} km de la referencia", "{0} km from the reference", [
            FormatoNumero.decimal(origen.distance(from: destino) / 1_000)
        ])
    }

    private func abrir(_ item: MKMapItem) {
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
