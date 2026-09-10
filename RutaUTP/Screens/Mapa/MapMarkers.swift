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

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.secondaryContainer.opacity(0.35))
                .frame(width: pulsando ? 32 : 20, height: pulsando ? 32 : 20)
                .animation(
                    .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
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
        .onAppear { pulsando = true }
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

// MARK: - Bus: línea legible, rumbo separado y selección
struct AnimatedBusMarker: View {
    let linea: String
    let color: Color
    let heading: Double
    var seleccionado: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 4) {
            Text(linea)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.onSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.surfaceContainerLowest, in: Capsule())
                .overlay(Capsule().stroke(color.opacity(0.55), lineWidth: 1))

            ZStack {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(color.opacity(seleccionado ? 0.22 : 0.09))
                    .frame(width: 52, height: 52)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.surfaceContainerLowest)
                    .frame(width: 42, height: 42)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(color, lineWidth: seleccionado ? 3 : 1.5)
                    }
                // El vehículo permanece derecho aunque cambie de rumbo.
                Image(systemName: "bus.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Color.onSurface)
                if heading.isFinite && heading >= 0 {
                    Image(systemName: "arrowtriangle.up.fill")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(Color.onSurface)
                        .padding(3)
                        .background(Color.surfaceContainerLowest, in: Circle())
                        .offset(y: -25)
                        .rotationEffect(.degrees(heading))
                }
                if seleccionado {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(Color.onSurface)
                        .frame(width: 17, height: 17)
                        .background(Color.surfaceContainerLowest, in: Circle())
                        .overlay(Circle().stroke(color, lineWidth: 1.5))
                        .offset(x: 20, y: 20)
                }
            }
        }
        .frame(minWidth: 60, maxWidth: 88)
        .padding(3)
        .shadow(color: .black.opacity(0.16), radius: 4, x: 0, y: 2)
        .contentShape(Rectangle())
        .scaleEffect(seleccionado ? 1.08 : 1)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: seleccionado)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.t("Micro, línea ", "Bus, line ") + linea)
        .accessibilityValue(seleccionado ? L.t("Seleccionado", "Selected") : "")
        .accessibilityHint(L.t("Toca para ver la información del micro", "Tap to view bus information"))
        .accessibilityAddTraits(.isButton)
    }
}
