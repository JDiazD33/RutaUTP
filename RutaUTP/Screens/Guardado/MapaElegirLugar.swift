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

enum ControlesMapaLugar {
    case ninguno, ampliar, ubicacionYCiudad
}

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
    var controles: ControlesMapaLugar = .ninguno
    var espacioSuperiorControles: CGFloat = 0
    var onExpandir: (() -> Void)?
    var onUbicar: () -> Void = {}
    @Environment(\.colorScheme) private var colorScheme

    private var acento: UIColor { UIColor(colorScheme == .dark ? .primaryFixed : .appPrimary) }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTocar: onTocar, colorPin: UIColor(colorPin), iconoPin: iconoPin,
                    ultimoRecentradoCamara: recentrarCamaraTrigger, onInteraccion: onInteraccion,
                    onExpandir: onExpandir, onUbicar: onUbicar)
    }

    func makeUIView(context: Context) -> ContenedorMapaLugar {
        let contenedor = ContenedorMapaLugar(coordinator: context.coordinator)
        let mapView = contenedor.mapa
        mapView.delegate = context.coordinator
        context.coordinator.mapa = mapView
        context.coordinator.contenedor = contenedor
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
        contenedor.configurarControles(tipo: controles, acento: acento,
                                       espacioSuperior: espacioSuperiorControles)
        return contenedor
    }

    func updateUIView(_ contenedor: ContenedorMapaLugar, context: Context) {
        let mapView = contenedor.mapa
        let coordinator = context.coordinator
        coordinator.colorPin = UIColor(colorPin)
        coordinator.iconoPin = iconoPin
        coordinator.onTocar = onTocar
        coordinator.onInteraccion = onInteraccion
        coordinator.onExpandir = onExpandir
        coordinator.onUbicar = onUbicar
        contenedor.configurarControles(tipo: controles, acento: acento,
                                       espacioSuperior: espacioSuperiorControles)

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
                mapView.setUserTrackingMode(.none, animated: false)
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
            if let centroCamara, mapView.userTrackingMode == .none {
                mapView.setRegion(MKCoordinateRegion(center: centroCamara, span: spanRecentrado),
                                  animated: !UIAccessibility.isReduceMotionEnabled)
            }
        }
        coordinator.configurarAccesibilidad(mapView, seleccion: coordenada)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        weak var mapa: MKMapView?
        weak var contenedor: ContenedorMapaLugar?
        var pin: MKPointAnnotation?
        var ultimoRecentrado = 0
        var onTocar: (CLLocationCoordinate2D) -> Void
        var colorPin: UIColor
        var iconoPin: String
        var ultimoRecentradoCamara: Int
        var onInteraccion: () -> Void
        var onExpandir: (() -> Void)?
        var onUbicar: () -> Void

        init(onTocar: @escaping (CLLocationCoordinate2D) -> Void, colorPin: UIColor, iconoPin: String,
             ultimoRecentradoCamara: Int, onInteraccion: @escaping () -> Void,
             onExpandir: (() -> Void)?, onUbicar: @escaping () -> Void) {
            self.onTocar = onTocar
            self.colorPin = colorPin
            self.iconoPin = iconoPin
            self.ultimoRecentradoCamara = ultimoRecentradoCamara
            self.onInteraccion = onInteraccion
            self.onExpandir = onExpandir
            self.onUbicar = onUbicar
        }

        func mapView(_ mapView: MKMapView, didChange mode: MKUserTrackingMode, animated: Bool) {
            contenedor?.actualizarSeguimiento(mode)
        }

        @objc func centrarUsuario() {
            guard let mapa else { return }
            // La flecha sigue el punto azul sin esperar al lector puntual.
            // Cancela el centrado automático para que no deshaga esta acción.
            onInteraccion()
            AppHaptics.impact(.light)
            mapa.setUserTrackingMode(.follow, animated: !UIAccessibility.isReduceMotionEnabled)
            onUbicar()
        }

        @objc func verCiudad() {
            guard let mapa else { return }
            onInteraccion()
            AppHaptics.impact(.light)
            mapa.setUserTrackingMode(.none, animated: false)
            mapa.setRegion(
                MKCoordinateRegion(center: DestinosFijos.centroTrujillo,
                                   latitudinalMeters: 12_000, longitudinalMeters: 12_000),
                animated: !UIAccessibility.isReduceMotionEnabled)
        }

        @objc func expandirMapa() { onExpandir?() }

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
            mapView.setUserTrackingMode(.none, animated: false)
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

