import SwiftUI
import CoreLocation
import MapKit

/// La ficha pública muestra corroboraciones; los votos se envían desde el viaje.
struct BusOccupancyPanel: View {
    let vehicleID: String?
    @StateObject private var service = OccupancyService()

    private var reading: OccupancyReading? {
        service.buses.first { $0.vehicleId == vehicleID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(L.t("Ocupación", "Occupancy"), systemImage: "person.2.fill")
                Spacer()
                Text(reading?.state.title ?? (service.ready
                    ? L.t("Sin confirmar", "Unconfirmed")
                    : L.t("Sin datos recientes", "No recent data")))
                    .fontWeight(.semibold)
            }
            if let reading {
                Text(L.f("{0} personas coinciden", "{0} people agree", ["\(reading.confirmations)"]))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(vehicleID == nil
                 ? L.t("Disponible para vehículos reales.", "Available for real vehicles.")
                 : L.t("Busca tu ruta y confirma «Sí, ya subí» para indicar cómo va tu micro.",
                       "Find your route and confirm ‘Yes, I'm on board’ to report bus occupancy."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 12))
        .onAppear { if vehicleID != nil { service.start() } }
        .onDisappear { service.stop() }
    }
}
