//
//  RutaMapKitView.swift
//  RutaUTP
//
//  CORREGIDO V4: Reemplaza el contenedor azul decorativo por un mapa real.
//  - Usa un unico MKMapView (UIViewRepresentable) con anotaciones y polyline.
//  - Esto evita el problema de doble mapa (SwiftUI Map + MKMapView overlay)
//    donde los tiles del MKMapView ocultaban las anotaciones.
//  - Badge "RECORRIDO OFICIAL" sobre el mapa en esquina superior derecha.
//    Antes decía "RUTA SEGURA", que afirmaba una seguridad que el feed GTFS
//    no respalda: el feed describe el trazado y los paraderos, no si la zona
//    es segura. "Recorrido oficial" sí es cierto y verificable.
//  - Se usa con .disabled(true) y .allowsHitTesting(false) desde el padre
//    para no capturar gestos de scroll.
//

import SwiftUI
import MapKit
import UIKit

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
    /// `route_id` de la ruta. Identifica la geometría: si cambia, SwiftUI
    /// reutilizó esta vista para OTRA ruta y hay que rehacer overlays y
    /// marcadores. Sin esto, `updateUIView` era un no-op y el mapa seguía
    /// mostrando el trazado anterior.
    let idRuta: String
    var tituloOrigen: String? = nil
    var tituloDestino: String? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(color: colorLinea, linea: linea, idRuta: idRuta)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.isUserInteractionEnabled = false
        mapView.pointOfInterestFilter = .excludingAll
        construir(mapView)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Solo se rehace si la geometría es de otra ruta. Comparar el route_id
        // es fiable; `[CLLocationCoordinate2D]` no es Equatable y comparar
        // solo el número de puntos no distinguiría dos rutas del mismo tamaño.
        guard context.coordinator.idRuta != idRuta else { return }
        context.coordinator.idRuta = idRuta
        context.coordinator.color = colorLinea
        context.coordinator.linea = linea
        construir(mapView)
    }

    /// Dibuja el recorrido y sus marcadores. Se usa al crear la vista y cuando
    /// se reutiliza para otra ruta.
    private func construir(_ mapView: MKMapView) {
        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations)

        guard !coordenadas.isEmpty else { return }

        // Polyline
        let polyline = MKPolyline(coordinates: coordenadas, count: coordenadas.count)
        mapView.addOverlay(polyline)

        // Ajustar region al boundingRect del polyline
        mapView.setVisibleMapRect(
            polyline.boundingMapRect,
            edgePadding: UIEdgeInsets(top: 40, left: 30, bottom: 40, right: 30),
            animated: false
        )

        // Anotaciones (origen y destino según el feed GTFS)
        if let primero = coordenadas.first {
            mapView.addAnnotation(MarcadorRutaAnnotation(
                coordinate: primero,
                tipo: .origen,
                color: colorLinea,
                title: tituloOrigen
            ))
        }
        if let ultimo = coordenadas.last {
            mapView.addAnnotation(MarcadorRutaAnnotation(
                coordinate: ultimo,
                tipo: .destino,
                color: .systemRed,
                title: tituloDestino ?? "UTP Trujillo"
            ))
        }
        // Bus decorativo a mitad del recorrido
        if coordenadas.count > 2 {
            let medio = coordenadas[coordenadas.count / 2]
            mapView.addAnnotation(MarcadorRutaAnnotation(
                coordinate: medio,
                tipo: .bus,
                color: colorLinea,
                linea: linea
            ))
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var color: UIColor
        var linea: String
        var idRuta: String

        init(color: UIColor, linea: String, idRuta: String) {
            self.color = color
            self.linea = linea
            self.idRuta = idRuta
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

    /// Shape real del feed GTFS.
    ///
    /// Ya NO hay trazado de respaldo. Antes, si la ruta no traía geometría, se
    /// dibujaba una línea inventada: el usuario veía como "su recorrido" un
    /// trazado que no era el suyo, sin nada que lo delatara. Ahora se muestra
    /// un estado vacío explícito.
    private var coordenadas: [CLLocationCoordinate2D] { ruta.shape }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if coordenadas.count >= 2 {
                MapaRutaRepresentable(
                    coordenadas: coordenadas,
                    colorLinea: UIColor(ruta.colorLinea),
                    linea: ruta.linea,
                    idRuta: ruta.id,
                    tituloOrigen: ruta.paradaInicio,
                    tituloDestino: ruta.paradaFin
                )
            } else {
                sinTrazado
            }

            // Badge "RECORRIDO OFICIAL"
            HStack(spacing: 5) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                Text(L.t("RECORRIDO OFICIAL", "OFFICIAL ROUTE"))
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

    /// Estado honesto para una ruta sin geometría en el feed.
    private var sinTrazado: some View {
        ZStack {
            Color.surfaceContainerLow
            VStack(spacing: 8) {
                Image(systemName: "map")
                    .font(.system(size: 26))
                    .foregroundStyle(.onSurfaceVariant.opacity(0.55))
                Text(L.t("Esta línea no trae trazado en el feed",
                         "This line has no geometry in the feed"))
                    .font(.bodySm)
                    .foregroundStyle(.onSurfaceVariant)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    RutaMapKitView(ruta: RutaOpcion(
        id: "17419574", linea: "C-06", empresa: "Titanic Express",
        recorrido: "Vía Panamericana Norte (ramal circular)",
        frecuenciaMin: 5, duracionMin: 45, costo: "S/ 2.00",
        numParaderos: 120, distanciaKm: 18.4, colorLinea: Color(hex: "#9999FF"),
        shape: [], paraderos: [],
        paradaInicio: "Panamericana Norte", paradaFin: "Av. América"
    ))
    .frame(height: 280)
    .padding()
}

