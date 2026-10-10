import SwiftUI
import MapKit

// MARK: - Mapa no interactivo para RutasView
struct RutasMapView: View {
    // Decorativo: sigue la sede elegida sin abrir otro servicio de ubicación.
    private var region: MKCoordinateRegion {
        MKCoordinateRegion(center: TransporteApp.referenciaInicio,
                           span: MKCoordinateSpan(latitudeDelta: 0.035, longitudeDelta: 0.035))
    }

    var body: some View {
        // Inicializadores de `MapContentBuilder` (iOS 17): sustituyen a
        // `Map(coordinateRegion:annotationItems:)` y a `MapAnnotation`, que
        // quedaron obsoletos.
        Map(position: .constant(.region(region))) {
            if TransporteApp.utpComoReferencia {
                Annotation(L.t("Campus UTP Trujillo", "UTP Trujillo campus"), coordinate: GTFSRepository.coordenadaUTP) {
                    MarcadorCampusUTP(busesUTPActivos: TransporteApp.busesUTPActivos)
                }
            } else if let sede = TransporteApp.sedeVisible {
                Annotation(sede.nombre, coordinate: sede.coordinate, anchor: .bottom) {
                    MarcadorSedeTrabajo(sede: sede)
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
