import SwiftUI
import CoreLocation
import MapKit

/// La ficha pública muestra corroboraciones; los votos se envían desde el viaje.
///
/// Es la fila de ocupación de la ficha del micro: usa su misma fila de etiqueta
/// y valor, y el fondo lo aporta el grupo de datos de la ficha.
struct BusOccupancyPanel: View {
    let vehicleID: String?
    @StateObject private var service = OccupancyService()

    private var reading: OccupancyReading? {
        service.buses.first { $0.vehicleId == vehicleID }
    }

    var body: some View {
        BusDetailRow(
            titulo: L.t("Ocupación", "Occupancy"),
            simbolo: "person.2.fill",
            valor: reading?.state.title ?? (service.ready
                ? L.t("Sin confirmar", "Unconfirmed")
                : L.t("Sin datos recientes", "No recent data")),
            tinte: tinte,
            notas: notas
        )
        .onAppear { if vehicleID != nil { service.start() } }
        .onDisappear { service.stop() }
    }

    /// Un micro lleno se marca en rojo; sin lectura, el valor queda atenuado.
    private var tinte: Color {
        guard let reading else { return .onSurfaceVariant }
        return reading.state == .full ? .appError : .onSurface
    }

    private var notas: [String] {
        var notas: [String] = []
        if let reading {
            notas.append(L.f("{0} personas coinciden", "{0} people agree", ["\(reading.confirmations)"]))
        }
        notas.append(vehicleID == nil
            ? L.t("Disponible para vehículos reales.", "Available for real vehicles.")
            : L.t("Busca tu ruta y confirma «Sí, ya subí» para indicar cómo va tu micro.",
                  "Find your route and confirm ‘Yes, I'm on board’ to report bus occupancy."))
        return notas
    }
}
