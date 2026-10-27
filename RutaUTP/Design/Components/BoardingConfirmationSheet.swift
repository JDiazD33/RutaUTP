//
//  BoardingConfirmationSheet.swift
//  RutaUTP
//
//  Hoja de confirmación de subida al bus.
//

import SwiftUI
import CoreLocation
import MapKit

struct BoardingConfirmationSheet: View {
    @ObservedObject var coordinator: PassiveTrackingCoordinator
    let locationService: LocationServiceProtocol
    let itinerary: TransitItinerary?
    let onRemindLater: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.colorScheme) private var colorScheme
    @State private var confirmingLine = false
    @State private var alturaConfirmacion: CGFloat = 220

    private var acento: Color { colorScheme == .dark ? .primaryFixed : .appPrimary }

    var body: some View {
        Group {
            if confirmingLine {
                TripSelectionSheet(coordinator: coordinator, locationService: locationService,
                                   itinerary: itinerary)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        pregunta
                        VStack(spacing: 8) {
                            confirmarSubida
                            accionesSecundarias
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(key: BoardingConfirmationHeightKey.self,
                                                   value: geometry.size.height.rounded(.up))
                        }
                        .allowsHitTesting(false)
                    }
                }
                .background(Color.appBackground)
                .scrollBounceBehavior(.basedOnSize)
                .onPreferenceChange(BoardingConfirmationHeightKey.self) { altura in
                    guard altura.isFinite, altura > 0, abs(altura - alturaConfirmacion) > 0.5 else { return }
                    alturaConfirmacion = altura
                }
            }
        }
        .presentationDetents(confirmingLine || textSize.isAccessibilitySize
                             ? [.large] : [.height(alturaConfirmacion)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(20)
    }

    private var pregunta: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(L.t("¿Ya subiste?", "Already on board?"))
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            Image(systemName: "bus")
                .font(.title3)
                .foregroundStyle(acento)
                .accessibilityHidden(true)
        }
    }

    private var confirmarSubida: some View {
        Button { confirmingLine = true } label: {
            Text(L.t("Sí, ya subí", "Yes, I'm on board"))
                .font(.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(Color.onPrimaryFill)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color.primaryFill, in: RoundedRectangle(cornerRadius: 16))
                .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var accionesSecundarias: some View {
        let distribucion = textSize >= .xxxLarge
            ? AnyLayout(VStackLayout(spacing: 4))
            : AnyLayout(HStackLayout(spacing: 12))
        return distribucion {
            Button {
                onRemindLater()
                dismiss()
            } label: {
                Label(L.t("En 2 minutos", "In 2 minutes"), systemImage: "clock")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.t("Recordarme en 2 minutos", "Remind me in 2 minutes"))

            Button { dismiss() } label: {
                Text(L.t("Todavía no", "Not yet"))
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

private enum BoardingConfirmationHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
