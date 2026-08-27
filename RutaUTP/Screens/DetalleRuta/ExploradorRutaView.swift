//
//  ExploradorRutaView.swift
//  RutaUTP
//
//  Mapa a pantalla completa para explorar el recorrido REAL de una ruta
//  (shape GTFS): pan/zoom libres, paraderos sobre el trazado y leyenda
//  con los datos oficiales del feed.
//
//  Se abre desde DetalleRutaView al tocar el mapa de la ruta.
//

import SwiftUI
import MapKit

// MARK: - Anotaciones
final class ParaderoExploraAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let nombre: String
    let esInicio: Bool
    let esFin: Bool

    var title: String? { esInicio || esFin ? nombre : nil }

    init(coordinate: CLLocationCoordinate2D, nombre: String,
         esInicio: Bool = false, esFin: Bool = false) {
        self.coordinate = coordinate
        self.nombre = nombre
        self.esInicio = esInicio
        self.esFin = esFin
    }
}

// MARK: - Mapa interactivo
struct MapaExploradorRepresentable: UIViewRepresentable {
    let coordenadas: [CLLocationCoordinate2D]
    let colorLinea: UIColor
    let paraderos: [ParaderoGTFS]
    /// Cambia este valor para re-encuadrar el mapa al recorrido completo.
    var ajustarTrigger: Int = 0

    func makeCoordinator() -> Coordinator {
        Coordinator(color: colorLinea)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.showsScale = true

        // Trazo del recorrido
        if coordenadas.count >= 2 {
            let polyline = MKPolyline(coordinates: coordenadas, count: coordenadas.count)
            mapView.addOverlay(polyline)
            context.coordinator.encuadrar(mapView, polyline: polyline)
        }

        // Paraderos (decimados para no saturar; inicio y fin siempre)
        let visibles = Self.paraderosVisibles(paraderos)
        for (i, p) in visibles.enumerated() {
            mapView.addAnnotation(ParaderoExploraAnnotation(
                coordinate: p.coordinate,
                nombre: p.nombre,
                esInicio: i == 0,
                esFin: i == visibles.count - 1
            ))
        }

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        if context.coordinator.ultimoAjuste != ajustarTrigger {
            context.coordinator.ultimoAjuste = ajustarTrigger
            if coordenadas.count >= 2 {
                let polyline = MKPolyline(coordinates: coordenadas, count: coordenadas.count)
                context.coordinator.encuadrar(mapView, polyline: polyline)
            }
        }
    }

    /// Máximo ~70 paraderos en el mapa para que sea legible.
    static func paraderosVisibles(_ paraderos: [ParaderoGTFS]) -> [ParaderoGTFS] {
        guard paraderos.count > 70 else { return paraderos }
        let paso = Double(paraderos.count) / 70.0
        var visibles = (0..<70).map { paraderos[min(Int(Double($0) * paso), paraderos.count - 1)] }
        if let primero = paraderos.first, visibles.first?.id != primero.id {
            visibles.insert(primero, at: 0)
        }
        if let ultimo = paraderos.last, visibles.last?.id != ultimo.id {
            visibles.append(ultimo)
        }
        return visibles
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        let color: UIColor
        var ultimoAjuste: Int = 0

        init(color: UIColor) {
            self.color = color
        }

        func encuadrar(_ mapView: MKMapView, polyline: MKPolyline) {
            mapView.setVisibleMapRect(
                polyline.boundingMapRect,
                edgePadding: UIEdgeInsets(top: 120, left: 40, bottom: 320, right: 40),
                animated: true
            )
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
            if annotation is MKUserLocation { return nil }
            guard let paradero = annotation as? ParaderoExploraAnnotation else { return nil }

            // Inicio / fin con marcador grande
            if paradero.esInicio || paradero.esFin {
                let id = paradero.esInicio ? "inicio" : "fin"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id)
                            as? MKMarkerAnnotationView)
                            ?? MKMarkerAnnotationView(annotation: nil, reuseIdentifier: id)
                view.annotation = paradero
                view.markerTintColor = paradero.esInicio ? color : .systemRed
                view.glyphTintColor = .white
                view.glyphImage = UIImage(systemName: paradero.esInicio ? "play.fill" : "flag.fill")
                view.titleVisibility = .visible
                view.canShowCallout = true
                return view
            }

