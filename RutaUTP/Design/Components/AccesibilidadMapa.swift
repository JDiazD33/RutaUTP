import SwiftUI
import MapKit
import UIKit

/// Alternativa a tocar una coordenada: elegir explícitamente un paradero del feed.
/// No confirma un abordaje ni publica un reporte por sí misma.
struct SelectorParaderoAccesible: View {
    let paraderos: [ParaderoGTFS]
    let seleccion: CLLocationCoordinate2D?
    var onSeleccionar: (CLLocationCoordinate2D) -> Void
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverOn

    private var indice: Binding<Int> {
        Binding(get: {
            guard let seleccion else { return -1 }
            return paraderos.firstIndex {
                abs($0.lat - seleccion.latitude) < 1e-9 && abs($0.lon - seleccion.longitude) < 1e-9
            } ?? -1
        }, set: { nuevo in
            guard paraderos.indices.contains(nuevo) else { return }
            onSeleccionar(paraderos[nuevo].coordinate)
        })
    }

    var body: some View {
        if voiceOverOn, !paraderos.isEmpty {
            Picker(L.t("Elegir paradero de referencia", "Choose a reference stop"), selection: indice) {
                Text(L.t("Seleccionar paradero", "Select a stop")).tag(-1)
                ForEach(paraderos.indices, id: \.self) { i in
                    Text(paraderos[i].nombre).tag(i)
                }
            }
            .pickerStyle(.menu)
            .padding(8)
            .frame(minHeight: 44)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityHint(L.t("Coloca el punto en un paradero de esta línea; después puedes confirmar", "Places the point at a stop on this line; you can then confirm"))
            .accessibilityValue(seleccion.map { punto in
                paraderos.first { abs($0.lat - punto.latitude) < 1e-9 && abs($0.lon - punto.longitude) < 1e-9 }?.nombre
                    ?? MovimientoPuntoMapa.texto(punto)
            } ?? L.t("Sin punto seleccionado", "No point selected"))
            .accessibilityActions {
                if let seleccion {
                    ForEach(MovimientoPuntoMapa.direcciones.indices, id: \.self) { i in
                        let direccion = MovimientoPuntoMapa.direcciones[i]
                        Button(direccion.nombre) {
                            let punto = MovimientoPuntoMapa.mover(seleccion, norte: direccion.norte, este: direccion.este)
                            onSeleccionar(punto)
                            UIAccessibility.post(notification: .announcement, argument: MovimientoPuntoMapa.texto(punto))
                        }
                    }
                }
            }
        }
    }
}

/// El selector de puntos UIKit comparte las mismas acciones en sus tres consumidores.
extension MapaElegirLugar.Coordinator {
    func configurarAccesibilidad(_ mapa: MKMapView, seleccion: CLLocationCoordinate2D?) {
        let titulo = L.t("Seleccionar punto del mapa", "Select a map point")
        mapa.isAccessibilityElement = true
        if mapa.accessibilityLabel != titulo {
            mapa.accessibilityLabel = titulo
            mapa.accessibilityHint = L.t("Usa Acciones para mover el punto unos 50 metros o seleccionar el centro visible", "Use Actions to move the point about 50 meters or select the visible center")
            mapa.accessibilityCustomActions = MovimientoPuntoMapa.direcciones.map { nombre, norte, este in
                UIAccessibilityCustomAction(name: nombre) { [weak self, weak mapa] _ in
                    guard let self, let mapa else { return false }
                    let punto = MovimientoPuntoMapa.mover(self.pin?.coordinate ?? mapa.region.center, norte: norte, este: este)
                    mapa.setCenter(punto, animated: false)
                    self.elegirPuntoAccesible(punto)
                    return true
                }
            } + [UIAccessibilityCustomAction(name: L.t("Seleccionar centro visible", "Select visible center")) { [weak self, weak mapa] _ in
                guard let self, let mapa else { return false }
                self.elegirPuntoAccesible(mapa.region.center)
                return true
            }]
        }
        mapa.accessibilityLanguage = L.esIngles ? "en" : "es-PE"
        mapa.accessibilityValue = seleccion.map(MovimientoPuntoMapa.texto)
            ?? L.t("Sin punto seleccionado", "No point selected")
    }

    private func elegirPuntoAccesible(_ punto: CLLocationCoordinate2D) {
        onTocar(punto)
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: MovimientoPuntoMapa.texto(punto))
        }
    }

}

private enum MovimientoPuntoMapa {
    static var direcciones: [(nombre: String, norte: Double, este: Double)] {
        [(L.t("Mover punto al norte", "Move point north"), 1, 0),
         (L.t("Mover punto al sur", "Move point south"), -1, 0),
         (L.t("Mover punto al este", "Move point east"), 0, 1),
         (L.t("Mover punto al oeste", "Move point west"), 0, -1)]
    }

    static func mover(_ coordenada: CLLocationCoordinate2D, norte: Double, este: Double) -> CLLocationCoordinate2D {
        var punto = coordenada
        punto.latitude = max(-85, min(85, punto.latitude + norte * 0.00045))
        punto.longitude += este * 0.00045 / max(0.01, cos(punto.latitude * .pi / 180))
        punto.longitude = (punto.longitude + 540).truncatingRemainder(dividingBy: 360) - 180
        return punto
    }

    static func texto(_ punto: CLLocationCoordinate2D) -> String {
        let lat = String(format: "%.5f", punto.latitude)
        let lon = String(format: "%.5f", punto.longitude)
        return L.t("Latitud \(lat), longitud \(lon)", "Latitude \(lat), longitude \(lon)")
    }
}
