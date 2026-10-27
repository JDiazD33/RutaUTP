//
//  MonederoCard.swift
//  RutaUTP
//
//  Tarjeta del monedero en el Perfil.
//

import SwiftUI
import UIKit

struct MonederoCard: View {
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("perfil.monedero.saldoOculto.v1") private var saldoOculto = false

    @ObservedObject var store: MonederoStore
    let onRecargar: () -> Void
    let onMostrarQR: () -> Void
    var empresa: TematicaEmpresa = .utp

    private var acento: Color { colorScheme == .dark ? .primaryFixed : .appPrimary }

    private var resumenSaldo: String {
        if saldoOculto { return L.t("Saldo oculto", "Balance hidden") }
        return L.f("Saldo de demostración {0}, aproximadamente {1} pasajes a {2}",
                   "Demo balance {0}, approximately {1} fares at {2}",
                   [store.saldoTexto, "\(store.pasajesDisponibles)", store.tarifaTexto])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "ticket")
                    .font(.body)
                    .foregroundStyle(acento)
                    .accessibilityHidden(true)
                Text(L.t("Saldo de demostración", "Demo balance"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button {
                    AppHaptics.selection()
                    saldoOculto.toggle()
                } label: {
                    Image(systemName: saldoOculto ? "eye" : "eye.slash")
                        .font(.body)
                        .foregroundStyle(acento)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(saldoOculto
                    ? L.t("Mostrar saldo", "Show balance")
                    : L.t("Ocultar saldo", "Hide balance"))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(saldoOculto ? "••••" : store.saldoTexto)
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(Color.onSurface)
                Group {
                    if saldoOculto {
                        Text(L.t("Saldo oculto", "Balance hidden"))
                    } else {
                        Text(L.f("≈ {0} pasajes a {1}", "≈ {0} fares at {1}",
                                 ["\(store.pasajesDisponibles)", store.tarifaTexto]))
                    }
                }
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(Color.onSurfaceVariant)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L.t("Saldo de demostración", "Demo balance"))
            .accessibilityValue(resumenSaldo)

            (textSize >= .xxxLarge ? AnyLayout(VStackLayout(spacing: 10))
                                    : AnyLayout(HStackLayout(spacing: 10))) {
                boton(L.t("Recargar", "Top up"), icono: "plus", accion: onRecargar)
                boton(L.t("Pagar con QR", "Pay with QR"),
                      icono: "qrcode", destacado: true,
                      accion: onMostrarQR)
            }
            .padding(.top, 6)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L.t("Monedero ", "Wallet ") + empresa.nombre)
    }

    private func boton(_ titulo: String, icono: String, destacado: Bool = false,
                       accion: @escaping () -> Void) -> some View {
        Button {
            AppHaptics.impact(.light)
            accion()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icono)
                    .accessibilityHidden(true)
                Text(titulo)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(destacado ? Color(uiColor: .systemBackground) : Color.onSurface)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(destacado ? Color(uiColor: .label) : Color(uiColor: .tertiarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
