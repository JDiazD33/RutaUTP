//
//  PerfilView.swift
//  RutaUTP
//
//  Perfil con identidad, billetera y ajustes organizados por seccion.
//

import SwiftUI
import UIKit

struct PerfilView: View {
    @Environment(\.bottomNavBarHeight) private var tabBarHeight
    @Environment(\.mainNavigationHostedExternally) private var navigationHostedExternally
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverOn
    @ScaledMetric(relativeTo: .title2) private var avatarSize = 72.0

    private var apilarContenido: Bool { textSize >= .xxxLarge }
    private var acentoPerfil: Color { colorScheme == .dark ? .primaryFixed : .appPrimary }

    // Dato institucional del prototipo. DatosPersonalesSheet lo presenta como
    // "solo lectura" (viene de la universidad), así que aquí no se edita.
    @State private var nombre: String = "Joaquín Díaz"
    /// Preferencias del usuario. En @AppStorage para que sobrevivan al cambio
    /// de pestaña: RootView reconstruye cada pantalla al navegar, así que con
    /// @State se perdían en cada visita.
    @AppStorage(PreferenciasApp.compartirUbicacion) private var ubicacionOn: Bool = true
    /// Modo Señas. Se lee desde varias pantallas, por eso va en AppStorage
    /// y no en @State: cualquier vista reacciona al cambio al instante.
    @AppStorage(SeniasService.llaveModo) private var modoSenias: Bool = false
    @State private var showOfflineMapPopup: Bool = false
    @State private var showUbicacionPopup: Bool = false
    @State private var ubicacionPopupMensaje: String = ""
    @State private var ubicacionPopupSubtitulo: String = ""
    @State private var showDatosPersonales: Bool = false
    @State private var showVoiceOverHelp: Bool = false
    @State private var showRespaldos: Bool = false
    @State private var mostrarIdiomas = false
    @State private var mostrarNotificaciones = false
    @State private var mostrarCredenciales = false
    //  CORREGIDO V3: estado para Wallet
    @State private var showTarjetaSheet: Bool = false
    @State private var showRecargarSaldo: Bool = false
    @State private var showQRPasaje: Bool = false
    @State private var showCarneDigital: Bool = false
    @State private var showCarnetScanner: Bool = false
    @State private var empresaDelCarnet: TematicaEmpresa = .utp
    @State private var carnetGuardado: Bool = false
    @State private var empresaFotoVerificada: TematicaEmpresa?
    @StateObject private var tarjetasStore = TarjetasStore()
    /// Monedero de pasajes: el contenido real de la billetera.
    @StateObject private var monederoStore = MonederoStore()
    /// Misma foto que en el drawer: ProfileImageStore es la fuente única.
    @State private var fotoPerfil: UIImage? = nil
    @State private var revisionFotos = UUID()
    private let preferenciasVisuales = PreferenciasVisualesPerfilStore.shared

    private var empresa: TematicaEmpresa { TematicaEmpresaStore.shared.seleccion }
    private var mostrarCarnetFoto: Bool { preferenciasVisuales.visible(.foto, empresa: empresa) }
    private var mostrarCarnetDigital: Bool { preferenciasVisuales.visible(.digital, empresa: empresa) }
    private var hayCarnetGuardado: Bool { carnetGuardado && empresaFotoVerificada == empresa }
    private var rolPerfil: String {
        empresa == .utp ? L.t("ESTUDIANTE UTP", "UTP STUDENT")
            : L.t("COLABORADOR · ", "EMPLOYEE · ") + empresa.nombre.uppercased()
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.appBackground.ignoresSafeArea()

            ZStack(alignment: .bottom) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 28) {
                        hero
                            .padding(.horizontal, 20)

                        billetera
                            .padding(.horizontal, 20)

                        PerfilCuponesGuardados()

                        configuracion
                            .padding(.horizontal, 20)
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                }
                .padding(.bottom, tabBarHeight)

