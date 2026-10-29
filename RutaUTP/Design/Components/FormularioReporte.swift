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

/// Fila de formulario con selección única en un menú nativo de iOS.
struct SelectorTipoReporte: View {
    @Binding var tipo: TipoReporte
    var tiposDisponibles: [TipoReporte] = TipoReporte.allCases
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Menu {
            Picker(L.t("Tipo de reporte", "Report type"), selection: $tipo) {
                ForEach(tiposDisponibles) { opcion in
                    Label(opcion.titulo, systemImage: opcion.iconoContorno)
                        .tag(opcion)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    filaVertical
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) {
                            titulo.fixedSize()
                            Spacer(minLength: 12)
                            valor.fixedSize()
                        }
                        filaVertical
                    }
                }
            }
            .font(.body)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tint(Color.appAccent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.t("Tipo de reporte", "Report type"))
        .accessibilityValue(tipo.titulo)
        .onChange(of: tipo) { _, _ in AppHaptics.selection() }
    }

    private var titulo: some View {
        Text(L.t("Tipo de reporte", "Report type"))
            .foregroundStyle(Color.onSurface)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var valor: some View {
        HStack(spacing: 8) {
            Text(tipo.titulo)
                .foregroundStyle(Color.appAccent)
                .fixedSize(horizontal: false, vertical: true)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    private var filaVertical: some View {
        VStack(alignment: .leading, spacing: 8) {
            titulo
            valor
        }
    }
}

// MARK: - Detalle contextual

/// Explica qué se espera que cuente el usuario, según el tipo elegido.
struct DetalleTipoReporte: View {
    let tipo: TipoReporte
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(tipo.detalle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: tipo)
            .id(tipo)
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
                Text(L.t("Descripción", "Description"))
                    .font(.headline)
                    .foregroundStyle(Color.onSurface)
                Spacer()
                Text("\(restantes)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(restantes <= 20 ? Color.appError : Color.onSurfaceVariant)
                    .accessibilityLabel(L.f("{0} caracteres restantes", "{0} characters left", ["\(restantes)"]))
            }

            TextField(tipo.placeholder, text: $descripcion, axis: .vertical)
                .font(.body)
                .foregroundStyle(Color.onSurface)
                .accessibilityLabel(L.t("Descripción del reporte", "Report description"))
                .accessibilityHint(L.f("Máximo {0} caracteres", "Maximum {0} characters", ["\(FormularioReporte.maxCaracteres)"]))
                .lineLimit(4...7)
                .padding(16)
                .background(Color(uiColor: .secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
    @Environment(\.colorScheme) private var colorScheme
    private var acento: Color { colorScheme == .dark ? .primaryFixed : .appPrimary }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(sugerencias, id: \.self) { texto in
                Button {
                    alTocar(texto)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus")
                            .font(.body).foregroundStyle(acento).accessibilityHidden(true)
                        Text(texto)
                            .font(.subheadline).foregroundStyle(Color.onSurface)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if texto != sugerencias.last { Divider().padding(.leading, 44) }
            }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                .foregroundStyle(tieneUbicacion ? Color.appAccent : Color.onSurfaceVariant)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.surfaceContainerLowest))
                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(PressableCapsuleStyle())
        .accessibilityLabel(L.t("Centrar en mi ubicación", "Center on my location"))
    }
}
