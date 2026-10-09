import SwiftUI
import MapKit

struct TrackingInstructionPanel: View {
    let vm: RouteTrackingViewModel

    var body: some View {
        // Instrucción principal según estado
        HStack(spacing: 12) {
            Image(systemName: iconoEstado)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(colorEstado)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(colorEstado.opacity(0.15)))

            VStack(alignment: .leading, spacing: 2) {
                Text(instruccion)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.onSurface)
                    .lineLimit(2)
                Text(subtitulo)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.onSurface.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    // MARK: - Estado → UI

    private var iconoEstado: String {
        switch vm.estado {
        case .esperandoGPS:  return "antenna.radiowaves.left.and.right"
        case .sinPermiso:    return "location.slash.fill"
        case .listo:         return "location.fill"
        case .enRuta:        return (vm.journeyLeg == .riding || vm.journeyLeg == .ridingSecond) ? "bus.fill" : "figure.walk"
        case .fueraDeRuta:   return "exclamationmark.triangle.fill"
        case .cercaDestino:  return "bell.badge.fill"
        case .finalizado:    return "checkmark.circle.fill"
        }
    }

    private var colorEstado: Color {
        switch vm.estado {
        case .esperandoGPS:  return Color.onSurface
        case .sinPermiso:    return .red
        case .listo:         return Color(light: "#087C55", dark: "#8affc1")
        case .enRuta:        return Color.primaryContainer
        case .fueraDeRuta:   return .orange
        case .cercaDestino:  return Color(light: "#946200", dark: "#FFD166")
        case .finalizado:    return Color(light: "#087C55", dark: "#8affc1")
        }
    }

    private var instruccion: String {
        switch vm.estado {
        case .esperandoGPS:
            return L.t("Buscando señal GPS…", "Looking for GPS signal…")
        case .sinPermiso:
            return L.t("Activa la ubicación para navegar", "Enable location to navigate")
        case .listo:
            return L.t("GPS listo · elige un destino", "GPS ready · pick a destination")
        case .enRuta:
            switch vm.journeyLeg {
            case .walkingToBoard: return L.t("Camina al paradero de subida", "Walk to your boarding stop")
            case .riding: return L.t("Toma el micro \(vm.rutaGTFS?.linea ?? "")", "Take bus \(vm.rutaGTFS?.linea ?? "")")
            case .transferring: return L.t("Camina al segundo micro", "Walk to the second bus")
            case .ridingSecond: return L.t("Toma el micro ", "Take bus ") + (vm.itinerary?.transfer?.route.linea ?? "")
            case .walkingToDestination: return L.t("Baja y camina a tu destino", "Get off and walk to your destination")
            }
        case .fueraDeRuta(let metros):
            return L.t("Te alejaste de la ruta (\(Int(metros)) m)",
                       "You went off route (\(Int(metros)) m)")
        case .cercaDestino:
            return L.t("Prepárate para llegar", "Get ready to arrive")
        case .finalizado:
            return L.t("¡Llegaste a tu destino!", "You arrived at your destination!")
        }
    }

    private var subtitulo: String {
        switch vm.estado {
        case .esperandoGPS:
            return L.t("Esperando el primer fix del GPS", "Waiting for the first GPS fix")
        case .sinPermiso:
            return L.t("Ajustes → Privacidad → Ubicación", "Settings → Privacy → Location")
        case .listo:
            return L.t("Inicia el viaje para probar el tracking", "Start the trip to test tracking")
        case .enRuta:
            guard let plan = vm.itinerary else { return "" }
            switch vm.journeyLeg {
            case .walkingToBoard: return plan.board.nombre
            case .riding: return L.t("Baja en ", "Get off at ") + plan.firstAlight.nombre
            case .transferring: return plan.transfer?.board.nombre ?? ""
            case .ridingSecond: return L.t("Baja en ", "Get off at ") + plan.alight.nombre
            case .walkingToDestination: return vm.destinoSeleccionado?.label ?? ""
            }
        case .fueraDeRuta:
            return L.t("Recalculando automáticamente", "Recalculating automatically")
        case .cercaDestino:
            return L.t("Llegando a \(vm.destinoSeleccionado?.label ?? "…")",
                       "Arriving at \(vm.destinoSeleccionado?.label ?? "…")")
        case .finalizado:
            return vm.destinoSeleccionado?.label ?? L.t("Destino", "Destination")
        }
    }
}
