import SwiftUI

/// La identidad es la unidad del backend, nunca el número de línea.
struct BusOccupancyPanel: View {
    let vehicleID: String?
    @StateObject private var service = OccupancyService()
    @State private var selection: BusOccupancyState?
    @State private var confirming = false

    private var reading: OccupancyReading? {
        service.buses.first { $0.vehicleId == vehicleID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(L.t("Ocupación", "Occupancy"), systemImage: "person.2.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(statusText)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(reading?.state == .full ? Color.orange : Color.onSurface)
            }
            if vehicleID != nil {
                if let reading {
                    Text(L.t("\(reading.confirmations) cuentas coinciden · vence ",
                             "\(reading.confirmations) accounts agree · expires ")
                         + Date(timeIntervalSince1970: reading.expiresAt).formatted(date: .omitted, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    ForEach(BusOccupancyState.allCases, id: \.self) { state in
                        Button {
                            selection = state
                            confirming = true
                        } label: {
                            Label(state.title, systemImage: state == .empty ? "person" : "person.3.fill")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!service.ready || service.sending)
                        .accessibilityLabel(L.t("Reportar bus ", "Report bus ") + state.title)
                    }
                }
                if service.sending {
                    ProgressView(L.t("Esperando confirmación…", "Waiting for confirmation…"))
                        .font(.caption)
                }
                if let result = service.result {
                    Text(result).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(service.ready
                         ? L.t("Reporta solo si estás a bordo y con «Ayudar con ubicaciones» activo. Se requieren dos cuentas; los reportes duran 3 minutos.",
                               "Report only when aboard with location contributions enabled. Two accounts are required; reports last 3 minutes.")
                         : L.t("No hay conexión con ocupación. Espera a que el servicio esté disponible.",
                               "Occupancy is offline. Wait for the service to become available."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(L.t("Disponible en buses en vivo. Los buses de demostración no reciben reportes.",
                         "Available for live buses. Demo buses don't accept reports."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 12))
        .confirmationDialog(L.t("¿Estás en este bus y confirmas que está ", "Are you aboard this bus and confirm it is ")
                            + (selection?.title.lowercased() ?? "") + "?",
                            isPresented: $confirming, titleVisibility: .visible) {
            if let selection, let vehicleID {
                Button(L.t("Sí, reportar ", "Yes, report ") + selection.title.lowercased()) {
                    service.send(vehicleID: vehicleID, state: selection)
                }
            }
            Button(L.t("Cancelar", "Cancel"), role: .cancel) {}
        }
        .onAppear { if vehicleID != nil { service.start() } }
        .onDisappear { service.stop() }
    }

    private var statusText: String {
        guard vehicleID != nil else { return L.t("Demo", "Demo") }
        guard service.ready else { return L.t("No disponible", "Unavailable") }
        return reading?.state.title ?? L.t("Sin confirmar", "Unconfirmed")
    }
}
