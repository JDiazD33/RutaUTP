//
//  PerfilView.swift
//  RutaUTP
//
//  Pantalla de perfil: hero gradient con billetera, configuración con toggles.
//

import SwiftUI
import UIKit

struct PerfilView: View {
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
    @AppStorage(PreferenciasApp.notificaciones) private var notifOn: Bool = true
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
        empresa == .inkafarma ? Color(light: "#EAD983", dark: "#456534") : .inversePrimary
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.appBackground.ignoresSafeArea()

            ZStack(alignment: .bottom) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        hero

                        PerfilCuponesGuardados()
                            .padding(.top, 24)

                        configuracion
                            .padding(.horizontal, 20)
                            .padding(.top, 24)
                        Spacer(minLength: 140)
                    }
                }
                .padding(.bottom, 64)

                BottomNavBar()
            }

        }
        .ignoresSafeArea(edges: .bottom)
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
            Text(ubicacionPopupSubtitulo)
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
    }

    // MARK: - Banner Sin Conexión (Top)
    // MARK: - Hero
    private var hero: some View {
        ZStack(alignment: .topLeading) {
            Circle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 220, height: 220)
                .offset(x: 230, y: -70)
                .accessibilityHidden(true)
            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 150, height: 150)
                .offset(x: -50, y: 50)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 56)

                // Avatar + Nombre + Rol
                (apilarContenido ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
                                  : AnyLayout(HStackLayout(alignment: .center, spacing: 14))) {
                    ZStack {
                        Circle()
                            .fill(fondoAvatar)
                            .frame(width: avatarSize, height: avatarSize)
                            .overlay(Circle().stroke(Color.white, lineWidth: 3))
                        if let fotoPerfil {
                            Image(uiImage: fotoPerfil)
                                .resizable()
                                .scaledToFill()
                                .frame(width: avatarSize, height: avatarSize)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white, lineWidth: 3))
                                .accessibilityHidden(true)
                        } else {
                            Text(iniciales(nombre))
                                .font(.headlineMd)
                                .foregroundStyle(tintaCabecera)
                        }
                    }
                    .accessibilityLabel(L.t("Foto de perfil, ", "Profile photo, ") + iniciales(nombre))
                    .accessibilityAddTraits(.isImage)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(nombre)
                            .font(.headlineLgMobile)
                            .foregroundStyle(tintaCabecera)
                        (apilarContenido ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                                          : AnyLayout(HStackLayout(spacing: 6))) {
                            Text(rolPerfil)
                                .font(.labelCapsSm)
                                .foregroundStyle(tintaCabecera.opacity(0.95))
                                .appTracking(AppTracking.wideLabel)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.white.opacity(0.20)))
                            if mostrarCarnetFoto, hayCarnetGuardado {
                                HStack(spacing: 3) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 10, weight: .bold))
                                        .accessibilityHidden(true)
                                    Text(L.t("CARNÉ GUARDADO", "CARD SAVED"))
                                        .font(.labelCapsSm)
                                        .appTracking(AppTracking.wideLabel)
                                }
                                .foregroundStyle(.onTertiary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.tertiary))
                            }
                        }
                    }
                    if !apilarContenido { Spacer() }
                }
                .padding(.horizontal, 20)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(nombre + ", " + rolPerfil
                                + (mostrarCarnetFoto && hayCarnetGuardado ? L.t(", carné guardado", ", card saved") : ""))
                .accessibilityAddTraits(.isHeader)

                // Mi Wallet integrado debajo del nombre
                VStack(alignment: .leading, spacing: 10) {
                    Text(L.t("MI BILLETERA", "MY WALLET"))
                        .font(.labelCapsSm)
                        .foregroundStyle(tintaCabecera.opacity(0.85))
                        .appTracking(AppTracking.wideLabel)
                        .padding(.horizontal, 4)
                        .accessibilityAddTraits(.isHeader)

                    // Monedero a lo ancho: es el contenido real de la
                    // billetera, y así sus dos botones no se recortan.
                    MonederoCard(store: monederoStore,
                                 onRecargar: { showRecargarSaldo = true },
                                 onMostrarQR: { showQRPasaje = true },
                                 tinta: tintaCabecera,
                                 empresa: empresa)

                    if mostrarCarnetFoto || mostrarCarnetDigital {
                        (apilarContenido ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                                          : AnyLayout(HStackLayout(alignment: .top, spacing: 12))) {
                            if mostrarCarnetFoto {
                                tarjetaBilletera(icono: CarnetPerfil.foto.icono,
                                                titulo: CarnetPerfil.foto.titulo(para: empresa),
                                                detalle: hayCarnetGuardado
                                                    ? L.t("Ver foto guardada", "View saved photo")
                                                    : L.t("Añadir foto", "Add photo"),
                                                conChevron: false) {
                                    empresaDelCarnet = empresa
                                    showCarnetScanner = true
                                }
                            }

                            if mostrarCarnetDigital {
                                tarjetaBilletera(icono: CarnetPerfil.digital.icono,
                                                titulo: CarnetPerfil.digital.titulo(para: empresa),
                                                detalle: L.t("Muestra · sin validez",
                                                             "Sample · not valid"),
                                                conChevron: true) {
                                    empresaDelCarnet = empresa
                                    showCarneDigital = true
                                }
                            }
                        }
                    }

                    // Organizador local de referencias de tarjetas, sin pagos.
                    Button {
                        AppHaptics.impact(.light)
                        showTarjetaSheet = true
                    } label: {
                        (apilarContenido ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                                          : AnyLayout(HStackLayout(spacing: 10))) {
                            Image(systemName: "creditcard.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(tintaCabecera.opacity(0.85))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L.t("Mis tarjetas", "My cards"))
                                    .font(.footnote.bold())
                                    .foregroundStyle(tintaCabecera)
                                Text(L.t("Referencias locales · sin pagos",
                                         "Local references · no payments"))
                                    .font(.caption2)
                                    .foregroundStyle(tintaCabecera.opacity(0.75))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if !apilarContenido { Spacer() }
                            Text(L.t("LOCAL", "LOCAL"))
                                .font(.labelCapsSm)
                                .foregroundStyle(tintaCabecera)
                                .appTracking(AppTracking.wideLabel)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(.white.opacity(0.22)))
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.10)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(.white.opacity(0.22),
                                              style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L.t("Mis tarjetas, referencias locales", "My cards, local references"))
                    .accessibilityHint(L.t("Organiza referencias guardadas en este dispositivo. No permite pagar",
                                           "Organize references saved on this device. Payments are not supported"))
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)

                Spacer(minLength: 24)
            }
        }
        .frame(minHeight: mostrarCarnetFoto || mostrarCarnetDigital ? 470 : 360)
        .background {
            LinearGradient(
                colors: coloresCabecera,
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    /// Tarjeta translúcida de la billetera (carnet y carné digital).
    ///
    /// Estaba copiada dos veces, con el mismo fondo, el mismo borde y el mismo
    /// gesto; solo cambiaban el icono y los textos.
    private func tarjetaBilletera(icono: String,
                                  titulo: String,
                                  detalle: String,
                                  conChevron: Bool,
                                  accion: @escaping () -> Void) -> some View {
        Button {
            AppHaptics.impact(.light)
            accion()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icono)
                    .font(.system(size: 18))
                    .foregroundStyle(tintaCabecera)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(titulo)
                        .font(.footnote.bold())
                        .foregroundStyle(tintaCabecera)
                    Text(detalle)
                        .font(.caption2)
                        .foregroundStyle(tintaCabecera.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if conChevron {
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(tintaCabecera.opacity(0.7))
                        .accessibilityHidden(true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.18)))
            .overlay(
                RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(titulo)
        .accessibilityValue(detalle)
    }

    // MARK: - Configuración
    private var configuracion: some View {
        VStack(alignment: .leading, spacing: 12) {
            PerfilPreferenciasVisuales(empresa: empresa)
                .padding(.bottom, 12)
            if TransporteApp.busesUTPDisponibles {
                ModoBusesUTPSection()
                    .padding(.bottom, 12)
            }

            Text(L.t("Preferencias", "Preferences"))
                .font(.labelCapsLg)
                .foregroundStyle(.onSurfaceVariant)
                .appTracking(AppTracking.wideLabel)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                toggleRow(icon: "bell.fill", iconColor: .appPrimary,
                          label: L.t("Preferencia de notificaciones", "Notification preference"), isOn: $notifOn)
                Divider().padding(.leading, 56).accessibilityHidden(true)
                toggleRow(icon: "mappin.circle.fill", iconColor: .secondary,
                          label: L.t("Preferencia de compartir ubicación", "Location sharing preference"), isOn: $ubicacionOn)
                Divider().padding(.leading, 56).accessibilityHidden(true)
                offlineToggleRow
                Divider().padding(.leading, 56).accessibilityHidden(true)
                toggleRow(icon: "hand.raised.fill", iconColor: .tertiary,
                          label: L.signable("perfil.modo_senias", "Modo Señas", "Sign Language Mode"), isOn: $modoSenias)
            .seniable("perfil.modo_senias", conGesto: false)
                Divider().padding(.leading, 56).accessibilityHidden(true)
                chevronRow(icon: "pencil", iconColor: .onSurfaceVariant,
                           label: L.t("Editar perfil", "Edit profile")) {
                    AppHaptics.impact(.light)
                    showDatosPersonales = true
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.surfaceContainerLowest)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.outlineVariant.opacity(0.20), lineWidth: 0.5)
                    )
            )

            Text(L.t("Las preferencias de notificaciones y de compartir ubicación se guardan solo en este dispositivo. Esta versión no envía alertas ni comparte tu ubicación con otros usuarios. No cambian los permisos de iOS ni desactivan el GPS del mapa.",
                     "Notification and location sharing preferences are saved only on this device. This version does not send alerts or share your location with other users. They do not change iOS permissions or turn off map GPS."))
                .font(.bodySm)
                .foregroundStyle(.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)

            // ── Accesibilidad (VoiceOver) ──
            VStack(alignment: .leading, spacing: 12) {
                Text(L.t("Accesibilidad", "Accessibility"))
                    .font(.labelCapsLg)
                    .foregroundStyle(.onSurfaceVariant)
                    .appTracking(AppTracking.wideLabel)
                    .padding(.leading, 4)
                    .accessibilityAddTraits(.isHeader)

                VStack(spacing: 0) {
                    accesibilidadRow()
                }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.surfaceContainerLowest)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.outlineVariant.opacity(0.20), lineWidth: 0.5)
                        )
                )
            }
        }
    }

    // MARK: - Fila Accesibilidad (VoiceOver)
    @ViewBuilder
    private func accesibilidadRow() -> some View {
        Button {
            AppHaptics.impact(.light)
            showVoiceOverHelp = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.appPrimary.opacity(0.14))
                        .frame(width: 36, height: 36)
                    Image(systemName: voiceOverOn ? "speaker.wave.3.fill" : "speaker.slash.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.appPrimary)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L.t("VoiceOver", "VoiceOver"))
                        .font(.bodyMdMedium)
                        .foregroundStyle(.onSurface)
                    Text(voiceOverOn ? L.t("Activado", "On") : L.t("Desactivado", "Off"))
                        .font(.bodySm)
                        .foregroundStyle(.onSurfaceVariant)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.onSurfaceVariant)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("VoiceOver")
        .accessibilityValue(voiceOverOn ? L.t("Activado", "On") : L.t("Desactivado", "Off"))
        .accessibilityHint(L.t("Muestra instrucciones de activación y gestos de navegación", "Shows activation instructions and navigation gestures"))
    }

    private func toggleRow(icon: String, iconColor: Color, label: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(iconColor.opacity(0.14)).frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(iconColor)
            }
            .accessibilityHidden(true)
            Toggle(isOn: isOn) {
                Text(label)
                    .font(.bodyMdMedium)
                    .foregroundStyle(.onSurface)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .tint(.appPrimary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)

    }

    // MARK: - Disponibilidad sin conexión
    private var offlineToggleRow: some View {
        Button {
            AppHaptics.impact(.light)
            showOfflineMapPopup = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.orange)
                    .frame(width: 36, height: 36)
                    .background(Color.orange.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.t("Modo offline", "Offline mode"))
                        .font(.bodyMdMedium)
                        .foregroundStyle(.onSurface)
                    Text(L.t("Consulta qué puedes usar sin internet", "See what works without internet"))
                        .font(.bodySm)
                        .foregroundStyle(.onSurfaceVariant)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Color.onSurfaceVariant)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func chevronRow(icon: String, iconColor: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(iconColor.opacity(0.14)).frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(iconColor)
                }
                .accessibilityHidden(true)
                Text(label)
                    .font(.bodyMdMedium)
                    .foregroundStyle(.onSurface)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.onSurfaceVariant)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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
