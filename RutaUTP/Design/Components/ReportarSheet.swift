//
//  ReportarSheet.swift
//  RutaUTP
//
//  Sheet compartido para reportar incidentes. Lo usan Mapa (pill REPORTAR)
//  y Seguridad (header y sección Comunidad): una sola implementación.
//
//  - Selector de tipo por tarjetas, con detalle contextual por tipo.
//  - Descripción limitada a 200 caracteres, con contador en vivo.
//

import SwiftUI

struct ReportarSheet: View {


    @Environment(\.dismiss) private var dismiss
    @State private var tipo: TipoReporte = .alerta
    @State private var descripcion: String = ""
    @State private var showSuccess = false
    @State private var showRouteChanges = false
    @StateObject private var routeChanges = RouteChangesService()

    private var puedeEnviar: Bool {
        !descripcion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    encabezado
                    Button { showRouteChanges = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.triangle.branch")
                            Text(L.t("Obras, cierres o cambios de ruta", "Roadworks, closures or route changes"))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right")
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding()
                        .background(Color.appPrimary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.appPrimary)
                    // Selector, detalle y descripción: compartidos con Publicar.
                    SelectorTipoReporte(tipo: $tipo, tiposDisponibles: [.alerta, .sugerencia, .otro])
                    DetalleTipoReporte(tipo: tipo)
                    CampoDescripcionReporte(descripcion: $descripcion, tipo: tipo)
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { botonEnviar }
        }
        .sheet(isPresented: $showRouteChanges) {
            RouteChangesSheet(service: routeChanges)
                .presentationDetents([.large])
                .onAppear { routeChanges.start() }
                .onDisappear { routeChanges.stop() }
        }
        // Mensaje honesto: el reporte no se envía a ningún sitio todavía. El
        // texto anterior ("Reporte enviado / Gracias por colaborar") prometía
        // una operación que no ocurre, que es justo lo que el proyecto evita
        // en otras pantallas (OfflineMapSheet, NegocioDetailCard).
        .alert(L.t("Reporte registrado", "Report recorded"), isPresented: $showSuccess) {
            Button(L.t("Listo", "Done")) { dismiss() }
        } message: {
            Text(L.t("Gracias por colaborar. En esta versión de prueba el reporte no se envía a ningún servidor.",
                     "Thanks for helping. In this trial version the report isn't sent to any server."))
        }
    }

    // MARK: - Encabezado

    private var encabezado: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.appPrimary.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "megaphone.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.appPrimary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(L.t("Reportar incidente", "Report an incident"))
                    .font(.headlineMd)
                    .foregroundStyle(.onSurface)
                Text(L.t("Tu reporte ayuda a otros estudiantes", "Your report helps other students"))
                    .font(.bodySm)
                    .foregroundStyle(.onSurfaceVariant)
            }
            Spacer()
        }
    }

    // MARK: - Enviar

    private var botonEnviar: some View {
        Button {
            AppHaptics.success()
            showSuccess = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 15, weight: .bold))
                Text(L.t("Enviar reporte", "Send report"))
                    .font(.headlineSm)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: puedeEnviar
                                ? [.appPrimary, .appPrimary.opacity(0.78)]
                                : [Color.onSurfaceVariant.opacity(0.35), Color.onSurfaceVariant.opacity(0.25)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: puedeEnviar ? .appPrimary.opacity(0.35) : .clear,
                            radius: 10, x: 0, y: 5)
            )
        }
        .buttonStyle(PressableCapsuleStyle())
        .disabled(!puedeEnviar)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .animation(.easeInOut(duration: 0.2), value: puedeEnviar)
    }
}

// MARK: - Datos por tipo de reporte

extension TipoReporte {

    var icono: String {
        switch self {
        case .alerta:     return "exclamationmark.shield.fill"
        case .trafico:    return "car.fill"
        case .sugerencia: return "lightbulb.fill"
        case .otro:       return "ellipsis.bubble.fill"
        }
    }

    var titulo: String {
        switch self {
        case .alerta:     return L.t("Alerta", "Alert")
        case .trafico:    return L.t("Tráfico", "Traffic")
        case .sugerencia: return L.t("Sugerencia", "Suggestion")
        case .otro:       return L.t("Otro", "Other")
        }
    }

    /// Qué esperamos que cuente el usuario, según el tipo elegido.
    var detalle: String {
        switch self {
        case .alerta:
            return L.t("Cuenta qué pasó: robo, acoso o una persona sospechosa. Indica el lugar aproximado.",
                       "Tell us what happened: theft, harassment or a suspicious person. Include the approximate location.")
        case .trafico:
            return L.t("Cuenta cómo está el tráfico: congestión o choques. Indica el lugar aproximado.",
                       "Describe traffic conditions: congestion or crashes. Include the approximate location.")
        case .sugerencia:
            return L.t("Propón mejoras: frecuencias, limpieza, nuevos paraderos o precios justos.",
                       "Suggest improvements: frequency, cleanliness, new stops or fair fares.")
        case .otro:
            return L.t("Cualquier otra cosa que la comunidad deba saber.",
                       "Anything else the community should know.")
        }
    }

    var placeholder: String {
        switch self {
        case .alerta:     return L.t("Ej. Vi a una persona sospechosa cerca del paradero…", "e.g. I saw a suspicious person near the stop…")
        case .trafico:    return L.t("Ej. Choque en Av. España, tráfico detenido…", "e.g. Crash on Av. España, traffic stopped…")
        case .sugerencia: return L.t("Ej. La línea B debería pasar más seguido…", "e.g. Line B should run more often…")
        case .otro:       return L.t("¿Qué sucede?", "What's happening?")
        }
    }

    /// Frases rápidas que el usuario puede tocar para empezar a escribir.
    var sugerencias: [String] {
        switch self {
        case .alerta:
            return [L.t("Robo en el paradero", "Theft at the stop"),
                    L.t("Persona sospechosa", "Suspicious person"),
                    L.t("Acoso", "Harassment")]
        case .trafico:
            return [L.t("Tráfico detenido", "Traffic stopped"),
                    L.t("Choque", "Crash"),
                    L.t("Congestión en el paradero", "Congestion at the stop")]
        case .sugerencia:
            return [L.t("Más frecuencia", "More frequency"),
                    L.t("Nuevo paradero", "New stop"),
                    L.t("Mejor limpieza", "Better cleanliness")]
        case .otro:
            return []
        }
    }
}
