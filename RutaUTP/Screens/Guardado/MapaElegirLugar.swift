//
//  MapaElegirLugar.swift
//  RutaUTP
//
//  Mapa para elegir una ubicación con un tap.
//
//  Compartido por Guardado (elegir ubicación del lugar) y Mapa (elegir
//  destino en el mapa).
//

import SwiftUI
import MapKit
import CoreLocation
import UIKit

// MARK: - Mapa para elegir ubicación (tocable para mover el pin)
/// Mapa para elegir un punto con un tap. Compartido por Guardado (elegir
/// ubicación del lugar) y Mapa (elegir destino en el mapa).
struct MapaElegirLugar: UIViewRepresentable {
    /// Se recibe desde el body SwiftUI para actualizar también el pin existente.
    let colorPin: Color
    /// Coordenada actual del pin (nil = sin pin todavía).
    let coordenada: CLLocationCoordinate2D?
    /// Avisa cuando el usuario toca el mapa para mover el pin.
    var onTocar: (CLLocationCoordinate2D) -> Void
    /// Cambia para re-centrar el mapa sobre `coordenada` (ej. al geocodificar).
    var recentrarTrigger: Int = 0
    /// Cada consumidor puede acercar su selector sin alterar los otros mapas.
    var spanInicial = MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
    var spanRecentrado = MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
    var iconoPin: String = "mappin.circle.fill"
    var centroCamara: CLLocationCoordinate2D?
    var recentrarCamaraTrigger: Int = 0
    var onInteraccion: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onTocar: onTocar, colorPin: UIColor(colorPin), iconoPin: iconoPin,
                    ultimoRecentradoCamara: recentrarCamaraTrigger, onInteraccion: onInteraccion)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsUserLocation = true
        mapView.setRegion(
            MKCoordinateRegion(
                center: coordenada ?? centroCamara ?? .init(latitude: -8.1096, longitude: -79.0287),
                span: spanInicial
            ), animated: false)

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.mapaTocado(_:)))
        mapView.addGestureRecognizer(tap)
        context.coordinator.configurarAccesibilidad(mapView, seleccion: coordenada)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.colorPin = UIColor(colorPin)
        coordinator.iconoPin = iconoPin
        coordinator.onTocar = onTocar
        coordinator.onInteraccion = onInteraccion

        // Pin
        if let coordenada {
            if let pin = coordinator.pin {
                pin.coordinate = coordenada
                if let vistaPin = mapView.view(for: pin) as? MKMarkerAnnotationView {
                    vistaPin.markerTintColor = coordinator.colorPin
                    vistaPin.glyphImage = UIImage(systemName: iconoPin)
                }
            } else {
                let pin = MKPointAnnotation()
                pin.coordinate = coordenada
                pin.title = "Aquí"
                mapView.addAnnotation(pin)
                coordinator.pin = pin
            }
        } else if let pin = coordinator.pin {
            mapView.removeAnnotation(pin)
            coordinator.pin = nil
        }

        // Re-centrado cuando el padre lo pide (geocodificación, no taps)
        if coordinator.ultimoRecentrado != recentrarTrigger {
            coordinator.ultimoRecentrado = recentrarTrigger
            if let coordenada {
                mapView.setRegion(
                    MKCoordinateRegion(
                        center: coordenada,
                        span: spanRecentrado
                    ), animated: true)
            }
        }
        // La flecha mueve únicamente la cámara; nunca sustituye el pin.
        if coordinator.ultimoRecentradoCamara != recentrarCamaraTrigger {
            coordinator.ultimoRecentradoCamara = recentrarCamaraTrigger
            if let centroCamara {
                mapView.setRegion(MKCoordinateRegion(center: centroCamara, span: spanRecentrado),
                                  animated: !UIAccessibility.isReduceMotionEnabled)
            }
        }
        coordinator.configurarAccesibilidad(mapView, seleccion: coordenada)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var pin: MKPointAnnotation?
        var ultimoRecentrado = 0
        var onTocar: (CLLocationCoordinate2D) -> Void
        var colorPin: UIColor
        var iconoPin: String
        var ultimoRecentradoCamara: Int
        var onInteraccion: () -> Void

        init(onTocar: @escaping (CLLocationCoordinate2D) -> Void, colorPin: UIColor, iconoPin: String,
             ultimoRecentradoCamara: Int, onInteraccion: @escaping () -> Void) {
            self.onTocar = onTocar
            self.colorPin = colorPin
            self.iconoPin = iconoPin
            self.ultimoRecentradoCamara = ultimoRecentradoCamara
            self.onInteraccion = onInteraccion
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            // Reconoce arrastre/zoom con los gestos públicos de UIKit sin
            // añadir reconocedores que compitan con MapKit o el scroll.
            func hayGestoActivo(_ vista: UIView) -> Bool {
                (vista.gestureRecognizers ?? []).contains { $0.state == .began || $0.state == .changed }
                    || vista.subviews.contains(where: hayGestoActivo)
            }
            if hayGestoActivo(mapView) { onInteraccion() }
        }

        @objc func mapaTocado(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }
            let punto = gesture.location(in: mapView)
            let coord = mapView.convert(punto, toCoordinateFrom: mapView)
            onTocar(coord)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            let id = "pin-elegir"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                        ?? MKMarkerAnnotationView(annotation: nil, reuseIdentifier: id)
            view.annotation = annotation
            view.markerTintColor = colorPin
            view.glyphImage = UIImage(systemName: iconoPin)
            view.glyphTintColor = .white
            view.canShowCallout = false
            return view
        }
    }
}
