//
//  RouteSummaryComponents.swift
//  RutaUTP
//
//  Piezas compartidas del resumen de ruta: categorías, identidad de línea y
//  recorrido. Las usan RouteSummaryPanel y RouteAlternativesSheet.
//

import SwiftUI

extension TransitRouteCategory {
    var title: String {
        switch self {
        case .recommended: return L.t("Recomendada", "Recommended")
        case .fastest: return L.t("Más rápida", "Fastest")
        case .closestBoarding: return L.t("Más cercana", "Closest boarding")
        }
    }
}

struct RouteCategoryBadges: View {
    let categories: [TransitRouteCategory]

    var body: some View {
        Text(categories.isEmpty ? L.t("Tu elección", "Your choice") : categories.map(\.title).joined(separator: " · "))
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.onSurfaceVariant)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// La identidad de la línea siempre se lee en tinta neutra; su color GTFS
/// queda en el indicador para no perder legibilidad con líneas muy oscuras.
struct RouteLineIdentity: View {
    let route: RutaGTFS
    var showsOperator = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Capsule().fill(route.color).frame(width: 4, height: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(route.lineaConLetra)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.onSurface)
                    .fixedSize(horizontal: false, vertical: true)
                if showsOperator {
                    Text(route.empresa).font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

struct RouteJourneyLines: View {
    let plan: TransitItinerary
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        let layout = textSize >= .xxxLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        return layout {
            RouteLineIdentity(route: plan.route)
            if let transfer = plan.transfer {
                Image(systemName: textSize >= .xxxLarge ? "arrow.down" : "arrow.right")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(L.t("1 transbordo", "1 transfer"))
                RouteLineIdentity(route: transfer.route)
            }
        }
    }
}
