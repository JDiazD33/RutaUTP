//
//  MapMarkers.swift
//  RutaUTP
//
//  Marcadores personalizados del mapa (compartidos entre MapaView y RutasView).
//

import SwiftUI

// MARK: - User marker (pulso azul con icono de caminante)
struct PulsingUserMarker: View {
    @State private var pulsando = false
    /// Con «reducir movimiento» activado el halo no late. El pulso es
    /// decorativo —llama la atención sobre el marcador, no informa de nada—,
    /// así que es lo primero que debe apagarse.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.secondaryContainer.opacity(0.35))
                .frame(width: pulsando ? 32 : 20, height: pulsando ? 32 : 20)
                .animation(
                    reduceMotion
                    ? nil
                    : .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                    value: pulsando
                )
            Circle()
                .fill(Color.secondary)
                .frame(width: 18, height: 18)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.25), radius: 3)
            Image(systemName: "figure.walk")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
        }
        .onAppear { pulsando = !reduceMotion }
    }
}

// MARK: - UTP marker
struct MarcadorUTP: View {
    var body: some View {
        VStack(spacing: 2) {
            Text("UTP Trujillo")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.appPrimary))
                .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
            ZStack {
                Circle().fill(Color.appPrimary).frame(width: 36, height: 36)
                    .shadow(color: .black.opacity(0.30), radius: 4, x: 0, y: 2)
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Marcador de Destino Buscado (ej. UPAO, Mall, etc.)
struct MarcadorDestinoBuscado: View {
    let titulo: String

    var body: some View {
        VStack(spacing: 2) {
            Text(titulo)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.secondary))
                .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
                .lineLimit(1)
            ZStack {
                Circle().fill(Color.secondary).frame(width: 34, height: 34)
                    .shadow(color: .black.opacity(0.30), radius: 4, x: 0, y: 2)
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Etiqueta del bus (la píldora con la línea)

/// La píldora que identifica el bus: color de la línea, icono, nombre y rumbo.
///
/// Se separó de `AnimatedBusMarker` para poder ponerla también encima del modelo
/// 3D sin duplicar el diseño. Conserva el aspecto que ya tenía.
struct EtiquetaBus: View {
    let linea: String
    let color: Color
    let heading: Double
    var seleccionado: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            // El color identifica la línea sin teñir todo el vehículo.
            Capsule()
                .fill(color)
                .frame(width: 3, height: 19)

            Image(systemName: "bus.fill")
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.onSurface)
                .frame(width: 23, height: 23)

            Text(linea)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.onSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .layoutPriority(1)

            if heading.isFinite && heading >= 0 {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color.onSurfaceVariant.opacity(0.65))
                    .rotationEffect(.degrees(heading))
                    .frame(width: 10, height: 12)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 36)
        .frame(minWidth: 78, maxWidth: 120)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.surfaceContainerLowest)
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(color.opacity(seleccionado ? 0.08 : 0))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(seleccionado ? Color.onSurface.opacity(0.75) : Color.onSurface.opacity(0.16),
                              lineWidth: seleccionado ? 1.5 : 0.75)
        }
        .shadow(color: .black.opacity(seleccionado ? 0.16 : 0.10), radius: 3, x: 0, y: 2)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: seleccionado)
    }
}

// MARK: - Bus: solo la etiqueta (Rutas y demo de tracking)
struct AnimatedBusMarker: View {
    let linea: String
    let color: Color
    let heading: Double
    var seleccionado: Bool = false

    var body: some View {
        EtiquetaBus(linea: linea, color: color, heading: heading, seleccionado: seleccionado)
            // Área táctil suficiente sin agrandar la etiqueta visible.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L.t("Micro, línea ", "Bus, line ") + linea)
            .accessibilityValue(seleccionado ? L.t("Seleccionado", "Selected") : "")
            .accessibilityHint(L.t("Toca para ver la información del micro", "Tap to view bus information"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(seleccionado ? .isSelected : [])
    }
}

// MARK: - Bus en 3D con su etiqueta encima (marcador del mapa)

/// El marcador del mapa: el bus en 3D y, justo encima, la etiqueta de la línea.
///
/// La etiqueta se conserva a propósito. Es la que dice de un vistazo qué línea
/// es y de qué color; el modelo aporta el aspecto de vehículo y, sobre todo, el
/// sentido de la marcha, que antes se resolvía con una flechita diminuta.
struct BusMarker3D: View {
    let linea: String
    let color: Color
    let heading: Double
    var seleccionado: Bool = false

    /// Alto del modelo. A 56 pt se distingue la franja roja de la carrocería;
    /// por debajo se convierte en una mancha y no compensa el coste.
    private let altoModelo: CGFloat = 56

    /// Altura total del marcador: la etiqueta más el modelo.
    static let altoTotal: CGFloat = 36 + 56

    /// Punto del marcador que se clava en la coordenada.
    ///
    /// Por defecto MapKit centra la vista entera, y con la etiqueta arriba eso
    /// dejaría el bus dibujado por debajo del punto real. Se ancla en el centro
    /// del modelo para que el vehículo caiga donde toca.
    static let ancla = UnitPoint(x: 0.5, y: (36 + 56 / 2) / altoTotal)

    var body: some View {
        VStack(spacing: 0) {
            EtiquetaBus(linea: linea, color: color, heading: heading, seleccionado: seleccionado)
                .zIndex(1)

            BusEn3D(rumbo: heading, lado: altoModelo, seleccionado: seleccionado)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.t("Micro, línea ", "Bus, line ") + linea)
        .accessibilityValue(seleccionado ? L.t("Seleccionado", "Selected") : "")
        .accessibilityHint(L.t("Toca para ver la información del micro", "Tap to view bus information"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(seleccionado ? .isSelected : [])
    }
}
