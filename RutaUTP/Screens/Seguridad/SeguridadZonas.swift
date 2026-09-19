//
//  SeguridadZonas.swift
//  RutaUTP
//
//  Zonas seguras de Trujillo: el modelo y el mini-mapa del banner.
//  
//  Estaba dentro de `SeguridadView.swift`.

import SwiftUI
import MapKit
import CoreLocation
// MARK: - Modelo de Ruta Segura
struct RutaSegura: Identifiable {
    let id: Int
    /// Nombre con el que se busca la zona en Apple Maps.
    ///
    /// Vive aquí, y no en un array paralelo indexado por `id` en la vista, para
    /// que el compilador obligue a declararlo en CADA zona: antes era
    /// `names[zona.id]` sobre un array de 10 posiciones, así que una undécima
    /// zona rompía la búsqueda con un índice fuera de rango.
    let consultaMapa: String
    let titulo: String
    let descripcion: String
    let icono: String
    let iconoBg: Color
    let iconoFg: Color
    let accent: Color?
}


// MARK: - Preview nocturno del banner de paraderos (mini-mapa con focos)
/// Ilustración animada: calles oscuras + focos azules pulsando en las
/// posiciones de los paraderos iluminados (si ya cargaron; si no, layout fijo).
struct BannerParaderosPreview: View {
    let cantidad: Int
    /// Paraderos cargados. Se pasan desde la vista padre en lugar de leerse de
    /// un `static var` compartido.
    var paraderos: [ParaderoGTFS] = []

    // Calles del mini-mapa (proporciones del contenedor)
    private static let calles: [(from: CGPoint, to: CGPoint)] = {
        let puntos = [(0.04, 0.78), (0.22, 0.62), (0.42, 0.70), (0.60, 0.46),
                      (0.78, 0.38), (0.97, 0.22), (0.12, 0.30), (0.35, 0.16),
                      (0.58, 0.10), (0.88, 0.72), (0.30, 0.90), (0.65, 0.82)]
        return [
            (p(0), p(1)), (p(1), p(2)), (p(2), p(3)), (p(3), p(4)), (p(4), p(5)),
            (p(6), p(7)), (p(7), p(8)), (p(2), p(7)), (p(3), p(8)),
            (p(1), p(6)), (p(4), p(9)), (p(10), p(2)), (p(11), p(9))
        ]
        func p(_ i: Int) -> CGPoint { CGPoint(x: puntos[i].0, y: puntos[i].1) }
    }()

    /// Focos en fracciones del contenedor: reales si hay paraderos cargados.
    ///
    /// Los paraderos llegan como parámetro. Antes se leían de un
    /// `static var paraderosCache` de `SeguridadView` que se escribía desde
    /// `.task` y se leía aquí durante el render: estado global mutable
    /// compartido entre el ciclo de carga y el de dibujo.
    private var focos: [CGPoint] {
        if !paraderos.isEmpty {
            let lats = paraderos.map(\.lat)
            let lons = paraderos.map(\.lon)
            guard let minLat = lats.min(), let maxLat = lats.max(),
                  let minLon = lons.min(), let maxLon = lons.max() else {
                return Self.focosDecorativos
            }
            let rangoLat = max(maxLat - minLat, 0.0001)
            let rangoLon = max(maxLon - minLon, 0.0001)
            return paraderos.map { p in
                CGPoint(x: 0.08 + (p.lon - minLon) / rangoLon * 0.84,
                        y: 0.85 - (p.lat - minLat) / rangoLat * 0.72)
            }
        }
        return Self.focosDecorativos
    }

    /// Fallback decorativo mientras carga el feed.
    private static let focosDecorativos: [CGPoint] = [
        (0.14, 0.62), (0.30, 0.48), (0.47, 0.58), (0.63, 0.32),
        (0.80, 0.26), (0.22, 0.24), (0.55, 0.78), (0.88, 0.55)
    ].map { CGPoint(x: $0.0, y: $0.1) }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 0.5, paused: false)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                ZStack {
                    // Noche
                    LinearGradient(colors: [Color(hex: "#0d1b3d"), Color(hex: "#123061")],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)

                    // Calles
                    Path { p in
                        for calle in Self.calles {
                            p.move(to: CGPoint(x: calle.from.x * geo.size.width, y: calle.from.y * geo.size.height))
                            p.addLine(to: CGPoint(x: calle.to.x * geo.size.width, y: calle.to.y * geo.size.height))
                        }
                    }
                    .stroke(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .padding(.horizontal, 8)

                    Path { p in
                        for calle in Self.calles {
                            p.move(to: CGPoint(x: calle.from.x * geo.size.width, y: calle.from.y * geo.size.height))
                            p.addLine(to: CGPoint(x: calle.to.x * geo.size.width, y: calle.to.y * geo.size.height))
                        }
                    }
                    .stroke(Color(hex: "#5cc8ff").opacity(0.35), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [3, 5]))
                    .padding(.horizontal, 8)

                    // Focos con pulso desfasado
                    ForEach(Array(focos.enumerated()), id: \.offset) { i, foco in
                        let fase = Double(i) * 0.9
                        let brillo = 0.55 + 0.45 * sin(t * 2.2 + fase)
                        ZStack {
                            Circle()
                                .fill(Color(hex: "#7fd4ff").opacity(0.22 * brillo))
                                .frame(width: 34, height: 34)
                            Circle()
                                .fill(Color(hex: "#8fd8ff"))
                                .frame(width: 12, height: 12)
                                .shadow(color: Color(hex: "#7fd4ff").opacity(brillo), radius: 6)
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.white)
                                .opacity(0.95)
                        }
                        .position(x: foco.x * geo.size.width, y: foco.y * geo.size.height)
                    }
                }
                .clipped()
            }
        }
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 5) {
                Label(L.t("EXPLORA TU CIUDAD", "EXPLORE YOUR CITY"), systemImage: "map.fill")
                    .font(.system(size: 10, weight: .bold)).tracking(1.2)
                    .foregroundStyle(Color(hex: "#8FD8FF"))
                Text(L.t("Encuentra tu próxima parada", "Find your next stop"))
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(.white).lineLimit(2)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Color.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
        }
        .overlay(alignment: .bottom) {
            // Cápsula de info
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: "#8fd8ff"))
                Text(L.t("\(cantidad) paraderos por explorar", "\(cantidad) stops to explore"))
                    .font(.bodySm)
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "map.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(L.t("VER MAPA", "OPEN MAP"))
                    .font(.labelCapsSm)
                    .foregroundStyle(.white)
                    .appTracking(AppTracking.wideLabel)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.black.opacity(0.55)))
            .padding(12)
        }
        .frame(height: 212)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
    }
}

#Preview {
    SeguridadView().environmentObject(AppRouter())
}


