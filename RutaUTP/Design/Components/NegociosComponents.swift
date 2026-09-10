//
//  NegociosComponents.swift
//  RutaUTP
//
//  UI de los "negocios en ruta": burbuja del mapa + card de detalle con
//  cupón. Nace en la vista de Tracking (el usuario viajando en el micro);
//  cuando la feature pase al mapa principal, estos mismos componentes
//  sirven sin cambios.
//
//  Regla visual: lo patrocinado se distingue (badge + borde de categoría),
//  nunca se disfraza de contenido orgánico. La confianza es el activo.
//

import SwiftUI
import CoreLocation
import UIKit

// MARK: - Burbuja del mapa

/// Forma de "globo" tipo pin de Google Maps: círculo con cola que converge
/// en punta abajo. Un solo path para que el borde blanco sea continuo
/// (círculo y cola sin costuras).
struct BurbujaGloboShape: Shape {
    /// Radio del círculo de la burbuja.
    let radio: CGFloat
    /// Distancia del centro del círculo a la punta de la cola.
    let alturaCola: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centro = CGPoint(x: rect.midX, y: radio + 1)   // margen para el borde
        let punta = CGPoint(x: rect.midX, y: centro.y + alturaCola)

        // Puntos de tangencia de la cola con el círculo: cos(β) = r / d.
        let beta = acos(min(1, radio / max(radio + 0.001, alturaCola)))
        let abajo = CGFloat.pi / 2
        let tangente1 = abajo - beta
        let tangente2 = abajo + beta

        path.move(to: punta)
        path.addLine(to: CGPoint(x: centro.x + radio * cos(tangente1),
                                 y: centro.y + radio * sin(tangente1)))
        // Rodea el círculo por arriba (el camino largo) hasta la otra tangente.
        path.addArc(center: centro, radius: radio,
                    startAngle: .radians(Double(tangente1)),
                    endAngle: .radians(Double(tangente2)),
                    clockwise: false)
        path.addLine(to: punta)
        path.closeSubpath()
        return path
    }
}

/// Pin de negocio estilo Google Maps: globo del color de la categoría con el
/// ícono de la comida adentro. Sin texto: la promo vive en la card al tocar.
/// Compacto a propósito: en el mapa compite con buses, usuario y destino.
struct NegocioBubbleMarker: View {
    let negocio: Negocio
    var seleccionado: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(LinearGradient(colors: [negocio.categoria.color.opacity(0.85), negocio.categoria.color],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                    .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.appSurface, lineWidth: 3))
                Text(negocio.categoria.emoji)
                    .font(.system(size: 25))
                    .frame(width: 44, height: 44)
                if negocio.cupon?.vigente == true {
                    Image(systemName: "ticket.fill")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Color.appPrimary)
                        .padding(4)
                        .background(Circle().fill(Color.appSurface))
                        .offset(x: 3, y: 3)
                }
            }
            if seleccionado {
                Text(negocio.nombre)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.onSurface).lineLimit(1)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Color.surfaceContainerLowest))
                    .frame(maxWidth: 150)
            }
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 9)).foregroundStyle(negocio.categoria.color)
                .offset(y: -1)
        }
        .shadow(color: negocio.categoria.color.opacity(0.3), radius: 5, y: 3)
        .frame(minWidth: 48, minHeight: 54)
        .contentShape(Rectangle())
        .scaleEffect(seleccionado ? 1.12 : 1, anchor: .bottom)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: seleccionado)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(negocio.nombre + ", " + negocio.categoria.etiqueta)
        .accessibilityHint(L.t("Toca para ver la promoción de demostración", "Tap to view the demo offer"))
    }
}

// MARK: - Card de detalle

/// Detalle del negocio tocado: nombre, rating, distancia desde la posición
/// actual, promo completa y cupón (copiar código + guardar).
struct NegocioDetailCard: View {
    let negocio: Negocio
    /// Posición del usuario en el momento del render; la distancia se
    /// recalcula en vivo mientras el micro avanza.
    let ubicacion: CLLocationCoordinate2D?
    let onClose: () -> Void

    @State private var cuponGuardado: Bool
    @State private var codigoCopiado: Bool = false

