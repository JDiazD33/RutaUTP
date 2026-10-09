import SwiftUI

/// Solo los valores que presenta una tarjeta; la posición vive en la flota.
struct BusPanelItem: Identifiable, Equatable {
    let id: String
    let rutaId: String
    let linea: String
    let empresa: String
    let tipo: String
    let variante: String
    let minutosLlegada: Int?
    let colorDeRuta: Color?
    var color: Color { colorDeRuta ?? .appPrimary }
    let fuente: VehicleTrackingSource

    init(_ bus: BusAnimado) {
        id = bus.id
        rutaId = bus.rutaId
        linea = bus.linea
        empresa = bus.empresa
        tipo = bus.tipo
        variante = bus.variante
        minutosLlegada = bus.minutosLlegada
        colorDeRuta = bus.colorDeRuta
        fuente = bus.fuente
    }

    var ramalTexto: String {
        variante.isEmpty ? L.t("S/D", "N/A") : L.t("Ramal \(variante)", "Branch \(variante)")
    }

    var etiquetaLlegada: String {
        guard let minutosLlegada else { return L.t("SIN ETA", "NO ETA") }
        return fuente == .real ? "~\(minutosLlegada) MIN" : "\(minutosLlegada) MIN"
    }
}
