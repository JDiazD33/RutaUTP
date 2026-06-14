//
//  MapMarkers.swift
//  RutaUTP
//
//  Marcadores personalizados del mapa (compartidos entre MapaView y RutasView).
//

import SwiftUI

// MARK: - Bus marker (punto rojo pulsante)
struct BusMarker: View {
    let linea: String
    @State private var pulsando = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.appPrimary.opacity(0.25))
                .frame(width: pulsando ? 20 : 12, height: pulsando ? 20 : 12)
                .animation(
                    .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                    value: pulsando
                )
            Circle()
                .fill(Color.appPrimary)
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
        }
        .onAppear { pulsando = true }
    }
}

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