            // Paraderos intermedios: punto pequeño
            let id = "paradero"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id)
                        as? MKAnnotationView)
                        ?? MKAnnotationView(annotation: nil, reuseIdentifier: id)
            view.annotation = paradero
            let config = UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)
            view.image = UIImage(systemName: "circle.fill", withConfiguration: config)?
                .withTintColor(.darkGray, renderingMode: .alwaysOriginal)
            view.canShowCallout = true
            view.displayPriority = .defaultLow
            return view
        }
    }
}

// MARK: - Vista
struct ExploradorRutaView: View {
    let ruta: RutaOpcion

    @Environment(\.dismiss) private var dismiss
    @State private var ajustarTrigger: Int = 0

    var body: some View {
        ZStack(alignment: .top) {
            MapaExploradorRepresentable(
                coordenadas: ruta.shape,
                colorLinea: UIColor(ruta.colorLinea),
                paraderos: ruta.paraderos,
                ajustarTrigger: ajustarTrigger
            )
            .ignoresSafeArea()

            // Chrome superior
            HStack(alignment: .center, spacing: 10) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.onSurface)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.appSurface))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cerrar")

                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(ruta.colorLinea)
                        .frame(width: 4, height: 22)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Línea \(ruta.linea)")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(.onSurface)
                        Text(ruta.empresa)
                            .font(.system(size: 11))
                            .foregroundStyle(.onSurfaceVariant)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(Color.appSurface)
                        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 3)
                )

                Spacer()

                Button {
                    ajustarTrigger += 1
                } label: {
                    Image(systemName: "scope")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.onSurface)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.appSurface))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Encuadrar recorrido")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // Leyenda inferior
            VStack {
                Spacer()
                leyenda
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Leyenda con datos del feed
    private var leyenda: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(ruta.colorLinea)
                    .frame(width: 5, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(ruta.linea) · \(ruta.empresa)")
                        .font(.headlineSm)
                        .foregroundStyle(.onSurface)
                    Text(ruta.recorrido)
                        .font(.bodySm)
                        .foregroundStyle(.onSurfaceVariant)
                        .lineLimit(1)
                }
                Spacer()
                Text(ruta.frecuenciaTexto)
                    .font(.labelCapsSm)
                    .foregroundStyle(ruta.colorLinea)
                    .appTracking(AppTracking.wideLabel)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(ruta.colorLinea.opacity(0.12)))
            }

            HStack(spacing: 0) {
                datoLeyenda(icono: "clock.fill", valor: ruta.tiempoTexto, etiqueta: "Viaje")
                divisor
                datoLeyenda(icono: "creditcard.fill", valor: ruta.costo, etiqueta: "Tarifa")
                divisor
                datoLeyenda(icono: "mappin.and.ellipse", valor: "\(ruta.numParaderos)", etiqueta: "Paraderos")
                divisor
                datoLeyenda(icono: "point.topleft.down.curvedto.point.bottomright.up",
                            valor: String(format: "%.1f km", ruta.distanciaKm), etiqueta: "Longitud")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 6)
        )
    }

    private var divisor: some View {
        Rectangle()
            .fill(Color.outlineVariant.opacity(0.35))
            .frame(width: 1, height: 34)
    }

    private func datoLeyenda(icono: String, valor: String, etiqueta: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icono)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.appPrimary)
            Text(valor)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.onSurface)
            Text(etiqueta.uppercased())
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.onSurfaceVariant)
                .appTracking(AppTracking.wideLabel)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    ExploradorRutaView(ruta: RutaOpcion(
        id: "17350695", linea: "C-01", empresa: "Nuevos Girasoles",
        recorrido: "Av. Miguel Grau (ramal circular)",
        frecuenciaMin: 4, duracionMin: 77, costo: "S/ 2.50",
        numParaderos: 247, distanciaKm: 21.3, colorLinea: Color(hex: "#00CC00"),
        shape: [], paraderos: [],
        paradaInicio: "Av. Miguel Grau", paradaFin: "Av. Miguel Grau"
    ))
}
