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
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverOn
    @ScaledMetric(relativeTo: .title2) private var avatarSize = 72.0

    private var apilarContenido: Bool { textSize >= .xxxLarge }

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

    /// Inkafarma conserva el amarillo, con fondos suaves solo en esta cabecera.
    private var coloresCabecera: [Color] {
        empresa == .inkafarma
            ? [Color(light: "#FFF4B5", dark: "#3C381C"),
               Color(light: "#FFF9DF", dark: "#252A1C"),
               Color(light: "#EAF3DF", dark: "#193623")]
            : [.primaryFill, .primaryContainer, .primaryGradientEnd]
    }
    private var tintaCabecera: Color {
        empresa == .inkafarma ? Color(light: "#193D23", dark: "#E8EED2") : .onPrimaryFill
    }
    private var fondoAvatar: Color {
        empresa == .inkafarma ? Color(light: "#EAD983", dark: "#456534") : .primaryFill
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.appBackground.ignoresSafeArea()

            ZStack(alignment: .bottom) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 24) {
                        hero
                            .padding(.horizontal, 20)

                        billetera
                            .padding(.horizontal, 20)

                        configuracion
                            .padding(.horizontal, 20)

                        PerfilCuponesGuardados()
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                }
                .padding(.bottom, tabBarHeight)

                BottomNavBar()
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
                    .font(.labelCapsLg)
                    .foregroundStyle(tintaCabecera.opacity(0.9))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    AppHaptics.impact(.light)
                    showDatosPersonales = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(tintaCabecera)
                        .frame(width: 44, height: 44)
                        .background(tintaCabecera.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.t("Editar perfil", "Edit profile"))
            }

            (apilarContenido ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
                              : AnyLayout(HStackLayout(alignment: .center, spacing: 16))) {
                ZStack {
                    Circle().fill(fondoAvatar)
                    if let fotoPerfil {
                        Image(uiImage: fotoPerfil)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Text(iniciales(nombre))
                            .font(.headlineMd)
                            .foregroundStyle(tintaCabecera)
                    }
                }
                .frame(width: avatarSize, height: avatarSize)
                .clipShape(Circle())
                .overlay(Circle().stroke(tintaCabecera.opacity(0.3), lineWidth: 2))
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    Text(nombre)
                        .font(.headlineLgMobile)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(rolPerfil)
                        .font(.caption.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(tintaCabecera.opacity(0.85))
                    if mostrarCarnetFoto, hayCarnetGuardado {
                        Label(L.t("Carné guardado", "Card saved"), systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(tintaCabecera.opacity(0.12), in: Capsule())
                    }
                }
                .foregroundStyle(tintaCabecera)
                if !apilarContenido { Spacer(minLength: 0) }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(nombre + ", " + rolPerfil
                + (mostrarCarnetFoto && hayCarnetGuardado
                   ? L.t(", carné guardado", ", card saved") : ""))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            LinearGradient(colors: coloresCabecera, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    // MARK: - Billetera
    private var billetera: some View {
        VStack(alignment: .leading, spacing: 14) {
            (apilarContenido ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                              : AnyLayout(HStackLayout(alignment: .center, spacing: 12))) {
                tituloSeccion(L.t("Mi billetera", "My wallet"))
                if !apilarContenido { Spacer(minLength: 0) }
                Button {
                    AppHaptics.impact(.light)
                    mostrarCredenciales = true
                } label: {
                    Label(L.t("Credenciales", "Credentials"), systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.onPrimaryContainer)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(Color.primaryContainer, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint(L.t("Elige qué carnés aparecen en tu billetera", "Choose which cards appear in your wallet"))
            }

            MonederoCard(store: monederoStore,
                         onRecargar: { showRecargarSaldo = true },
                         onMostrarQR: { showQRPasaje = true },
                         tinta: tintaCabecera,
                         empresa: empresa)
                .padding(6)
                .background {
                    LinearGradient(colors: coloresCabecera, startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            if mostrarCarnetFoto || mostrarCarnetDigital {
                (apilarContenido ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                                  : AnyLayout(HStackLayout(alignment: .top, spacing: 12))) {
                    if mostrarCarnetFoto {
                        tarjetaBilletera(icono: CarnetPerfil.foto.icono,
                                        titulo: CarnetPerfil.foto.tituloBreve(para: empresa),
                                        detalle: hayCarnetGuardado
                                            ? L.t("Ver foto", "View photo")
                                            : L.t("Añadir foto", "Add photo")) {
                            empresaDelCarnet = empresa
                            showCarnetScanner = true
                        }
                    }
                    if mostrarCarnetDigital {
                        tarjetaBilletera(icono: CarnetPerfil.digital.icono,
                                        titulo: CarnetPerfil.digital.tituloBreve(para: empresa),
                                        detalle: L.t("Muestra · sin validez", "Sample · not valid")) {
                            empresaDelCarnet = empresa
                            showCarneDigital = true
                        }
                    }
                }
            }

            grupoFilas {
                chevronRow(icon: "creditcard.fill", iconColor: .appPrimary,
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

    private func tarjetaBilletera(icono: String, titulo: String, detalle: String,
                                  accion: @escaping () -> Void) -> some View {
        Button {
            AppHaptics.impact(.light)
            accion()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    iconoFila(icono, color: .appPrimary)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.onSurfaceVariant)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(titulo).font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.onSurface)
                    Text(detalle).font(.caption)
                        .foregroundStyle(Color.onSurfaceVariant)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.outlineVariant.opacity(0.18), lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(titulo)
        .accessibilityValue(detalle)
    }

    // MARK: - Ajustes
    private var configuracion: some View {
        VStack(alignment: .leading, spacing: 24) {
            if TransporteApp.busesUTPDisponibles { ModoBusesUTPSection() }

            VStack(alignment: .leading, spacing: 12) {
                tituloSeccion(L.t("Preferencias", "Preferences"))
                grupoFilas {
                    chevronRow(icon: "globe", iconColor: .appPrimary,
                               label: L.t("Idioma", "Language"),
                               detalle: IdiomaManager.shared.idioma.nombreNativo) {
                        mostrarIdiomas = true
                    }
                    separadorFila
                    TimelineView(.periodic(from: .now, by: 60)) { contexto in
                        chevronRow(icon: "bell.fill", iconColor: .appPrimary,
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
                    chevronRow(icon: "person.crop.circle", iconColor: .appPrimary,
                               label: L.t("Datos personales", "Personal details")) {
                        AppHaptics.impact(.light)
                        showDatosPersonales = true
                    }
                    separadorFila
                    chevronRow(icon: "archivebox", iconColor: .appPrimary,
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
                .tint(.appPrimary)
            }
        }
    }

    private func accesibilidadRow() -> some View {
        chevronRow(icon: voiceOverOn ? "speaker.wave.3.fill" : "speaker.slash.fill",
                   iconColor: .appPrimary, label: L.t("VoiceOver", "VoiceOver"),
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
            .font(.title3.weight(.bold))
            .foregroundStyle(Color.onSurface)
            .accessibilityAddTraits(.isHeader)
    }

    private func grupoFilas<Contenido: View>(@ViewBuilder contenido: () -> Contenido) -> some View {
        VStack(spacing: 0, content: contenido)
            .background(Color.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.outlineVariant.opacity(0.18), lineWidth: 0.5)
            }
    }

    private var separadorFila: some View {
        Divider().padding(.leading, 68).accessibilityHidden(true)
    }

    private func iconoFila(_ icono: String, color: Color) -> some View {
        Image(systemName: icono)
            .font(.body.weight(.semibold))
            .foregroundStyle(color == .appPrimary ? Color.onPrimaryContainer : color)
            .frame(width: 38, height: 38)
            .background(color == .appPrimary ? Color.primaryContainer : color.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)
    }

    private func toggleRow(icon: String, iconColor: Color, label: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            iconoFila(icon, color: iconColor)
            Toggle(isOn: isOn) {
                Text(label)
                    .font(.bodyMdMedium)
                    .foregroundStyle(Color.onSurface)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .tint(.appPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func chevronRow(icon: String, iconColor: Color, label: String,
                            detalle: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                iconoFila(icon, color: iconColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text(label).font(.bodyMdMedium).foregroundStyle(Color.onSurface)
                    if let detalle {
                        Text(detalle).font(.caption).foregroundStyle(Color.onSurfaceVariant)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.onSurfaceVariant)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
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
