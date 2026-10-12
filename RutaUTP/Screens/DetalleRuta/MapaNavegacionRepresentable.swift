// MapaNavegacionRepresentable.swift
// Separado por responsabilidad; conserva el comportamiento existente.

import SwiftUI
import MapKit
import UIKit

// MARK: - Mapa de navegación
struct MapaNavegacionRepresentable: UIViewRepresentable {
    let shape: [CLLocationCoordinate2D]
    let paraderos: [ParaderoGTFS]
    let colorLinea: UIColor
    let colorPosicion: UIColor
    let posicion: CLLocationCoordinate2D?
    @Binding var seguir: Bool
    let modoDemo: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(color: colorLinea, colorPosicion: colorPosicion)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsUserLocation = !modoDemo
        mapView.userTrackingMode = .none
        mapView.isRotateEnabled = false

        if shape.count >= 2 {
            let polyline = MKPolyline(coordinates: shape, count: shape.count)
            mapView.addOverlay(polyline)
            mapView.setVisibleMapRect(polyline.boundingMapRect,
                                      edgePadding: UIEdgeInsets(top: 60, left: 30, bottom: 280, right: 30),
                                      animated: false)
        }

        // Solo paraderos destacados: siguiente no se sabe aquí (cambia),
        // marcamos inicio y fin.
        let visibles = MapaExploradorRepresentable.paraderosVisibles(paraderos)
        for (i, p) in visibles.enumerated() {
            mapView.addAnnotation(ParaderoExploraAnnotation(
                coordinate: p.coordinate, nombre: p.nombre,
                esInicio: i == 0, esFin: i == visibles.count - 1
            ))
        }
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.colorPosicion = colorPosicion
        (mapView.view(for: coordinator.demoPin) as? MKMarkerAnnotationView)?.markerTintColor = colorPosicion
        coordinator.onPan = { seguir = false }
        mapView.showsUserLocation = !modoDemo
        if modoDemo, let posicion {
            if !mapView.annotations.contains(where: { $0 === coordinator.demoPin }) {
                coordinator.demoPin.title = L.t("Tu posición · demo", "Your position · demo")
                mapView.addAnnotation(coordinator.demoPin)
            }
            coordinator.demoPin.coordinate = posicion
        } else {
            mapView.removeAnnotation(coordinator.demoPin)
        }
        if !seguir {
            if coordinator.wasFollowing, let overlay = mapView.overlays.first {
                mapView.setVisibleMapRect(overlay.boundingMapRect,
                    edgePadding: UIEdgeInsets(top: 110, left: 40, bottom: 360, right: 40), animated: true)
            }
            coordinator.wasFollowing = false
            return
        }
        let changedMode = !coordinator.wasFollowing
        coordinator.wasFollowing = true
        guard let posicion else { return }
        if !changedMode, let previous = coordinator.lastCenter,
           PolylineMatching.distanceMeters(previous, posicion) < 8 { return }
        coordinator.lastCenter = posicion
        let region = MKCoordinateRegion(center: posicion,
            span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008))
        mapView.setRegion(region, animated: true)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        let color: UIColor
        var colorPosicion: UIColor
        let demoPin = MKPointAnnotation()
        var wasFollowing = true
        var lastCenter: CLLocationCoordinate2D?
        var onPan: (() -> Void)?

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            let gestures = mapView.subviews.flatMap { $0.gestureRecognizers ?? [] }
            if gestures.contains(where: { $0.state == .began || $0.state == .changed }) {
                // Evita que la siguiente actualización de GPS interrumpa la exploración.
                wasFollowing = false
                onPan?()
            }
        }

        init(color: UIColor, colorPosicion: UIColor) {
            self.color = color
            self.colorPosicion = colorPosicion
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = color
                renderer.lineWidth = 6
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            if annotation === demoPin {
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: "demo") as? MKMarkerAnnotationView)
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "demo")
                view.annotation = annotation
                view.markerTintColor = colorPosicion
                view.glyphImage = UIImage(systemName: "location.fill")
                view.displayPriority = .required
                return view
            }
            guard let paradero = annotation as? ParaderoExploraAnnotation else { return nil }
            if paradero.esFin {
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: "fin")
                            as? MKMarkerAnnotationView)
                            ?? MKMarkerAnnotationView(annotation: nil, reuseIdentifier: "fin")
                view.annotation = paradero
                view.markerTintColor = .systemRed
                view.glyphImage = UIImage(systemName: "flag.fill")
                view.glyphTintColor = .white
                view.titleVisibility = .visible
                return view
            }
            let id = "paradero"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                        ?? MKAnnotationView(annotation: nil, reuseIdentifier: id)
            view.annotation = paradero
            let config = UIImage.SymbolConfiguration(pointSize: 8, weight: .bold)
            view.image = UIImage(systemName: "circle.fill", withConfiguration: config)?
                .withTintColor(.darkGray, renderingMode: .alwaysOriginal)
            view.displayPriority = .defaultLow
            return view
        }
    }
}
