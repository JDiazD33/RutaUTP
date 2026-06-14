//
//  RutaMapKitView.swift
//  RutaUTP
//
//  ✅ CORREGIDO V4: Reemplaza el contenedor azul decorativo por un mapa real.
//  - Usa un unico MKMapView (UIViewRepresentable) con anotaciones y polyline.
//  - Esto evita el problema de doble mapa (SwiftUI Map + MKMapView overlay)
//    donde los tiles del MKMapView ocultaban las anotaciones.
//  - Badge "RUTA SEGURA" sobre el mapa en esquina superior derecha.
//  - Se usa con .disabled(true) y .allowsHitTesting(false) desde el padre
//    para no capturar gestos de scroll.
//

import SwiftUI
import MapKit
import UIKit

// MARK: - Coordenadas de las rutas
struct RutaCoordenadas {
    static let linea10: [CLLocationCoordinate2D] = [
        CLLocationCoordinate2D(latitude: -8.0780, longitude: -79.0420),
        CLLocationCoordinate2D(latitude: -8.0850, longitude: -79.0390),
        CLLocationCoordinate2D(latitude: -8.0920, longitude: -79.0360),
        CLLocationCoordinate2D(latitude: -8.0990, longitude: -79.0330),
        CLLocationCoordinate2D(latitude: -8.1040, longitude: -79.0310),
        CLLocationCoordinate2D(latitude: -8.1080, longitude: -79.0295),
        CLLocationCoordinate2D(latitude: -8.1116, longitude: -79.0287)
    ]

    static let linea4: [CLLocationCoordinate2D] = [
        CLLocationCoordinate2D(latitude: -8.0825, longitude: -79.1197),
        CLLocationCoordinate2D(latitude: -8.0920, longitude: -79.0900),
        CLLocationCoordinate2D(latitude: -8.1000, longitude: -79.0600),
        CLLocationCoordinate2D(latitude: -8.1050, longitude: -79.0400),
        CLLocationCoordinate2D(latitude: -8.1090, longitude: -79.0320),
        CLLocationCoordinate2D(latitude: -8.1116, longitude: -79.0287)
    ]

    static let lineaB: [CLLocationCoordinate2D] = [
        CLLocationCoordinate2D(latitude: -8.1200, longitude: -79.0350),
        CLLocationCoordinate2D(latitude: -8.1170, longitude: -79.0330),
        CLLocationCoordinate2D(latitude: -8.1145, longitude: -79.0310),
        CLLocationCoordinate2D(latitude: -8.1116, longitude: -79.0287)
    ]

    static func para(linea: String) -> [CLLocationCoordinate2D] {
        switch linea.uppercased() {
        case "10": return linea10
        case "4":  return linea4
        case "B":  return lineaB
        default:   return linea10
        }
    }
}

// MARK: - Anotacion personalizada
enum TipoMarcadorRuta { case origen, destino, bus }

final class MarcadorRutaAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let tipo: TipoMarcadorRuta
    let color: UIColor
    let linea: String?
    let titleText: String?

    var title: String? { titleText }

    init(coordinate: CLLocationCoordinate2D,
         tipo: TipoMarcadorRuta,
         color: UIColor,
         linea: String? = nil,
         title: String? = nil) {
        self.coordinate = coordinate
        self.tipo = tipo
        self.color = color
        self.linea = linea
        self.titleText = title
    }
}

// MARK: - UIViewRepresentable del mapa
struct MapaRutaRepresentable: UIViewRepresentable {
    let coordenadas: [CLLocationCoordinate2D]
    let colorLinea: UIColor
    let linea: String

    func makeCoordinator() -> Coordinator {
        Coordinator(color: colorLinea, linea: linea)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.isUserInteractionEnabled = false
        mapView.pointOfInterestFilter = .excludingAll

        guard !coordenadas.isEmpty else { return mapView }

        // Polyline
        let polyline = MKPolyline(coordinates: coordenadas, count: coordenadas.count)
        mapView.addOverlay(polyline)

        // Ajustar region al boundingRect del polyline
        mapView.setVisibleMapRect(
            polyline.boundingMapRect,
            edgePadding: UIEdgeInsets(top: 40, left: 30, bottom: 40, right: 30),
            animated: false
        )

        // Anotaciones
        if let primero = coordenadas.first {
            mapView.addAnnotation(MarcadorRutaAnnotation(
                coordinate: primero,
                tipo: .origen,
                color: colorLinea
            ))
        }
        if let ultimo = coordenadas.last {
            mapView.addAnnotation(MarcadorRutaAnnotation(
                coordinate: ultimo,
                tipo: .destino,
                color: .systemRed,
                title: "UTP Trujillo"
            ))
        }
        if coordenadas.count > 2 {
            mapView.addAnnotation(MarcadorRutaAnnotation(
                coordinate: coordenadas[1],
                tipo: .bus,
                color: colorLinea,
                linea: linea
            ))
        }

        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {}

    final class Coordinator: NSObject, MKMapViewDelegate {
        let color: UIColor
        let linea: String

        init(color: UIColor, linea: String) {
            self.color = color
            self.linea = linea
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = color
                renderer.lineWidth = 5
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let marcador = annotation as? MarcadorRutaAnnotation else { return nil }

            let id = "Marcador-\(marcador.tipo)"
            let view: MKMarkerAnnotationView

            if let dequeued = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView {
                dequeued.annotation = annotation
                view = dequeued
            } else {
                view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            }

            view.markerTintColor = marcador.color
            view.glyphTintColor = .white
            view.titleVisibility = marcador.tipo == .destino ? .visible : .hidden
            view.subtitleVisibility = .hidden
            view.canShowCallout = marcador.tipo == .destino
            view.animatesWhenAdded = false

            switch marcador.tipo {
            case .origen:
                view.glyphImage = UIImage(systemName: "circle.fill")
            case .destino:
                view.glyphImage = UIImage(systemName: "graduationcap.fill")
            case .bus:
                view.glyphText = marcador.linea
            }

            return view
        }
    }
}

// MARK: - Vista SwiftUI con mapa + badge
struct RutaMapKitView: View {
    let ruta: RutaOpcion

    private var coordenadas: [CLLocationCoordinate2D] {
        RutaCoordenadas.para(linea: ruta.linea)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            MapaRutaRepresentable(
                coordenadas: coordenadas,
                colorLinea: UIColor(ruta.colorLinea),
                linea: ruta.linea
            )

            // Badge "RUTA SEGURA"
            HStack(spacing: 5) {
                Image(systemName: "heart.shield.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                Text("RUTA SEGURA")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .appTracking(0.5)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color.tertiary)
                    .shadow(color: .black.opacity(0.20), radius: 6, x: 0, y: 2)
            )
            .padding(.top, 14)
            .padding(.trailing, 14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    RutaMapKitView(ruta: RutaOpcion(
        id: 2, linea: "10", empresa: "El Cortijo",
        recorrido: "El Cortijo → Av. España → UTP",
        llegaEn: "7 min", tiempo: "25 min", costo: "S/ 1.00",
        congestion: "Baja", colorLinea: .secondary
    ))
    .frame(height: 280)
    .padding()
}
