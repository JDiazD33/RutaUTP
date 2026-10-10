import SwiftUI
import UIKit

// MARK: - Cupones de los negocios del Tracking Demo

struct PerfilCuponesGuardados: View {
    @EnvironmentObject private var router: AppRouter
    @State private var negocios: [Negocio] = []
    @State private var seleccionado: Negocio?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "ticket.fill")
                    .foregroundStyle(Color.appPrimary)
                Text(L.t("Mis cupones", "My coupons"))
                    .font(.title3.bold())
                Spacer()
                Text("\(negocios.count)")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.appPrimary.opacity(0.1), in: Capsule())
            }
            .padding(.horizontal, 20)

            Text(L.t("Tus promociones guardadas en Tracking Demo.",
                     "Your saved offers from Tracking Demo."))
                .font(.subheadline).foregroundStyle(Color.onSurfaceVariant)
                .padding(.horizontal, 20)

            if negocios.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "ticket")
                        .font(.system(size: 32)).foregroundStyle(Color.appPrimary)
                    Text(L.t("Tu próxima promo te espera", "Your next offer awaits"))
                        .font(.headline)
                    Text(L.t("Abre un negocio en el mapa y toca Guardar en su cupón. Aparecerá aquí.",
                             "Open a business on the map and tap Save on its coupon. It will appear here."))
                        .font(.subheadline).foregroundStyle(Color.onSurfaceVariant)
                        .multilineTextAlignment(.center)
                    Button {
                        router.navigate(to: .trackingDemo)
                    } label: {
                        Label(L.t("Explorar negocios", "Explore businesses"), systemImage: "map.fill")
                            .font(.subheadline.bold()).padding(.vertical, 10).padding(.horizontal, 16)
                            .foregroundStyle(.onPrimaryFill)
                            .background(Color.primaryFill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity).padding(22)
                .background(Color.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 24))
                .padding(.horizontal, 20)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(negocios) { negocio in
                            PerfilCuponCard(negocio: negocio) { seleccionado = negocio }
                                .frame(width: 285)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 20).padding(.bottom, 4)
                }
                .scrollTargetBehavior(.viewAligned)
            }
        }
        .foregroundStyle(Color.onSurface)
        .onAppear(perform: actualizar)
        .onReceive(NotificationCenter.default.publisher(for: NegociosService.cuponesActualizados)
            .receive(on: RunLoop.main)) { _ in actualizar() }
        .sheet(item: $seleccionado, onDismiss: actualizar) { negocio in
            ScrollView {
                NegocioDetailCard(negocio: negocio, ubicacion: nil) { seleccionado = nil }
                    .padding(20)
            }
            .background(Color.appBackground)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .seguirTemaForzado()
        }
    }

    private func actualizar() {
        negocios = NegociosService.shared.cuponesGuardados()
    }
}

private struct PerfilCuponCard: View {
    let negocio: Negocio
    let abrir: () -> Void
    @State private var copiado = false

    var body: some View {
        if let cupon = negocio.cupon {
            VStack(alignment: .leading, spacing: 14) {
                Button(action: abrir) {
                    HStack(spacing: 10) {
                        NegocioIcono(categoria: negocio.categoria, size: 26)
                            .foregroundStyle(Color.onSurface)
                            .frame(width: 50, height: 50)
                            .background(negocio.categoria.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(negocio.nombre).font(.headline).lineLimit(2)
                            Text(negocio.categoria.etiqueta)
                                .font(.caption).foregroundStyle(Color.onSurfaceVariant)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption.bold())
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Text(cupon.detalle.texto)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Label(cupon.vigente ? L.t("Guardado", "Saved") : L.t("Vencido", "Expired"),
                          systemImage: cupon.vigente ? "bookmark.fill" : "clock.badge.exclamationmark")
                    Spacer()
                    Text(L.t("Cupón demo", "Demo coupon"))
                }
                .font(.caption).foregroundStyle(Color.onSurfaceVariant)
                if let fecha = cupon.fechaVencimiento {
                    Text(L.t("Vence: ", "Expires: ") + fecha.formatted(
                        .dateTime.day().month(.abbreviated).year()
                            .locale(Locale(identifier: IdiomaManager.shared.esIngles ? "en_US" : "es_PE"))))
                        .font(.caption).foregroundStyle(Color.onSurfaceVariant)
                }
                Rectangle().fill(negocio.categoria.color.opacity(0.25)).frame(height: 1)
                Button {
                    UIPasteboard.general.string = cupon.codigo
                    copiado = true
                    AppHaptics.success()
                } label: {
                    HStack {
                        Text(cupon.codigo).font(.system(.body, design: .monospaced).bold())
                        Spacer()
                        Image(systemName: copiado ? "checkmark.circle.fill" : "doc.on.doc")
                    }
                    .padding(12)
                    .background(negocio.categoria.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(!cupon.vigente)
                .accessibilityLabel(L.t("Copiar código ", "Copy code ") + cupon.codigo)
                if copiado {
                    Text(L.t("Código copiado", "Code copied"))
                        .font(.caption).foregroundStyle(Color.onSurfaceVariant)
                }
                HStack {
                    Button(L.t("Ver promoción", "View offer"), action: abrir)
                        .font(.subheadline.bold()).foregroundStyle(negocio.categoria.color)
                    Spacer()
                    Button(role: .destructive) {
                        NegociosService.shared.quitarCupon(negocio)
                    } label: {
                        Image(systemName: "bookmark.slash")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(L.t("Quitar cupón de ", "Remove coupon from ") + negocio.nombre)
                }
                .buttonStyle(.plain)
            }
            .padding(18)
            .background(Color.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24)
                .stroke(negocio.categoria.color.opacity(0.22), lineWidth: 1))
        }
    }
}
