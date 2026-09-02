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

    static let maxCaracteres = 200

    @Environment(\.dismiss) private var dismiss
    @State private var tipo: TipoReporte = .alerta
    @State private var descripcion: String = ""
    @State private var showSuccess = false

    private var restantes: Int { Self.maxCaracteres - descripcion.count }
    private var puedeEnviar: Bool {
        !descripcion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    encabezado
                    selectorTipo
                    detalleTipo
                    campoDescripcion
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { botonEnviar }
        }
        .alert(L.t("Reporte enviado", "Report sent"), isPresented: $showSuccess) {
            Button(L.t("Listo", "Done")) { dismiss() }
        } message: {
            Text(L.t("Gracias por colaborar con la comunidad.",
                     "Thanks for helping the community."))
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

    // MARK: - Selector de tipo

    private var selectorTipo: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.t("TIPO DE REPORTE", "REPORT TYPE"))
                .font(.labelCapsMd)
                .foregroundStyle(.onSurfaceVariant)
                .appTracking(AppTracking.wideLabel)

            HStack(spacing: 8) {
                ForEach(TipoReporte.allCases) { t in
                    tipoCard(t)
                }
            }
        }
    }

    private func tipoCard(_ t: TipoReporte) -> some View {
        let seleccionado = tipo == t
        return Button {
            AppHaptics.selection()
            withAnimation(.easeInOut(duration: 0.18)) { tipo = t }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: t.icono)
                    .font(.system(size: 17, weight: .semibold))
                Text(t.titulo)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(seleccionado ? t.foreground : Color.onSurfaceVariant)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(seleccionado ? t.background : Color.surfaceContainerLow)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(seleccionado ? t.foreground.opacity(0.55) : Color.outlineVariant.opacity(0.35),
                            lineWidth: seleccionado ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(seleccionado ? .isSelected : [])
    }

    // MARK: - Detalle contextual por tipo

    private var detalleTipo: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tipo.icono)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tipo.foreground)
                .frame(width: 20)
            Text(tipo.detalle)
                .font(.bodySm)
                .foregroundStyle(.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tipo.background.opacity(0.45))
        )
        .animation(.easeInOut(duration: 0.2), value: tipo)
        .id(tipo) // re-anima la entrada al cambiar de tipo
    }

    // MARK: - Descripción (máx. 200 caracteres)

    private var campoDescripcion: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L.t("DESCRIPCIÓN", "DESCRIPTION"))
                    .font(.labelCapsMd)
                    .foregroundStyle(.onSurfaceVariant)
                    .appTracking(AppTracking.wideLabel)
                Spacer()
                Text("\(restantes)")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(restantes <= 20 ? Color.appError : Color.onSurfaceVariant)
                    .accessibilityLabel(L.t("\(restantes) caracteres restantes", "\(restantes) characters left"))
            }

            TextField(tipo.placeholder, text: $descripcion, axis: .vertical)
                .lineLimit(4...7)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.surfaceContainerLow)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.outlineVariant.opacity(0.35), lineWidth: 0.5)
                )
                .onChange(of: descripcion) { _, nuevo in
                    if nuevo.count > Self.maxCaracteres {
                        descripcion = String(nuevo.prefix(Self.maxCaracteres))
                        AppHaptics.impact(.light)
                    }
                }

            // Sugerencias rápidas según el tipo: insertan texto inicial
            if !tipo.sugerencias.isEmpty && descripcion.isEmpty {
                FlowLayoutSugerencias(sugerencias: tipo.sugerencias) { texto in
                    descripcion = texto
                    AppHaptics.impact(.light)
                }
            }
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
            return L.t("Cuenta qué pasó: robo, acoso, persona sospechosa o accidente. Indica el lugar aproximado.",
                       "Tell us what happened: theft, harassment, suspicious person or accident. Include the approximate location.")
        case .trafico:
            return L.t("Reporta congestión, choques o desvíos que estén afectando tu ruta ahora mismo.",
                       "Report congestion, crashes or detours affecting your route right now.")
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
                    L.t("Accidente", "Accident")]
        case .trafico:
            return [L.t("Tráfico detenido", "Traffic stopped"),
                    L.t("Choque", "Crash"),
                    L.t("Desvío en la ruta", "Route detour")]
        case .sugerencia:
            return [L.t("Más frecuencia", "More frequency"),
                    L.t("Nuevo paradero", "New stop"),
                    L.t("Mejor limpieza", "Better cleanliness")]
        case .otro:
            return []
        }
    }
}

// MARK: - Chips de sugerencias (flujo simple en filas)

private struct FlowLayoutSugerencias: View {
    let sugerencias: [String]
    let alTocar: (String) -> Void

    var body: some View {
        // Filas apiladas: suficiente para 2-3 frases cortas, sin layout math.
        VStack(alignment: .leading, spacing: 6) {
            ForEach(sugerencias, id: \.self) { texto in
                Button {
                    alTocar(texto)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .bold))
                        Text(texto)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.appPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.appPrimary.opacity(0.09)))
                    .overlay(Capsule().stroke(Color.appPrimary.opacity(0.25), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
