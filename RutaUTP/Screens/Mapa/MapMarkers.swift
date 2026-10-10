//
//  MapMarkers.swift
//  RutaUTP
//
//  Marcadores personalizados del mapa (compartidos entre MapaView y RutasView).
//

import SwiftUI

// MARK: - User marker (pulso azul con icono de caminante)
struct PulsingUserMarker: View {
    /// Con «reducir movimiento» activado el halo no late. El pulso es
    /// decorativo —llama la atención sobre el marcador, no informa de nada—,
    /// así que es lo primero que debe apagarse.

    var body: some View {
        DecorativeAnimationScope { animar in
            ZStack {
                Circle()
                    .fill(Color.secondaryContainer.opacity(0.35))
                    .frame(width: animar ? 32 : 20, height: animar ? 32 : 20)
                    .animation(
                        !animar
                        ? nil
                        : .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                        value: animar
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
        }
    }
}

/// Referencia institucional; no representa un vehículo ni un paradero confirmado.
struct MarcadorCampusUTP: View {
    let busesUTPActivos: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text("UTP")
                .font(.caption.bold())
                .foregroundStyle(busesUTPActivos ? Color.white : Color.onPrimaryFill)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(busesUTPActivos ? Color.red : Color.primaryFill, in: Capsule())
            if busesUTPActivos {
                Image(systemName: "bus.fill")
                    .font(.title2.bold())
                    .foregroundStyle(.red)
                    .padding(10)
                    .background(Color.appSurface, in: Circle())
            } else {
                ZStack {
                    Circle().fill(Color.primaryFill).frame(width: 48, height: 48)
                    Image(systemName: CategoriaLugar.universidad.icono)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.onPrimaryFill)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.t("Campus UTP Trujillo, referencia del mapa", "UTP Trujillo campus, map reference"))
    }
}

// MARK: - Sede de trabajo elegida
struct MarcadorSedeTrabajo: View {
    let sede: SedeTrabajo

    var body: some View {
        let paleta = PaletasEmpresa.paleta(para: sede.empresa)
        VStack(spacing: 2) {
            Text(sede.nombre)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(paleta.onPrimaryFill)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(paleta.primaryFill))
                .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
                .lineLimit(1)
                .frame(maxWidth: 200)
            ZStack {
                Circle().fill(paleta.primaryFill).frame(width: 44, height: 44)
                    .shadow(color: .black.opacity(0.30), radius: 4, x: 0, y: 2)
                if let logo = sede.empresa.logoAsset {
                    Image(logo).renderingMode(.template).resizable().scaledToFit()
                        .frame(width: 34, height: 24)
                        .foregroundStyle(paleta.onPrimaryFill)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sede.nombre + ", " + sede.direccion)
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

// MARK: - Marcador de referencia (pin)

// MARK: Forma de la "gota" del pin

/// Silueta clásica de marcador de mapa: cabeza circular que se estrecha en una
/// punta. La punta es la que se clava en la coordenada, así que el ancla del
/// marcador es `.bottom` (`MarcadorPin.ancla`).
struct FormaPinGota: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = rect.width / 2
        let cx = rect.midX
        let cy = r            // centro de la cabeza
        let puntaY = rect.height

        // La cabeza es un semicírculo por encima de `cy`.
        p.move(to: CGPoint(x: cx - r, y: cy))
        p.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                 startAngle: .degrees(180), endAngle: .degrees(360),
                 clockwise: false)
        // Y de ahí cae a la punta con dos curvas: los flancos del pin.
        p.addQuadCurve(to: CGPoint(x: cx, y: puntaY),
                       control: CGPoint(x: cx + r * 0.88,
                                        y: cy + (puntaY - cy) * 0.55))
        p.addQuadCurve(to: CGPoint(x: cx - r, y: cy),
                       control: CGPoint(x: cx - r * 0.88,
                                        y: cy + (puntaY - cy) * 0.55))
        p.closeSubpath()
        return p
    }
}

// MARK: El pin que el usuario deja caer en el mapa

/// Marcador de referencia que el usuario coloca sobre el mapa.
///
/// Distinto del marcador del usuario (el punto pulsante): aquel dice "aquí
/// estoy", este dice "estoy mirando esto". Toca para quitarlo.
struct MarcadorPin: View {
    var color: Color? = nil
    var onTap: (() -> Void)?

    /// Punto que se ancla en la coordenada: la punta de la gota.
    static let ancla = UnitPoint(x: 0.5, y: 1)

    var body: some View {
        FormaPinGota()
            .fill(color ?? Color.appPrimary)
            .frame(width: 34, height: 46)
            .overlay {
                // El hueco interior: sin él la gota es una mancha sólida y no
                // se lee como "un punto" a tamaño real.
                FormaPinGota()
                    .fill(Color.surfaceContainerLowest)
                    .frame(width: 12, height: 17)
                    .offset(y: -11)
            }
            .overlay {
                FormaPinGota()
                    .stroke(Color.white, lineWidth: 2.5)
            }
            .shadow(color: .black.opacity(0.30), radius: 5, x: 0, y: 3)
            .contentShape(Rectangle())
            .onTapGesture { onTap?() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L.t("Marcador en el mapa", "Map marker"))
            .accessibilityHint(onTap == nil ? "" : L.t("Quita el marcador", "Removes the marker"))
            .accessibilityAddTraits(onTap == nil ? [] : .isButton)
            .accessibilityAction { onTap?() }
    }
}

// MARK: El pin flotante mientras se está colocando

/// La versión "en vuelo" del pin: aparece sobre el centro del mapa
/// mientras el usuario desplaza el mapa para elegir el punto.
///
/// Es la misma silueta pero sin sombra de mapa y con un anillo en el suelo que
/// marca dónde va a caer, para que quede claro que la posición aún no está
/// fijada.
struct PinEnColocacion: View {

    var body: some View {
        ZStack {
            FormaPinGota()
                .fill(Color.appPrimary)
                .frame(width: 30, height: 40)
                .overlay {
                    FormaPinGota()
                        .fill(Color.surfaceContainerLowest)
                        .frame(width: 10, height: 14)
                        .offset(y: -9)
                }
                .overlay {
                    FormaPinGota().stroke(Color.white, lineWidth: 2.5)
                }
                .shadow(color: .black.opacity(0.22), radius: 4, x: 0, y: 2)
                .offset(y: -28)

            // El centro del anillo es el punto que MapProxy convierte.
            // El pin elevado no desplaza este objetivo ni modifica su tamaño.
            Circle()
                .fill(Color.appSurface.opacity(0.75))
                .overlay { Circle().stroke(Color.appPrimary, lineWidth: 2) }
                .frame(width: 24, height: 24)
            Circle()
                .fill(Color.appPrimary)
                .frame(width: 4, height: 4)
        }
        .frame(width: 30, height: 26)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
