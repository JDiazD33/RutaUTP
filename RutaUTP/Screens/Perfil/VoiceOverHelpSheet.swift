import SwiftUI

/// iOS controla VoiceOver. Perfil ofrece su estado real y una guía accesible.
struct VoiceOverHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverOn

    private var pasos: [String] {
        [L.t("Abre Ajustes en tu iPhone.", "Open Settings on your iPhone."),
         L.t("Entra en Accesibilidad y luego en VoiceOver.", "Go to Accessibility, then VoiceOver."),
         L.t("Activa o desactiva VoiceOver con su interruptor.", "Use the switch to turn VoiceOver on or off.")]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Label(voiceOverOn ? L.t("VoiceOver está activado", "VoiceOver is on")
                                     : L.t("VoiceOver está desactivado", "VoiceOver is off"),
                          systemImage: voiceOverOn ? "speaker.wave.3.fill" : "speaker.slash.fill")
                        .font(.headline)
                        .foregroundStyle(Color.appPrimary)
                        .accessibilityAddTraits(.isHeader)

                    Text(L.t("VoiceOver describe los controles y lee la pantalla. La activación se realiza en iOS; esta app mantiene sus controles accesibles aunque VoiceOver esté apagado.",
                             "VoiceOver describes controls and reads the screen. You turn it on in iOS; this app keeps its controls accessible even when VoiceOver is off."))
                        .foregroundStyle(Color.onSurfaceVariant)

                    VStack(alignment: .leading, spacing: 12) {
                        encabezado(L.t("Activación en el iPhone", "Turn it on on iPhone"))
                        ForEach(pasos.indices, id: \.self) { i in
                            Text("\(i + 1). \(pasos[i])")
                                .accessibilityLabel(L.t("Paso \(i + 1). ", "Step \(i + 1). ") + pasos[i])
                        }
                        Text(L.t("También puedes pedirle a Siri que active o desactive VoiceOver.",
                                 "You can also ask Siri to turn VoiceOver on or off."))
                            .foregroundStyle(Color.onSurfaceVariant)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        encabezado(L.t("Cómo navegar", "How to navigate"))
                        instruccion(L.t("Explorar", "Explore"),
                                    L.t("Desliza un dedo a derecha o izquierda para recorrer los controles.",
                                        "Swipe one finger right or left to move between controls."))
                        instruccion(L.t("Activar un control", "Activate a control"),
                                    L.t("Después de escucharlo, toca dos veces en cualquier parte de la pantalla.",
                                        "After hearing it, double-tap anywhere on the screen."))
                        instruccion(L.t("Desplazar una lista", "Scroll a list"),
                                    L.t("Desliza tres dedos para ver más contenido.",
                                        "Swipe with three fingers to scroll."))
                        instruccion(L.t("Acciones adicionales", "Additional actions"),
                                    L.t("En controles con acciones, el rotor permite elegir opciones como mover un punto del mapa o abrir un reporte.",
                                        "On controls with actions, use the rotor to choose options such as moving a map point or opening a report."))
                    }

                    Text(L.t("En Ajustes puedes configurar la Función rápida de accesibilidad para usar el botón lateral o de inicio. VoiceOver también dispone de un tutorial para practicar sus gestos.",
                             "In Settings, you can configure the Accessibility Shortcut for the side or Home button. VoiceOver also includes a tutorial for practicing gestures."))
                        .foregroundStyle(Color.onSurfaceVariant)

                    if let url = URL(string: "https://support.apple.com/guide/iphone/iph3e2e415f/ios") {
                        Link(destination: url) {
                            Label(L.t("Guía de VoiceOver de Apple", "Apple VoiceOver guide"), systemImage: "arrow.up.right.square")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .accessibilityHint(L.t("Abre la guía oficial en el navegador", "Opens the official guide in your browser"))
                    }
                }
                .font(.body)
                .foregroundStyle(Color.onSurface)
                .fixedSize(horizontal: false, vertical: true)
                .padding(20)
            }
            .background(Color.appBackground)
            .navigationTitle(L.t("Ayuda de VoiceOver", "VoiceOver help"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("Cerrar", "Close")) { dismiss() }
                        .accessibilityLabel(L.t("Cerrar ayuda de VoiceOver", "Close VoiceOver help"))
                }
            }
        }
        .tint(Color.appPrimary)
        .accessibilityAction(.escape) { dismiss() }
    }

    private func encabezado(_ texto: String) -> some View {
        Text(texto).font(.headline).accessibilityAddTraits(.isHeader)
    }

    private func instruccion(_ titulo: String, _ texto: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titulo).font(.body.weight(.semibold))
            Text(texto).foregroundStyle(Color.onSurfaceVariant)
        }
        .accessibilityElement(children: .combine)
    }
}