/// Cada selector conserva sus propios controles y su propio mapa, también
/// cuando el formulario queda debajo del selector a pantalla completa.
final class ContenedorMapaLugar: UIView {
    let mapa: MKMapView
    private let controles = UIStackView()
    private let botonUbicacion = UIButton(type: .system)
    private let botonCiudad = UIButton(type: .system)
    private let botonExpandir = UIButton(type: .system)
    private lazy var anclajeSuperior = controles.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor)

    init(coordinator: MapaElegirLugar.Coordinator) {
        let nuevoMapa = MKMapView()
        mapa = nuevoMapa
        super.init(frame: .zero)
        mapa.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mapa)
        controles.axis = .horizontal
        controles.spacing = 8
        controles.translatesAutoresizingMaskIntoConstraints = false
        addSubview(controles)
        for control in [botonExpandir, botonUbicacion, botonCiudad] {
            controles.addArrangedSubview(control)
            control.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                control.widthAnchor.constraint(equalToConstant: 44),
                control.heightAnchor.constraint(equalToConstant: 44)
            ])
        }
        configurar(botonUbicacion, simbolo: "location.fill")
        configurar(botonCiudad, simbolo: "map")
        configurar(botonExpandir, simbolo: "arrow.up.left.and.arrow.down.right", compacto: true)
        botonUbicacion.addTarget(coordinator, action: #selector(MapaElegirLugar.Coordinator.centrarUsuario), for: .touchUpInside)
        botonCiudad.addTarget(coordinator, action: #selector(MapaElegirLugar.Coordinator.verCiudad), for: .touchUpInside)
        botonExpandir.addTarget(coordinator, action: #selector(MapaElegirLugar.Coordinator.expandirMapa), for: .touchUpInside)
        botonUbicacion.accessibilityIdentifier = "place-picker.my-location"
        botonCiudad.accessibilityIdentifier = "place-picker.city"
        botonExpandir.accessibilityIdentifier = "place-picker.expand"
        NSLayoutConstraint.activate([
            mapa.topAnchor.constraint(equalTo: topAnchor),
            mapa.bottomAnchor.constraint(equalTo: bottomAnchor),
            mapa.leadingAnchor.constraint(equalTo: leadingAnchor),
            mapa.trailingAnchor.constraint(equalTo: trailingAnchor),
            anclajeSuperior,
            controles.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -12)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func configurar(_ boton: UIButton, simbolo: String, compacto: Bool = false) {
        var configuracion = UIButton.Configuration.plain()
        configuracion.image = UIImage(systemName: simbolo)
        configuracion.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: compacto ? 15 : 18, weight: .semibold)
        configuracion.background.backgroundColor = .secondarySystemGroupedBackground
        configuracion.background.cornerRadius = compacto ? 18 : 22
        if compacto {
            // Fondo visible de 36 puntos; el área táctil conserva 44 puntos.
            configuracion.background.backgroundInsets = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
        }
        boton.configuration = configuracion
    }

    func configurarControles(tipo: ControlesMapaLugar, acento: UIColor, espacioSuperior: CGFloat) {
        anclajeSuperior.constant = 12 + max(0, espacioSuperior)
        mapa.accessibilityIdentifier = tipo == .ampliar ? "place-picker.compact-map"
            : tipo == .ubicacionYCiudad ? "place-picker.full-map" : "place-picker.map"
        controles.isHidden = tipo == .ninguno
        botonExpandir.isHidden = tipo != .ampliar
        botonUbicacion.isHidden = tipo != .ubicacionYCiudad
        botonCiudad.isHidden = tipo != .ubicacionYCiudad
        controles.tintColor = acento
        // El GPS puede tardar o no tener permiso; la flecha sigue visible y
        // recibe toques. MapKit gestiona la cámara, no la visibilidad del botón.
        for boton in [botonUbicacion, botonCiudad, botonExpandir] {
            boton.configuration?.baseForegroundColor = acento
        }
        actualizarSeguimiento(mapa.userTrackingMode)
        botonUbicacion.accessibilityLabel = L.t("Mi ubicación", "My location")
        botonUbicacion.accessibilityHint = L.t("Centra el mapa sin cambiar el lugar marcado", "Centers the map without changing the marked place")
        botonCiudad.accessibilityLabel = L.t("Ver la ciudad", "Show city")
        botonCiudad.accessibilityHint = L.t("Muestra la mayor parte de Trujillo sin cambiar el lugar marcado", "Shows most of Trujillo without changing the marked place")
        botonExpandir.accessibilityLabel = L.t("Expandir mapa", "Expand map")
    }

    func actualizarSeguimiento(_ modo: MKUserTrackingMode) {
        botonUbicacion.isSelected = modo != .none
    }
}
