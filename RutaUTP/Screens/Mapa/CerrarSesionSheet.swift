//
//  CerrarSesionSheet.swift
//  RutaUTP
//
//  Hoja de confirmación de cierre de sesión del menú lateral del Mapa.
//

import SwiftUI

struct CerrarSesionSheet: View {
    var onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var lloraScale: CGFloat = 1.0
    /// Confirmación final. Vive aquí y no en el drawer: un alert declarado en
    /// la vista de fondo, con este sheet ya presentado, no aparece de forma
    /// fiable en SwiftUI.
    @State private var confirmarCierre = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            // Carita llorando animada
            ZStack {
                Circle()
                    .fill(Color.appPrimary.opacity(0.10))
                    .frame(width: 140, height: 140)
                Image(systemName: "face.dashed")
                    .font(.system(size: 80))
                    .foregroundStyle(.appAccent)
                    .scaleEffect(lloraScale)
            }

            VStack(spacing: 8) {
                Text(L.t("¿Te vas?", "Leaving already?"))
                    .font(.displayLg)
                    .foregroundStyle(.onSurface)
                Text(L.t("Lamentamos verte partir. Puedes volver cuando quieras.",
                          "We hate to see you go. You can come back whenever you want."))
                    .font(.bodyMd)
                    .foregroundStyle(.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()

            VStack(spacing: 10) {
                Button {
                    confirmarCierre = true
                } label: {
                    Text(L.t("Sí, cerrar sesión", "Yes, log out"))
                        .font(.headlineSm)
                        .foregroundStyle(.onPrimaryFill)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.primaryFill)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    dismiss()
                } label: {
                    Text(L.t("Cancelar", "Cancel"))
                        .font(.bodyMdMedium)
                        .foregroundStyle(.onSurfaceVariant)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                lloraScale = 1.1
            }
        }
        .alert(L.t("Cerrar sesión", "Log out"), isPresented: $confirmarCierre) {
            Button(L.t("Cerrar sesión", "Log out"), role: .destructive) {
                onConfirm()
                dismiss()
            }
            Button(L.t("Cancelar", "Cancel"), role: .cancel) { }
        } message: {
            Text(L.t("Tendrás que volver a iniciar sesión para usar la app.",
                       "You will need to sign in again to use the app."))
        }
    }
}
