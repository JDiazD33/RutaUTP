import SwiftUI
import UIKit

// MARK: - Cupones de los negocios del Tracking Demo

struct PerfilCuponesGuardados: View {
    @EnvironmentObject private var router: AppRouter
    @Environment(\.colorScheme) private var colorScheme
    @State private var negocios: [Negocio] = []
    @State private var seleccionado: Negocio?
    @State private var datosCuponesInvalidos = false
    @State private var confirmarReinicio = false
    @State private var errorRecuperacion = false
    @State private var respaldo: URL?

    private var acento: Color { colorScheme == .dark ? .primaryFixed : .appPrimary }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.t("Mis cupones", "My coupons"))
                        .font(.title3.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(L.t("Promociones demo", "Demo offers"))
                        .font(.caption).foregroundStyle(Color.onSurfaceVariant)
                }
                Spacer(minLength: 8)
                Text("\(negocios.count)")
                    .font(.subheadline.weight(.medium)).monospacedDigit()
                    .foregroundStyle(Color.onSurfaceVariant)
            }
            .padding(.horizontal, 20)

            if let respaldo {
                ShareLink(item: respaldo) {
                    Label(L.t("Compartir respaldo de cupones", "Share coupon backup"),
                          systemImage: "square.and.arrow.up")
                        .frame(minHeight: 44)
                }
                .padding(.horizontal, 20)
            }

            if datosCuponesInvalidos {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L.t("No se pudieron leer tus cupones guardados. Se conservaron los datos originales.",
                             "Your saved coupons could not be read. The original data was preserved."))
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(L.t("Reintentar lectura", "Retry reading"), action: actualizar)
                        .frame(minHeight: 44)
                    Button(L.t("Respaldar y reiniciar cupones", "Back up and reset coupons")) {
                        confirmarReinicio = true
                    }
                    .frame(minHeight: 44)
                }
                .padding(.horizontal, 20)
            } else if negocios.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "ticket")
                            .font(.body)
                            .foregroundStyle(acento)
                            .frame(width: 28, height: 28)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L.t("Sin cupones guardados", "No saved coupons"))
                                .font(.subheadline.weight(.semibold))
                            Text(L.t("Guarda un cupón desde un negocio del mapa.",
                                     "Save a coupon from a business on the map."))
                                .font(.caption).foregroundStyle(Color.onSurfaceVariant)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    Divider().padding(.leading, 56).accessibilityHidden(true)
                    Button {
                        router.navigate(to: .trackingDemo)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "map")
                                .frame(width: 28, height: 28)
                                .accessibilityHidden(true)
                            Text(L.t("Explorar negocios", "Explore businesses"))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.onSurfaceVariant.opacity(0.55))
                                .accessibilityHidden(true)
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(acento)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
        .alert(L.t("¿Empezar una nueva lista de cupones?", "Start a new coupon list?"),
               isPresented: $confirmarReinicio) {
            Button(L.t("Respaldar y reiniciar", "Back up and reset"), role: .destructive) {
                do {
                    if let archivo = try NegociosService.shared.respaldarYReiniciarCupones() {
                        respaldo = archivo
                    }
                    actualizar()
                } catch { errorRecuperacion = true }
            }
            Button(L.t("Cancelar", "Cancel"), role: .cancel) {}
        } message: {
            Text(L.t("Se guardará una copia de los datos originales en tus documentos y la lista de cupones quedará vacía.",
                     "A copy of the original data will be saved in your documents and the coupon list will be empty."))
        }
        .alert(L.t("No se pudo reiniciar", "Couldn't reset"), isPresented: $errorRecuperacion) {
            Button(L.t("Aceptar", "OK"), role: .cancel) {}
        } message: {
            Text(L.t("No se reiniciaron los datos. Reintenta la lectura y comprueba el espacio disponible.",
                     "The data was not reset. Retry reading and check available storage."))
        }
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
        datosCuponesInvalidos = NegociosService.shared.datosCuponesInvalidos
        if !datosCuponesInvalidos {
            negocios = NegociosService.shared.cuponesGuardados()
        }
    }
}

private struct PerfilCuponCard: View {
    let negocio: Negocio
    let abrir: () -> Void
    @State private var copiado = false
    @State private var errorGuardado = false

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
                            .locale(FormatoFecha.localeActivo)))
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
                        do {
                            try NegociosService.shared.quitarCupon(negocio)
                        } catch {
                            errorGuardado = true
                        }
                    } label: {
                        Image(systemName: "bookmark.slash")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(L.t("Quitar cupón de ", "Remove coupon from ") + negocio.nombre)
                }
                .buttonStyle(.plain)
            }
            .padding(18)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .alert(L.t("No se pudo quitar el cupón", "Couldn't remove coupon"), isPresented: $errorGuardado) {
                Button(L.t("Aceptar", "OK"), role: .cancel) {}
            } message: {
                Text(L.t("Los cupones guardados no se pueden leer. Se conservaron los datos originales.",
                         "Saved coupons could not be read. The original data was preserved."))
            }
        }
    }
}
