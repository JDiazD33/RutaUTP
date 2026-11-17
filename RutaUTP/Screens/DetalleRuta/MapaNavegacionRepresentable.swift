// MapaNavegacionRepresentable.swift
// Mapa de la navegación: recorrido, paraderos, paradero de bajada, posición
// y cambios de ruta confirmados que afectan a la línea.

import SwiftUI
import MapKit
import UIKit

/// Paradero donde termina el viaje de la persona.
private final class DestinoNavegacionAnnotation: MKPointAnnotation {}

/// Cambio de ruta confirmado por la comunidad.
private final class CambioNavegacionAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let motivo: MotivoCambioRuta
    let title: String?

    init(_ cambio: CambioRutaEnMapa) {
        coordinate = cambio.aviso.coordenada
        motivo = cambio.aviso.motivo
        title = cambio.aviso.motivo.tituloAviso
    }
}

/// Tramo que la línea deja de recorrer (punteado) o calle por la que va ahora.
private final class TrazoCambioNavegacion: MKPolyline {
    var punteado = false
    var color = UIColor.systemBlue
}

// MARK: - Mapa de navegación
struct MapaNavegacionRepresentable: UIViewRepresentable {
    let shape: [CLLocationCoordinate2D]
    let paraderos: [ParaderoGTFS]
    let colorLinea: UIColor
    let colorPosicion: UIColor
    let posicion: CLLocationCoordinate2D?
    /// Punto donde la persona baja y su nombre visible.
    let destino: CLLocationCoordinate2D?
    let nombreDestino: String
    let cambios: [CambioRutaEnMapa]
    @Binding var seguir: Bool
    let modoDemo: Bool
    /// Cambia este valor para volver a encuadrar el recorrido completo.
    var ajustarTrigger: Int = 0
    /// Espacio que ocupan la cabecera y el panel sobre el mapa.
    var margenes = UIEdgeInsets(top: 110, left: 32, bottom: 360, right: 72)
    var reducirMovimiento = false
    var alTocarCambio: () -> Void = {}

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
        mapView.showsCompass = false

        if shape.count >= 2 {
            let polyline = MKPolyline(coordinates: shape, count: shape.count)
            mapView.addOverlay(polyline)
            context.coordinator.limites = polyline.boundingMapRect
            mapView.setVisibleMapRect(polyline.boundingMapRect, edgePadding: margenes, animated: false)
        }

        // El paradero siguiente cambia con el avance, así que aquí solo van
        // los puntos del recorrido. El de bajada tiene su propio marcador.
        for paradero in MapaExploradorRepresentable.paraderosVisibles(paraderos) {
            mapView.addAnnotation(ParaderoExploraAnnotation(coordinate: paradero.coordinate,
                                                            nombre: paradero.nombreVisible))
        }
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.colorPosicion = colorPosicion
        (mapView.view(for: coordinator.demoPin) as? MKMarkerAnnotationView)?.markerTintColor = colorPosicion
        coordinator.onPan = { seguir = false }
        coordinator.alTocarCambio = alTocarCambio
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
        actualizarDestino(mapView, coordinator)
        actualizarCambios(mapView, coordinator)