    init(negocio: Negocio,
         ubicacion: CLLocationCoordinate2D?,
         onClose: @escaping () -> Void) {
        self.negocio = negocio
        self.ubicacion = ubicacion
        self.onClose = onClose
        _cuponGuardado = State(initialValue: NegociosService.shared.cuponGuardado(negocio))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            encabezado
            Text(L.t("NEGOCIO DEMO · PROMOCIÓN DE EJEMPLO", "DEMO BUSINESS · SAMPLE OFFER"))
                .font(.system(size: 9, weight: .bold)).foregroundStyle(Color.onSurfaceVariant)
            infoLugar
            promo
            if let cupon = negocio.cupon {
                cuponView(cupon)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(negocio.categoria.color.opacity(0.45), lineWidth: 1)
        )
        .onReceive(NotificationCenter.default.publisher(for: NegociosService.cuponesActualizados)
            .receive(on: RunLoop.main)) { _ in
                cuponGuardado = NegociosService.shared.cuponGuardado(negocio)
            }
    }

    // MARK: Encabezado (icono, nombre, rating, cerrar)

    private var encabezado: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(negocio.categoria.color.opacity(0.20))
                    .frame(width: 44, height: 44)
                Image(systemName: negocio.categoria.icono)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(negocio.categoria.color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(negocio.nombre)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.onSurface)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(negocio.categoria.etiqueta)
                        .font(.system(size: 11))
                        .foregroundStyle(.onSurfaceVariant)
                    if let rating = negocio.calificacion {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.yellow)
                            Text(String(format: "%.1f", rating))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.onSurfaceVariant)
                        }
                    }
                    if negocio.patrocinado {
                        Text(L.t("Promocionado", "Sponsored"))
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(Color.appPrimary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.appPrimary.opacity(0.14)))
                    }
                }
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.onSurfaceVariant.opacity(0.6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.t("Cerrar", "Close"))
        }
    }

    // MARK: Dirección + horario + distancia

    private var infoLugar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "mappin")
                    .font(.system(size: 11))
                    .foregroundStyle(.onSurfaceVariant)
                Text("\(negocio.direccion) · \(negocio.distrito)")
                    .font(.system(size: 12))
                    .foregroundStyle(.onSurfaceVariant)
                    .lineLimit(1)
                Spacer()
                if let distancia = distanciaTexto {
                    Text(distancia)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.appPrimary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.appPrimary.opacity(0.14)))
                }
            }
            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.system(size: 11))
                    .foregroundStyle(.onSurfaceVariant)
                Text(negocio.horario.texto)
                    .font(.system(size: 11))
                    .foregroundStyle(.onSurfaceVariant)
                    .lineLimit(1)
            }
        }
    }

    /// "a 240 m" / "a 2.3 km" desde la posición actual (nil sin GPS).
    private var distanciaTexto: String? {
        guard let ubicacion else { return nil }
        let metros = NegociosService.distanciaMetros(ubicacion, negocio.coordinate)
        if metros < 1000 {
            return L.t("a \(Int(metros)) m", "\(Int(metros)) m away")
        }
        return L.t(String(format: "a %.1f km", metros / 1000),
                   String(format: "%.1f km away", metros / 1000))
    }

    // MARK: Promo

    private var promo: some View {
        Text(negocio.promoDetalle.texto)
            .font(.system(size: 12))
            .foregroundStyle(.onSurface)
            .lineSpacing(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.surfaceContainerHighest.opacity(0.45))
            )
    }

    // MARK: Cupón

    private func cuponView(_ cupon: CuponNegocio) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if cupon.vigente {
                HStack(spacing: 6) {
                    Image(systemName: "ticket.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.appPrimary)
                    Text(cupon.detalle.texto)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.onSurface)
                }
                Text(cupon.condiciones.texto)
                    .font(.system(size: 10))
                    .foregroundStyle(.onSurfaceVariant)
                    .lineSpacing(1)
                if let vence = textoVencimiento(cupon) {
                    Text(vence)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.onSurfaceVariant.opacity(0.8))
                }

                HStack(spacing: 8) {
                    // Código: tap copia al portapapeles (mostrarlo en el
                    // local / mandarlo por WhatsApp).
                    Button {
                        UIPasteboard.general.string = cupon.codigo
                        AppHaptics.impact(.light)
                        codigoCopiado = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                            codigoCopiado = false
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: codigoCopiado ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10, weight: .bold))
                            Text(codigoCopiado ? L.t("Copiado", "Copied") : cupon.codigo)
                                .font(.system(size: 12, weight: .heavy))
                                .minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(.onSurface)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.surfaceContainerLowest)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(Color.outlineVariant, style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                        )
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        AppHaptics.impact(.medium)
                        cuponGuardado = NegociosService.shared.alternarCupon(negocio)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: cuponGuardado ? "checkmark.circle.fill" : "bookmark.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text(cuponGuardado ? L.t("Guardado", "Saved")
                                               : L.t("Guardar cupón", "Save coupon"))
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(cuponGuardado
                                           ? Color.secondaryContainer.opacity(0.7)
                                           : Color.appPrimary)
                        )
                    }
                    .buttonStyle(.plain)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "ticket")
                        .font(.system(size: 12))
                        .foregroundStyle(.onSurfaceVariant)
                    Text(L.t("Cupón vencido", "Coupon expired"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.onSurfaceVariant)
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondaryContainer.opacity(0.30))
        )
    }

    /// "Válido hasta 31 dic. 2026" en el idioma activo.
    private func textoVencimiento(_ cupon: CuponNegocio) -> String? {
        guard let fecha = cupon.fechaVencimiento else { return nil }
        let formato = DateFormatter()
        formato.dateFormat = "d MMM yyyy"
        formato.locale = Locale(identifier: IdiomaManager.shared.esIngles ? "en_US" : "es_PE")
        return L.t("Válido hasta \(formato.string(from: fecha))",
                   "Valid until \(formato.string(from: fecha))")
    }
}

