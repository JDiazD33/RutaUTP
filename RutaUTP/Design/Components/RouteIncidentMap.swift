//
//  RouteIncidentMap.swift
//  RutaUTP
//
//  Mapa de incidencia con trazado de la ruta y leyenda.
//

import SwiftUI
import MapKit

// Ambas vistas comparten el trazado y la selección del punto afectado.
struct RouteIncidentMap: View {
    let route: RutaGTFS
    @Binding var point: CLLocationCoordinate2D?
    @Binding var camera: MapCameraPosition
    /// Se llama cuando el usuario toca el mapa. Permite distinguir "el pin
    /// está donde yo lo puse" de "el pin se puso solo", que es lo que decide
    /// si se recoloca al cambiar de línea.
    var onPointChange: (() -> Void)? = nil

    var body: some View {
        MapReader { proxy in
            Map(position: $camera) {
                MapPolyline(coordinates: route.shape).stroke(route.color, lineWidth: 4)
                if let point {
                    Marker(L.t("Lugar afectado", "Affected location"), coordinate: point)
                        .tint(.orange)
                }
            }
            .onTapGesture { location in
                if let coordinate = proxy.convert(location, from: .local) {
                    point = coordinate
                    onPointChange?()
                }
            }
        }
        .overlay(alignment: .topLeading) {
            LeyendaCoherencia()
                .padding(8)
        }
        .overlay(alignment: .bottomLeading) {
            SelectorParaderoAccesible(paraderos: route.paraderos, seleccion: point) {
                point = $0
                camera = .region(MKCoordinateRegion(center: $0, span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)))
                onPointChange?()
            }
            .padding(12)
        }
    }
}

/// Texto que explica, sobre el propio mapa, si el punto marcado encaja con la
/// ruta elegida. Sin esto el usuario no tiene forma de saber que el punto está
/// mal hasta que el botón de enviar se queda inactivo.
private struct LeyendaCoherencia: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 10, weight: .bold))
                .accessibilityHidden(true)
            Text(L.t("Zona válida de la ruta", "Route's valid area"))
                .font(.caption2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.onSurface)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .allowsHitTesting(false)
    }
}

/// Aviso bajo el mapa: dice por qué el punto no sirve, o confirma que sí.
struct AvisoCoherencia: View {
    let evaluacion: CoherenciaPunto?
    let route: RutaGTFS

    var body: some View {
        if let evaluacion {
            switch evaluacion {
            case .coherente:
                etiqueta(L.t("El punto está sobre el recorrido de ",
                             "The point is on ") + rutaCorta(route),
                         icono: "checkmark.circle.fill", tono: .green)
            case .limite(let d):
                etiqueta(L.f("A {0} m del recorrido. Se aceptará, pero revisa que sea el lugar correcto.", "{0} m from the route. It'll be accepted, but check it's the right spot.", ["\(Int(d.rounded()))"]),
                         icono: "exclamationmark.triangle.fill", tono: .orange)
            case .fueraDeRuta(let d):
                etiqueta(L.f("Este punto está a {0} m de la ruta {1}. No corresponde a esta línea: toca el recorrido azul.", "This point is {0} m from route {1}. It doesn't belong to this line: tap the blue path.", ["\(Int(d.rounded()))", "\(rutaCorta(route))"]),
                         icono: "xmark.octagon.fill", tono: .red)
            }
        }
    }

    private func rutaCorta(_ r: RutaGTFS) -> String { "\(r.linea) \(r.variante)" }

    private func etiqueta(_ texto: String, icono: String, tono: Color) -> some View {
        Label(texto, systemImage: icono)
            .font(.footnote)
            .foregroundStyle(tono)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
