//
//  SheetHeader.swift
//  RutaUTP
//
//  Cabecera compartida por las hojas del menú lateral del Mapa.
//

import SwiftUI

struct SheetHeader: View {
    let icon: String
    let iconColor: Color
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(iconColor)
            }
            .accessibilityHidden(true)
            Text(title)
                .font(.headlineMd)
                .foregroundStyle(.onSurface)
            Spacer()
        }
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
