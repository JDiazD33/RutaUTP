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
    @State private var carnetGuardado: Bool = false
    @StateObject private var tarjetasStore = TarjetasStore()
    /// Monedero de pasajes: el contenido real de la billetera.
    @StateObject private var monederoStore = MonederoStore()
    /// Misma foto que en el drawer: ProfileImageStore es la fuente única.
    @State private var fotoPerfil: UIImage? = nil

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
            fotoPerfil = ProfileImageStore.load()
            carnetGuardado = CarnetImageStore.load() != nil
            // Solo DEBUG: abre directo el Carné Digital, p.ej.
            // xcrun simctl launch ... apolito.RutaUTP --pantalla perfil --carne
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--carne") { showCarneDigital = true }
            // Monedero: permite mirar sus hojas sin navegar hasta ellas.
            if ProcessInfo.processInfo.arguments.contains("--qr") { showQRPasaje = true }
            if ProcessInfo.processInfo.arguments.contains("--recargar") { showRecargarSaldo = true }
            #endif
        }
        .onChange(of: showDatosPersonales) { _, abierto in
            if !abierto { fotoPerfil = ProfileImageStore.load() }
        }
        // La foto puede cambiar dentro del Carné Digital: recargar al cerrar.
        .onChange(of: showCarneDigital) { _, abierto in
            if !abierto { fotoPerfil = ProfileImageStore.load() }
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
            CarneDigitalView(nombre: nombre)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .seguirTemaForzado()
        }
        // Scanner de Carnet
        .fullScreenCover(isPresented: $showCarnetScanner) {
            CarnetScannerView {
                carnetGuardado = true
            }
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
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
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
                HStack(alignment: .center, spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.inversePrimary)
                            .frame(width: 72, height: 72)
                            .overlay(Circle().stroke(Color.white, lineWidth: 3))
                        if let fotoPerfil {
                            Image(uiImage: fotoPerfil)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 72, height: 72)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white, lineWidth: 3))
                                .accessibilityHidden(true)
                        } else {
                            Text(iniciales(nombre))
                                .font(.headlineMd)
                                .foregroundStyle(.white)
                        }
                    }
                    .accessibilityLabel(L.t("Foto de perfil, ", "Profile photo, ") + iniciales(nombre))
                    .accessibilityAddTraits(.isImage)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(nombre)
                            .font(.headlineLgMobile)
                            .foregroundStyle(.white)
                        HStack(spacing: 6) {
                            Text(L.t("ESTUDIANTE UTP", "UTP STUDENT"))
                                .font(.labelCapsSm)
                                .foregroundStyle(.white.opacity(0.95))
                                .appTracking(AppTracking.wideLabel)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.white.opacity(0.20)))
                            if carnetGuardado {
                                HStack(spacing: 3) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 10, weight: .bold))
                                        .accessibilityHidden(true)
                                    Text(L.t("CARNÉ GUARDADO", "CARD SAVED"))
                                        .font(.labelCapsSm)
                                        .appTracking(AppTracking.wideLabel)
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.tertiary))
                            }
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(nombre + L.t(", estudiante UTP", ", UTP student")
                                + (carnetGuardado ? L.t(", carné guardado", ", card saved") : ""))
                .accessibilityAddTraits(.isHeader)

                // Mi Wallet integrado debajo del nombre
                VStack(alignment: .leading, spacing: 10) {
                    Text(L.t("MI BILLETERA", "MY WALLET"))
                        .font(.labelCapsSm)
                        .foregroundStyle(.white.opacity(0.85))
                        .appTracking(AppTracking.wideLabel)
                        .padding(.horizontal, 4)
                        .accessibilityAddTraits(.isHeader)

                    // Monedero a lo ancho: es el contenido real de la
                    // billetera, y así sus dos botones no se recortan.
                    MonederoCard(store: monederoStore,
                                 onRecargar: { showRecargarSaldo = true },
                                 onMostrarQR: { showQRPasaje = true })

                    HStack(alignment: .top, spacing: 12) {
                        // Carnet UTP: la foto del carné físico.
                        tarjetaBilletera(icono: "person.text.rectangle.fill",
                                         titulo: L.t("Carnet Universitario", "University Card"),
                                         detalle: carnetGuardado
                                             ? L.t("Ver foto guardada", "View saved photo")
                                             : L.t("Añadir foto", "Add photo"),
                                         conChevron: false) {
                            showCarnetScanner = true
                        }

                        // Carné Digital de muestra: no es una credencial validada.
                        tarjetaBilletera(icono: "person.crop.rectangle.fill",
                                         titulo: L.t("Carné Digital", "Digital ID"),
                                         detalle: L.t("Muestra · sin validez",
                                                      "Sample · not valid"),
                                         conChevron: true) {
                            showCarneDigital = true
                        }
                    }

                    // Organizador local de referencias de tarjetas, sin pagos.
                    Button {
                        AppHaptics.impact(.light)
                        showTarjetaSheet = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "creditcard.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white.opacity(0.85))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L.t("Mis tarjetas", "My cards"))
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                                Text(L.t("Referencias locales · sin pagos",
                                         "Local references · no payments"))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.75))
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(L.t("LOCAL", "LOCAL"))
                                .font(.labelCapsSm)
                                .foregroundStyle(.white)
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
        .frame(minHeight: 470)
        .background {
            LinearGradient(
                colors: [Color.appPrimary, Color.primaryContainer, Color.tertiary],
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
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(titulo)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    Text(detalle)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                if conChevron {
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
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
                toggleRow(icon: "hand.raised.fill", iconColor: .purple,
                          label: L.signable("perfil.modo_senias", "Modo Señas", "Sign Language Mode"), isOn: $modoSenias)
                    .seniable("perfil.modo_senias")
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
        let voiceOverOn = UIAccessibility.isVoiceOverRunning
        Button {
            AppHaptics.impact(.light)
            if voiceOverOn {
                // Ya está activo: abrir ajustes de la app (por si quiere ajustar algo)
                abrirAjustesIOS()
            } else {
                // Mostrar instrucciones + botón a Ajustes
                showVoiceOverHelp = true
            }
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
        .accessibilityLabel("VoiceOver")
        .accessibilityValue(voiceOverOn ? L.t("Activado", "On") : L.t("Desactivado", "Off"))
        .accessibilityHint(L.t("Doble toque para ver cómo activar VoiceOver en tu iPhone", "Double tap to see how to enable VoiceOver on your iPhone"))
    }

    private func abrirAjustesIOS() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
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

// MARK: - Sheet de ayuda para activar VoiceOver
private struct VoiceOverHelpSheet: View {
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

#Preview {
    PerfilView().environmentObject(AppRouter())
}



// MARK: - Cupones de los negocios del Tracking Demo

private struct PerfilCuponesGuardados: View {
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
                            .foregroundStyle(.white)
                            .background(Color.appPrimary, in: Capsule())
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