#Preview("Burbuja") {
    ZStack {
        Color(hex: "#e8ecef").ignoresSafeArea()
        VStack(spacing: 24) {
            NegocioBubbleMarker(negocio: Negocio.negocioEjemplo)
            NegocioBubbleMarker(negocio: Negocio.negocioEjemplo, seleccionado: true)
        }
    }
    .padding(40)
}

#Preview("Card · claro") {
    ZStack {
        Color(hex: "#3a4a55").ignoresSafeArea()
        NegocioDetailCard(
            negocio: Negocio.negocioEjemplo,
            ubicacion: CLLocationCoordinate2D(latitude: -8.0982, longitude: -79.0381),
            onClose: {}
        )
        .padding(16)
    }
    .preferredColorScheme(.light)
}

#Preview("Card · oscuro") {
    ZStack {
        Color(hex: "#0a0a0a").ignoresSafeArea()
        NegocioDetailCard(
            negocio: Negocio.negocioEjemplo,
            ubicacion: CLLocationCoordinate2D(latitude: -8.0982, longitude: -79.0381),
            onClose: {}
        )
        .padding(16)
    }
    .preferredColorScheme(.dark)
}

// MARK: - Fixture de previews

extension Negocio {
    /// Negocio de ejemplo para previews y pruebas manuales.
    static var negocioEjemplo: Negocio {
        Negocio(
            id: "preview-polleria",
            nombre: "Pollería La Brasita Norteña",
            categoria: .polleria,
            latitud: -8.09745,
            longitud: -79.03799,
            direccion: "Av. Nicolás de Piérola 1150",
            distrito: "Trujillo",
            promoCorta: TextoBilingue(es: "🍗 1/4 pollo + papas 2x1",
                                      en: "🍗 1/4 chicken + fries 2x1"),
            promoDetalle: TextoBilingue(
                es: "De a dos: pide un 1/4 de pollo a la brasa con papas doradas y el segundo va por nuestra cuenta.",
                en: "For two: order a 1/4 rotisserie chicken with golden fries and the second one is on us."
            ),
            cupon: CuponNegocio(
                codigo: "RUTA-2X1POLLO",
                detalle: TextoBilingue(es: "2x1 en 1/4 de pollo + papas",
                                       en: "2x1 on 1/4 chicken + fries"),
                condiciones: TextoBilingue(es: "Lun a Jue desde las 3 pm. Mostrando el cupón en la app.",
                                           en: "Mon-Thu from 3 pm. Showing the in-app coupon."),
                vence: "2026-12-31"
            ),
            horario: TextoBilingue(es: "Lun-Sáb 11:00-22:30 · Dom 12:00-22:00",
                                   en: "Mon-Sat 11:00-22:30 · Sun 12:00-22:00"),
            telefono: "+51 944 302 118",
            patrocinado: true,
            calificacion: 4.6
        )
    }
}