                if !navigationHostedExternally { BottomNavBar() }
            }

        }
        .ignoresSafeArea(edges: .bottom)
        .sheet(isPresented: $mostrarIdiomas) {
            SelectorIdioma()
                .presentationDetents([.medium, .large])
                .seguirTemaForzado()
        }
        .sheet(isPresented: $mostrarNotificaciones) {
            NotificacionesView().seguirTemaForzado().presentationDetents([.large])
        }
        .sheet(isPresented: $mostrarCredenciales) {
            PerfilPreferenciasVisuales(empresa: empresa)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .seguirTemaForzado()
        }
        // Foto de perfil: recargar al entrar y al volver de Datos Personales.
        .onAppear {
            // Solo DEBUG: abre directo el Carné Digital, p.ej.
            // xcrun simctl launch ... apolito.RutaUTP --pantalla perfil --carne
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--carne"), mostrarCarnetDigital {
                empresaDelCarnet = empresa
                showCarneDigital = true
            }
            // Monedero: permite mirar sus hojas sin navegar hasta ellas.
            if ProcessInfo.processInfo.arguments.contains("--qr") { showQRPasaje = true }
            if ProcessInfo.processInfo.arguments.contains("--recargar") { showRecargarSaldo = true }
            #endif
        }
        .task(id: "\(empresa.rawValue)-\(mostrarCarnetFoto)-\(revisionFotos.uuidString)") {
            let empresaActual = empresa
            let foto = await ProfileImageStore.load()
            guard !Task.isCancelled else { return }
            fotoPerfil = foto
            let disponible = mostrarCarnetFoto
                ? await CarnetImageStore.hasStoredImage(empresa: empresaActual) : false
            guard !Task.isCancelled else { return }
            carnetGuardado = disponible
            empresaFotoVerificada = empresaActual
        }
        .onChange(of: empresa) { _, _ in
            carnetGuardado = false
            showCarneDigital = false
            showCarnetScanner = false
            mostrarCredenciales = false
        }
        .onChange(of: mostrarCarnetFoto) { _, visible in
            if !visible { showCarnetScanner = false }
        }
        .onChange(of: mostrarCarnetDigital) { _, visible in
            if !visible { showCarneDigital = false }
        }
        .onChange(of: showDatosPersonales) { _, abierto in
            if !abierto { revisionFotos = UUID() }
        }
        // La foto puede cambiar dentro del Carné Digital: recargar al cerrar.
        .onChange(of: showCarneDigital) { _, abierto in
            if !abierto { revisionFotos = UUID() }
        }
        .onChange(of: ubicacionOn) { _, activo in
            if activo {
                ubicacionPopupMensaje = L.t("Preferencia activada", "Preference enabled")
                ubicacionPopupSubtitulo = L.t("Se guardó tu preferencia. Esta versión no comparte tu ubicación con otros usuarios ni modifica los permisos de GPS de iOS.", "Your preference was saved. This version does not share your location with other users or change iOS GPS permissions.")
            } else {
                ubicacionPopupMensaje = L.t("Preferencia desactivada", "Preference disabled")
                ubicacionPopupSubtitulo = L.t("Se guardó tu preferencia. El GPS del mapa se controla por separado; este ajuste no cambia los permisos de iOS.", "Your preference was saved. Map GPS is controlled separately; this setting does not change iOS permissions.")
            }
            showUbicacionPopup = true
        }
        .alert(ubicacionPopupMensaje, isPresented: $showUbicacionPopup) {
            Button(L.t("Entendido", "Got it"), role: .cancel) { }
        } message: {
            Text(L.aviso(ubicacionPopupSubtitulo))
        }
        // Sheet de Tarjeta
        .sheet(isPresented: $showTarjetaSheet) {
            MetodosPagoSheet(store: tarjetasStore)
            .presentationDetents([.large])
        }
        // Monedero: saldo propio de la app. Recarga y cobro simulados.
        .sheet(isPresented: $showRecargarSaldo) {
            RecargarSaldoSheet(store: monederoStore)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showQRPasaje) {
            QRPasajeSheet(store: monederoStore)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        // Sheet del Carné Digital (identificación con código de barras)
        .sheet(isPresented: $showCarneDigital) {
            CarneDigitalView(nombre: nombre, empresa: empresaDelCarnet)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .seguirTemaForzado()
        }
        // Scanner de Carnet
        .fullScreenCover(isPresented: $showCarnetScanner) {
            let empresaCaptura = empresaDelCarnet
            CarnetScannerView(empresa: empresaCaptura) {
                carnetGuardado = true
                empresaFotoVerificada = empresaCaptura
                revisionFotos = UUID()
            }
            .seguirTemaForzado()
        }
        // Sheet de Datos Personales (reutilizado del SideDrawer)
        .sheet(isPresented: $showDatosPersonales) {
            DatosPersonalesSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        // Disponibilidad y límites de los datos sin conexión
        .sheet(isPresented: $showOfflineMapPopup) {
            OfflineMapSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .seguirTemaForzado()
        }
        // Sheet con instrucciones para activar VoiceOver
        .sheet(isPresented: $showVoiceOverHelp) {
            VoiceOverHelpSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .seguirTemaForzado()
        }
        .sheet(isPresented: $showRespaldos) {
            RespaldosRecuperacionSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .seguirTemaForzado()
        }
    }

    // MARK: - Identidad
    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L.t("Perfil", "Profile"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.onSurfaceVariant)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    AppHaptics.impact(.light)
                    showDatosPersonales = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(acentoPerfil)
                        .frame(width: 44, height: 44)
                        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.t("Editar perfil", "Edit profile"))
            }

            (apilarContenido ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
                              : AnyLayout(HStackLayout(alignment: .center, spacing: 16))) {
                ZStack {
                    Circle().fill(Color(uiColor: .tertiarySystemGroupedBackground))
                    if let fotoPerfil {
                        Image(uiImage: fotoPerfil)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Text(iniciales(nombre))
                            .font(.headlineMd)
                            .foregroundStyle(acentoPerfil)
                    }
                }
                .frame(width: avatarSize, height: avatarSize)
                .clipShape(Circle())
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    Text(nombre)
                        .font(.title2.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(rolPerfil)
                        .font(.caption.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(Color.onSurfaceVariant)
                    if mostrarCarnetFoto, hayCarnetGuardado {
                        Label(L.t("Carné guardado", "Card saved"), systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(acentoPerfil)
                    }
                }
                .foregroundStyle(Color.onSurface)
                if !apilarContenido { Spacer(minLength: 0) }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(nombre + ", " + rolPerfil
                + (mostrarCarnetFoto && hayCarnetGuardado
                   ? L.t(", carné guardado", ", card saved") : ""))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: - Billetera
    private var billetera: some View {
        VStack(alignment: .leading, spacing: 14) {
            (apilarContenido ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                              : AnyLayout(HStackLayout(alignment: .center, spacing: 12))) {
                Text(L.t("Mi billetera", "My wallet"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.onSurface)
                    .accessibilityAddTraits(.isHeader)
                if !apilarContenido { Spacer(minLength: 0) }
                Button {
                    AppHaptics.impact(.light)
                    mostrarCredenciales = true
                } label: {
                    Label(L.t("Credenciales", "Credentials"), systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(acentoPerfil)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(L.t("Elige qué carnés aparecen en tu billetera", "Choose which cards appear in your wallet"))
            }

            MonederoCard(store: monederoStore,
                         onRecargar: { showRecargarSaldo = true },
                         onMostrarQR: { showQRPasaje = true },
                         empresa: empresa)

            grupoFilas {
                if mostrarCarnetFoto {
                    chevronRow(icon: CarnetPerfil.foto.icono, iconColor: .appAccent,
                               label: CarnetPerfil.foto.tituloBreve(para: empresa),
                               detalle: hayCarnetGuardado
                                   ? L.t("Ver foto", "View photo")
                                   : L.t("Añadir foto", "Add photo")) {
                        AppHaptics.impact(.light)
                        empresaDelCarnet = empresa
                        showCarnetScanner = true
                    }
                    separadorFila
                }
                if mostrarCarnetDigital {
                    chevronRow(icon: CarnetPerfil.digital.icono, iconColor: .appAccent,
                               label: CarnetPerfil.digital.tituloBreve(para: empresa),
                               detalle: L.t("Muestra · sin validez", "Sample · not valid")) {
                        AppHaptics.impact(.light)
                        empresaDelCarnet = empresa
                        showCarneDigital = true
                    }
                    separadorFila
                }
                chevronRow(icon: "creditcard.fill", iconColor: .appAccent,
                           label: L.t("Mis tarjetas", "My cards"),
                           detalle: L.t("Referencias locales · sin pagos", "Local references · no payments")) {
                    AppHaptics.impact(.light)
                    showTarjetaSheet = true
                }
                .accessibilityHint(L.t("Organiza referencias guardadas en este dispositivo. No permite pagar",
                                       "Organize references saved on this device. Payments are not supported"))
            }
        }
    }

    // MARK: - Ajustes
    private var configuracion: some View {
        VStack(alignment: .leading, spacing: 28) {
            if TransporteApp.busesUTPDisponibles { ModoBusesUTPSection() }

            VStack(alignment: .leading, spacing: 12) {
                tituloSeccion(L.t("Preferencias", "Preferences"))
                grupoFilas {
                    chevronRow(icon: "globe", iconColor: .appAccent,
                               label: L.t("Idioma", "Language"),
                               detalle: IdiomaManager.shared.idioma.nombreNativo) {
                        mostrarIdiomas = true
                    }
                    separadorFila
                    TimelineView(.periodic(from: .now, by: 60)) { contexto in
                        chevronRow(icon: "bell.fill", iconColor: .appAccent,
                                   label: L.t("Notificaciones", "Notifications"),
                                   detalle: NotificacionesService.shared.resumen(ahora: contexto.date)) {
                            mostrarNotificaciones = true
                        }
                    }
                    separadorFila
                    offlineToggleRow
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                tituloSeccion(L.t("Accesibilidad", "Accessibility"))
                grupoFilas {
                    toggleRow(icon: "hand.raised.fill", iconColor: .tertiary,
                              label: L.signable("perfil.modo_senias", "Modo Señas", "Sign Language Mode"),
                              isOn: $modoSenias)
                        .seniable("perfil.modo_senias", conGesto: false)
                    separadorFila
                    accesibilidadRow()
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                tituloSeccion(L.t("Privacidad y datos", "Privacy and data"))
                grupoFilas {
                    chevronRow(icon: "person.crop.circle", iconColor: .appAccent,
                               label: L.t("Datos personales", "Personal details")) {
                        AppHaptics.impact(.light)
                        showDatosPersonales = true
                    }
                    separadorFila
                    chevronRow(icon: "archivebox", iconColor: .appAccent,
                               label: L.t("Respaldos guardados", "Saved backups")) {
                        AppHaptics.impact(.light)
                        showRespaldos = true
                    }
                    separadorFila
                    toggleRow(icon: "mappin.circle.fill", iconColor: .secondary,
                              label: L.t("Preferencia de ubicación", "Location preference"), isOn: $ubicacionOn)
                }
                DisclosureGroup(L.t("Sobre la ubicación", "About location")) {
                    Text(L.t("La preferencia de compartir ubicación se guarda en este dispositivo. No comparte tu ubicación con otros usuarios ni desactiva el GPS del mapa.",
                             "The location sharing preference is saved on this device. It does not share your location with other users or turn off map GPS."))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }
                .font(.footnote)
                .foregroundStyle(Color.onSurfaceVariant)
                .tint(.appAccent)
                .padding(.horizontal, 16)
            }
        }
    }

    private func accesibilidadRow() -> some View {
        chevronRow(icon: voiceOverOn ? "speaker.wave.3.fill" : "speaker.slash.fill",
                   iconColor: .appAccent, label: L.t("VoiceOver", "VoiceOver"),
                   detalle: voiceOverOn ? L.t("Activado", "On") : L.t("Desactivado", "Off")) {
            AppHaptics.impact(.light)
            showVoiceOverHelp = true
        }
        .accessibilityHint(L.t("Muestra instrucciones de activación y gestos de navegación", "Shows activation instructions and navigation gestures"))
    }

    private var offlineToggleRow: some View {
        chevronRow(icon: "wifi.slash", iconColor: .secondary,
                   label: L.t("Modo offline", "Offline mode")) {
            AppHaptics.impact(.light)
            showOfflineMapPopup = true
        }
        .accessibilityHint(L.t("Consulta qué puedes usar sin internet", "See what works without internet"))
    }

    private func tituloSeccion(_ titulo: String) -> some View {
        Text(titulo)
            .font(.footnote.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(Color.onSurfaceVariant)
            .padding(.horizontal, 16)
            .accessibilityAddTraits(.isHeader)
    }

    private func grupoFilas<Contenido: View>(@ViewBuilder contenido: () -> Contenido) -> some View {
        VStack(spacing: 0, content: contenido)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var separadorFila: some View {
        Divider().padding(.leading, 56).accessibilityHidden(true)
    }

    private func iconoFila(_ icono: String, color: Color) -> some View {
        Image(systemName: icono)
            .font(.body.weight(.regular))
            .foregroundStyle(colorScheme == .dark ? Color.primaryFixed : color)
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
    }

    private func toggleRow(icon: String, iconColor: Color, label: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            iconoFila(icon, color: iconColor)
            Toggle(isOn: isOn) {
                Text(label)
                    .font(.bodyMd)
                    .foregroundStyle(Color.onSurface)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .tint(.appAccent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 60)
    }

    private func chevronRow(icon: String, iconColor: Color, label: String,
                            detalle: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                iconoFila(icon, color: iconColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text(label).font(.bodyMd).foregroundStyle(Color.onSurface)
                    if let detalle {
                        Text(detalle).font(.footnote).foregroundStyle(Color.onSurfaceVariant)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.onSurfaceVariant.opacity(0.55))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(detalle ?? "")
        .accessibilityHint(L.t("Doble toque para abrir", "Double tap to open"))
    }

    // MARK: - Helpers
    private func iniciales(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first }.map { String($0) }.joined()
    }
}

#Preview {
    PerfilView().environmentObject(AppRouter())
}
