import SwiftUI
import MapKit

// MARK: - Mapa no interactivo para RutasView
struct RutasMapView: View {
    /// Región fija: este mapa es decorativo (`.disabled(true)`), así que no
    /// necesita un `@State` que nadie llega a cambiar.
    private static let regionUTP = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: -8.098247879173792, longitude: -79.03818104755645),
        span: MKCoordinateSpan(latitudeDelta: 0.035, longitudeDelta: 0.035)
    )

    private let marcadores: [MapaAnotacion] = [
        MapaAnotacion(id: 1, lat: -8.098247879173792, lon: -79.03818104755645, tipo: .utp),
        MapaAnotacion(id: 2, lat: -8.1180, lon: -79.0350, tipo: .usuario)
    ]

    private func titulo(_ tipo: TipoAnotacion) -> String {
        switch tipo {
        case .utp:     return "UTP Trujillo"
        case .usuario: return L.t("Mi Ubicación", "My Location")
        }
    }

    var body: some View {
        // Inicializadores de `MapContentBuilder` (iOS 17): sustituyen a
        // `Map(coordinateRegion:annotationItems:)` y a `MapAnnotation`, que
        // quedaron obsoletos.
        Map(initialPosition: .region(Self.regionUTP)) {
            ForEach(marcadores) { m in
                Annotation(titulo(m.tipo), coordinate: m.coordinate) {
                    switch m.tipo {
                    case .utp:     MarcadorUTP()
                    case .usuario: PulsingUserMarker()
                    }
                }
            }
        }
        .disabled(true)
        .overlay(
            // Gradient fade al bottom
            VStack {
                Spacer()
                LinearGradient(
                    colors: [Color.clear, Color.appBackground.opacity(0.6)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 60)
                .allowsHitTesting(false)
            }
        )
    }
}

