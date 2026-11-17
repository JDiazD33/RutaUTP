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
                    estadoVoiceOver
                    descripcion
                    activacion
                    navegacion
                    enRutaUTP
                    ajustes
                    guiaApple
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
        .tint(Color.appAccent)
        .accessibilityAction(.escape) { dismiss() }
    }

    private var estadoVoiceOver: some View {
        Label(voiceOverOn ? L.t("VoiceOver está activado", "VoiceOver is on")
                         : L.t("VoiceOver está desactivado", "VoiceOver is off"),
              systemImage: voiceOverOn ? "speaker.wave.3.fill" : "speaker.slash.fill")
            .font(.headline)
            .foregroundStyle(Color.appAccent)
            .accessibilityAddTraits(.isHeader)
    }

    private var descripcion: some View {
        Text(L.t("VoiceOver describe los controles y lee la pantalla. La activación se realiza en iOS; esta app mantiene sus controles accesibles aunque VoiceOver esté apagado.",
                 "VoiceOver describes controls and reads the screen. You turn it on in iOS; this app keeps its controls accessible even when VoiceOver is off."))
            .foregroundStyle(Color.onSurfaceVariant)
    }

    private var activacion: some View {
        VStack(alignment: .leading, spacing: 12) {
            encabezado(L.t("Activación en el iPhone", "Turn it on on iPhone"))
            ForEach(pasos.indices, id: \.self) { i in
                Text("\(i + 1). \(pasos[i])")
                    .accessibilityLabel(L.f("Paso {0}. ", "Step {0}. ", ["\(i + 1)"]) + pasos[i])
            }
            Text(L.t("También puedes pedirle a Siri que active o desactive VoiceOver.",
                     "You can also ask Siri to turn VoiceOver on or off."))
                .foregroundStyle(Color.onSurfaceVariant)
        }
    }

    private var navegacion: some View {
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
    }

    /// Cómo se usan con VoiceOver las funciones recientes de la app.
    private var enRutaUTP: some View {
        VStack(alignment: .leading, spacing: 12) {
            encabezado(L.t("En RutaUTP", "In RutaUTP"))
            instruccion(L.t("Publicaciones de Comunidad", "Community posts"),
                        L.t("En Seguridad, elige una publicación y desliza un dedo hacia arriba o hacia abajo para escuchar sus acciones: Me gusta, No me gusta, Comentar, Ver foto y Reportar publicación.",
                            "In Safety, choose a post and swipe up or down with one finger to hear its actions: Like, Dislike, Comment, View photo and Report post."))
            instruccion(L.t("Reportar una publicación", "Report a post"),
                        L.t("Dentro de la publicación, el botón Reportar abre los motivos: información falsa, derechos de autor o de imagen, ofensas, datos personales o spam. El motivo elegido se anuncia como seleccionado.",
                            "Inside the post, the Report button opens the reasons: false information, copyright or image rights, offensive content, personal information or spam. The chosen reason is announced as selected."))
            instruccion(L.t("Ver una foto", "View a photo"),
                        L.t("Toca dos veces la foto para abrirla a pantalla completa. Usa las acciones para acercar, alejar o moverla, y frota dos dedos en forma de Z para cerrarla.",
                            "Double-tap the photo to open it full screen. Use the actions to zoom in, zoom out or move it, and scrub two fingers in a Z shape to close it."))
            instruccion(L.t("Cerca de ti", "Near you"),
                        L.t("En Seguridad, sección Ayuda, Comisarías, Salud y Bomberos abren un mapa con los lugares más cercanos y su distancia.",
                            "In Safety, Help section, Police stations, Healthcare and Fire stations open a map with the nearest places and their distance."))
            instruccion(L.t("Sin conexión", "Offline"),
                        L.t("VoiceOver avisa cuando se pierde o se recupera la conexión. Sin internet, el buscador del Mapa ofrece paraderos y lugares guardados. El Modo offline se activa en Perfil.",
                            "VoiceOver tells you when the connection is lost or restored. Without internet, the Map search offers stops and saved places. Turn on Offline mode in Profile."))
            instruccion(L.t("Respaldos guardados", "Saved backups"),
                        L.t("En Perfil, crea, importa, restaura o comparte copias de tus datos. En la lista, las acciones permiten eliminar un respaldo.",
                            "In Profile, create, import, restore or share copies of your data. In the list, the actions let you delete a backup."))
        }
    }

    private var ajustes: some View {
        Text(L.t("En Ajustes puedes configurar la Función rápida de accesibilidad para usar el botón lateral o de inicio. VoiceOver también dispone de un tutorial para practicar sus gestos.",
                 "In Settings, you can configure the Accessibility Shortcut for the side or Home button. VoiceOver also includes a tutorial for practicing gestures."))
            .foregroundStyle(Color.onSurfaceVariant)
    }

    @ViewBuilder
    private var guiaApple: some View {
        if let url = URL(string: "https://support.apple.com/guide/iphone/iph3e2e415f/ios") {
            Link(destination: url) {
                Label(L.t("Guía de VoiceOver de Apple", "Apple VoiceOver guide"), systemImage: "arrow.up.right.square")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .accessibilityHint(L.t("Abre la guía oficial en el navegador", "Opens the official guide in your browser"))
        }
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
