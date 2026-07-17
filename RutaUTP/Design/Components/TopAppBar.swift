//
//  TopAppBar.swift
//  RutaUTP
//
//  Header reutilizable para las pantallas principales.
//  Fondo appSurface, altura 56pt + safe area top, sombra sutil.
//

import SwiftUI

struct TopAppBar: View {
    @EnvironmentObject private var router: AppRouter

    var leading: LeadingType = .none
    var title: String? = nil
    var trailingIcon: String? = nil
    var trailingAction: (() -> Void)? = nil
    var titleColor: Color = .appPrimary

    enum LeadingType {
        case none
        case menu
        case back
    }

    var body: some View {
        HStack(spacing: 12) {
            leadingButton
            if let title {
                Text(title)
                    .font(.headlineLgMobile)
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            trailingButton
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .frame(maxWidth: .infinity)
        .background(Color.appSurface)
        .overlay(
            Rectangle()
                .fill(Color.outlineVariant.opacity(0.25))
                .frame(height: 1),
            alignment: .bottom
        )
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 1)
    }

    @ViewBuilder
    private var leadingButton: some View {
        switch leading {
        case .none:
            EmptyView()
        case .menu:
            Button {
                NotificationCenter.default.post(name: .openSideDrawer, object: nil)
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.onSurface)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.surfaceContainerLow))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Abrir menú")
        case .back:
            Button {
                router.navigate(to: .mapaPrincipal)
            } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.onSurface)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.surfaceContainerLow))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Volver")
        }
    }

    @ViewBuilder
    private var trailingButton: some View {
        if let trailingIcon, let trailingAction {
            Button(action: trailingAction) {
                Image(systemName: trailingIcon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.onSurface)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.surfaceContainerLow))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Acción")
        }
    }
}

extension Notification.Name {
    static let openSideDrawer = Notification.Name("RutaUTP.openSideDrawer")
}
