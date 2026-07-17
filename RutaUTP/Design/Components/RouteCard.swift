//
//  RouteCard.swift
//  RutaUTP
//
//  Card horizontal para micro/combi en panel inferior del mapa y listas.
//

import SwiftUI

struct RouteCard: View {
    let ruta: Ruta
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(ruta.linea)
                        .font(.labelCapsMd)
                        .foregroundStyle(.onSurfaceVariant)
                        .appTracking(AppTracking.wideLabel)
                    Text(ruta.nombre)
                        .font(.headlineSm)
                        .foregroundStyle(.onSurface)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        badgeTiempo
                        Text("\(ruta.tipo.rawValue) • Placa: \(ruta.placa)")
                            .font(.bodySm)
                            .foregroundStyle(.onSurfaceVariant)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(width: 256, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.appSurface.opacity(0.55))
                    )
            )
            .overlay(
                HStack {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(ruta.colorIdentificador)
                        .frame(width: 4, height: 56)
                    Spacer()
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(ruta.linea), \(ruta.nombre), llega en \(ruta.minutosLlegada) minutos")
    }

    @ViewBuilder
    private var badgeTiempo: some View {
        let (bg, fg): (Color, Color) = {
            switch ruta.colorIdentificador {
            case .appPrimary:    return (.primaryContainer, .onPrimaryContainer)
            case .secondary:     return (.secondaryContainer, .onSecondaryContainer)
            case .tertiary:      return (.tertiaryContainer, .onTertiaryContainer)
            default:             return (.surfaceContainerHigh, .onSurface)
            }
        }()
        Text("\(ruta.minutosLlegada) MIN")
            .font(.labelCapsMd)
            .foregroundStyle(fg)
            .appTracking(AppTracking.wideLabel)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 8).fill(bg))
    }
}

#Preview {
    ZStack {
        Color.appBackground.ignoresSafeArea()
        HStack(spacing: 12) {
            RouteCard(ruta: Ruta(
                id: "1", linea: "LÍNEA 10", nombre: "El Cortijo",
                empresa: "Salaverry", tipo: .micro, placa: "T1B-721",
                minutosLlegada: 4, colorIdentificador: .appPrimary
            ))
            RouteCard(ruta: Ruta(
                id: "2", linea: "LÍNEA 4", nombre: "Salaverry",
                empresa: "Salaverry", tipo: .combi, placa: "A6N-450",
                minutosLlegada: 12, colorIdentificador: .secondary
            ))
        }
        .padding()
    }
}