        let animar = !reducirMovimiento
        if coordinator.ultimoAjuste != ajustarTrigger {
            coordinator.ultimoAjuste = ajustarTrigger
            coordinator.wasFollowing = false
            encuadrarRecorrido(mapView, coordinator, animated: animar)
            return
        }
        if !seguir {
            if coordinator.wasFollowing { encuadrarRecorrido(mapView, coordinator, animated: animar) }
            coordinator.wasFollowing = false
            return
        }
        let changedMode = !coordinator.wasFollowing
        coordinator.wasFollowing = true
        guard let posicion else { return }
        if !changedMode, let previous = coordinator.lastCenter,
           PolylineMatching.distanceMeters(previous, posicion) < 8 { return }
        coordinator.lastCenter = posicion
        // Unos 800 m alrededor de la posición, dentro del espacio que dejan
        // libre la cabecera y el panel: la posición no queda bajo el panel.
        let lado = 800 * MKMapPointsPerMeterAtLatitude(posicion.latitude)
        let centro = MKMapPoint(posicion)
        let cercania = MKMapRect(x: centro.x - lado / 2, y: centro.y - lado / 2, width: lado, height: lado)
        if mapView.bounds.width > margenes.left + margenes.right,
           mapView.bounds.height > margenes.top + margenes.bottom {
            mapView.setVisibleMapRect(cercania, edgePadding: margenes, animated: animar)
        } else {
            mapView.setVisibleMapRect(cercania, animated: animar)
        }
    }

    static func dismantleUIView(_ mapView: MKMapView, coordinator: Coordinator) {
        mapView.delegate = nil
        mapView.showsUserLocation = false
    }

    private func encuadrarRecorrido(_ mapView: MKMapView, _ coordinator: Coordinator, animated: Bool) {
        guard !coordinator.limites.isNull,
              mapView.bounds.width > margenes.left + margenes.right,
              mapView.bounds.height > margenes.top + margenes.bottom else { return }
        mapView.setVisibleMapRect(coordinator.limites, edgePadding: margenes, animated: animated)
    }

    private func actualizarDestino(_ mapView: MKMapView, _ coordinator: Coordinator) {
        guard let destino else {
            mapView.removeAnnotation(coordinator.destinoPin)
            return
        }
        let pin = coordinator.destinoPin
        if pin.coordinate.latitude != destino.latitude || pin.coordinate.longitude != destino.longitude {
            pin.coordinate = destino
        }
        if pin.title != nombreDestino {
            pin.title = nombreDestino
            mapView.view(for: pin)?.accessibilityLabel = L.t("Bajas en", "You get off at") + " " + nombreDestino
        }
        if !mapView.annotations.contains(where: { $0 === pin }) { mapView.addAnnotation(pin) }
    }

    /// Los avisos cambian pocas veces en un viaje; el mapa solo se toca entonces.
    private func actualizarCambios(_ mapView: MKMapView, _ coordinator: Coordinator) {
        let firma = cambios.map { "\($0.id)|\($0.tramo.count)|\($0.calleNueva.count)" }.joined(separator: ",")
        guard coordinator.firmaCambios != firma else { return }
        coordinator.firmaCambios = firma
        mapView.removeOverlays(mapView.overlays.filter { $0 is TrazoCambioNavegacion })
        mapView.removeAnnotations(mapView.annotations.filter { $0 is CambioNavegacionAnnotation })
        for cambio in cambios {
            let color = UIColor(cambio.aviso.motivo.tinta)
            if cambio.tramo.count >= 2 {
                let tramo = TrazoCambioNavegacion(coordinates: cambio.tramo, count: cambio.tramo.count)
                tramo.punteado = true
                tramo.color = color
                mapView.addOverlay(tramo)
            }
            if cambio.calleNueva.count >= 2 {
                let calle = TrazoCambioNavegacion(coordinates: cambio.calleNueva, count: cambio.calleNueva.count)
                calle.color = color
                mapView.addOverlay(calle)
            }
            mapView.addAnnotation(CambioNavegacionAnnotation(cambio))
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        let color: UIColor
        var colorPosicion: UIColor
        let demoPin = MKPointAnnotation()
        fileprivate let destinoPin = DestinoNavegacionAnnotation()
        var limites = MKMapRect.null
        var wasFollowing = true
        var lastCenter: CLLocationCoordinate2D?
        var ultimoAjuste = 0
        var firmaCambios = ""
        var onPan: (() -> Void)?
        var alTocarCambio: (() -> Void)?

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
            if let cambio = overlay as? TrazoCambioNavegacion {
                let renderer = MKPolylineRenderer(polyline: cambio)
                renderer.strokeColor = cambio.color
                renderer.lineWidth = cambio.punteado ? 5 : 6
                renderer.lineCap = .round
                renderer.lineJoin = .round
                if cambio.punteado { renderer.lineDashPattern = [2, 9] }
                return renderer
            }
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

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            guard annotation is CambioNavegacionAnnotation else { return }
            mapView.deselectAnnotation(annotation, animated: false)
            alTocarCambio?()
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
            if let destino = annotation as? DestinoNavegacionAnnotation {
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: "destino")
                            as? MKMarkerAnnotationView)
                            ?? MKMarkerAnnotationView(annotation: nil, reuseIdentifier: "destino")
                view.annotation = destino
                view.markerTintColor = .systemRed
                view.glyphImage = UIImage(systemName: "flag.fill")
                view.glyphTintColor = .white
                view.titleVisibility = .visible
                view.displayPriority = .required
                view.animatesWhenAdded = false
                view.isAccessibilityElement = true
                view.accessibilityLabel = L.t("Bajas en", "You get off at") + " " + (destino.title ?? "")
                return view
            }
            if let cambio = annotation as? CambioNavegacionAnnotation {
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: "cambio")
                            as? MKMarkerAnnotationView)
                            ?? MKMarkerAnnotationView(annotation: nil, reuseIdentifier: "cambio")
                view.annotation = cambio
                view.markerTintColor = UIColor(cambio.motivo.tinta)
                view.glyphImage = UIImage(systemName: cambio.motivo.icono)
                view.glyphTintColor = .systemBackground
                view.titleVisibility = .adaptive
                view.displayPriority = .defaultHigh
                view.canShowCallout = false
                view.isAccessibilityElement = true
                view.accessibilityLabel = cambio.motivo.tituloAviso
                view.accessibilityTraits = .button
                return view
            }
            guard let paradero = annotation as? ParaderoExploraAnnotation else { return nil }
            let id = "paradero"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                        ?? MKAnnotationView(annotation: nil, reuseIdentifier: id)
            view.annotation = paradero
            // Punto oscuro con borde claro: se distingue en mapa claro y oscuro.
            let config = UIImage.SymbolConfiguration(pointSize: 8, weight: .bold)
            view.image = UIImage(systemName: "circle.fill", withConfiguration: config)?
                .withTintColor(.black, renderingMode: .alwaysOriginal)
            view.layer.shadowColor = UIColor.white.cgColor
            view.layer.shadowOpacity = 1
            view.layer.shadowRadius = 1
            view.layer.shadowOffset = .zero
            view.displayPriority = .defaultLow
            return view
        }
    }
}
