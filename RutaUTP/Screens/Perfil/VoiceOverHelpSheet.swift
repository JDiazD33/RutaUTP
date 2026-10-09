import SwiftUI
import UIKit

// MARK: - Sheet de ayuda para activar VoiceOver
struct VoiceOverHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    private var pasos: [(icon: String, texto: String)] {
        [
        ("gearshape.fill", L.t("Abre la app Ajustes de tu iPhone", "Open your iPhone Settings app")),
        ("hand.point.right.fill", L.t("Toca Accesibilidad", "Tap Accessibility")),
        ("speaker.wave.2.fill", L.t("Toca VoiceOver, primera opción", "Tap VoiceOver, first option")),
        ("togglepower", L.t("Activa el interruptor VoiceOver", "Turn on the VoiceOver switch"))
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.appPrimary.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.appPrimary)
                }
                .accessibilityHidden(true)
                Text(L.t("Activar VoiceOver", "Enable VoiceOver"))
                    .font(.headlineMd)
                    .foregroundStyle(.onSurface)
                Spacer()
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Text(L.t("VoiceOver lee en voz alta lo que tocas en pantalla. Sigue estos pasos para activarlo en tu iPhone:", "VoiceOver reads aloud what you touch on screen. Follow these steps to enable it on your iPhone:"))
                .font(.bodySm)
                .foregroundStyle(.onSurfaceVariant)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(pasos.indices, id: \.self) { i in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.appPrimary.opacity(0.10))
                                .frame(width: 32, height: 32)
                            Image(systemName: pasos[i].icon)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.appPrimary)
                        }
                        .accessibilityHidden(true)
                        Text("\(i + 1). \(pasos[i].texto)")
                            .font(.bodyMd)
                            .foregroundStyle(.onSurface)
                        Spacer()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(L.t("Paso ", "Step ") + "\(i + 1): \(pasos[i].texto)")
                }
            }

            Spacer()

            Button {
                AppHaptics.impact(.light)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.fill")
                        .accessibilityHidden(true)
                    Text(L.t("Abrir Ajustes del iPhone", "Open iPhone Settings"))
                }
                .font(.bodyMdMedium)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.appPrimary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.t("Abrir Ajustes del iPhone", "Open iPhone Settings"))
            .accessibilityHint(L.t("Doble toque para ir directamente a la configuración de la app", "Double tap to go straight to the app settings"))

            Button {
                dismiss()
            } label: {
                Text(L.t("Cerrar", "Close"))
                    .font(.bodyMdMedium)
                    .foregroundStyle(.onSurfaceVariant)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.t("Cerrar instrucciones", "Close instructions"))
        }
        .padding(20)
    }
}

