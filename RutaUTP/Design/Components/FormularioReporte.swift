//
//  FormularioReporte.swift
//  RutaUTP
//
//  Piezas compartidas del formulario de reporte.
//
//  `ReportarSheet` (reportar un incidente) y `PublicarComunidadSheet` (aportar
//  a la comunidad) tenían el selector de tipo, el detalle contextual, el campo
//  de descripción con contador y los chips de sugerencias DUPLICADOS casi
//  literalmente: dos copias del mismo código que había que mantener dos veces
//  y que ya habían empezado a divergir en los nombres (`FlowLayoutSugerencias`
//  frente a `chipsSugerencias`).
//
//  Se comparten aquí. Cada hoja conserva lo que de verdad la distingue: su
//  encabezado, su acento de color y sus adjuntos (foto y ubicación en el caso
//  de la comunidad).
//

import SwiftUI

enum FormularioReporte {
    /// Límite de la descripción, compartido por las dos hojas.
    static let maxCaracteres = 200
}

// MARK: - Selector de tipo

/// Selector de tipo por tarjetas. El tipo elegido se resalta con su propio
/// color de fondo y borde.
struct SelectorTipoReporte: View {

    @Binding var tipo: TipoReporte
    var tiposDisponibles: [TipoReporte] = TipoReporte.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.t("TIPO DE REPORTE", "REPORT TYPE"))
                .font(.labelCapsMd)
                .foregroundStyle(.onSurfaceVariant)
                .appTracking(AppTracking.wideLabel)

            HStack(spacing: 8) {
                ForEach(tiposDisponibles) { t in
                    tarjeta(t)
                }
            }
        }
    }

    private func tarjeta(_ t: TipoReporte) -> some View {
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
}

// MARK: - Detalle contextual

/// Explica qué se espera que cuente el usuario, según el tipo elegido.
struct DetalleTipoReporte: View {

    let tipo: TipoReporte

    var body: some View {
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
}

// MARK: - Descripción

/// Campo de descripción con contador en vivo y sugerencias rápidas.
struct CampoDescripcionReporte: View {

    @Binding var descripcion: String
    let tipo: TipoReporte

    private var restantes: Int { FormularioReporte.maxCaracteres - descripcion.count }

    var body: some View {
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
                    if nuevo.count > FormularioReporte.maxCaracteres {
                        descripcion = String(nuevo.prefix(FormularioReporte.maxCaracteres))
                        AppHaptics.impact(.light)
                    }
                }

            if !tipo.sugerencias.isEmpty && descripcion.isEmpty {
                ChipsSugerencias(sugerencias: tipo.sugerencias) { texto in
                    descripcion = texto
                    AppHaptics.impact(.light)
                }
            }
        }
    }
}

// MARK: - Chips de sugerencias

/// Frases rápidas que el usuario puede tocar para empezar a escribir.
private struct ChipsSugerencias: View {

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

// MARK: - Botón «mi ubicación»

/// Botón circular para recentrar el mapa en la posición del usuario.
///
/// Existía dos veces: en la pestaña Mapa y en el selector de ubicación de
/// Comunidad. El estado se indica con el color del icono (primario si ya hay
/// posición, gris si todavía no).
struct BotonMiUbicacion: View {

    /// true cuando ya se conoce la posición del usuario.
    let tieneUbicacion: Bool
    let action: () -> Void

    var body: some View {
        Button {
            AppHaptics.impact(.light)
            action()
        } label: {
            Image(systemName: "location.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tieneUbicacion ? Color.appPrimary : Color.onSurfaceVariant)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.surfaceContainerLowest))
                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(PressableCapsuleStyle())
        .accessibilityLabel(L.t("Centrar en mi ubicación", "Center on my location"))
    }
}
