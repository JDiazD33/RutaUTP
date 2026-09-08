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

    @State private var nombre: String = "Joaquín Díaz"
    @State private var notifOn: Bool = true
    @State private var ubicacionOn: Bool = true
    @State private var modoOffline: Bool = false
    /// Modo Señas. Se lee desde varias pantallas, por eso va en AppStorage
    /// y no en @State: cualquier vista reacciona al cambio al instante.
    @AppStorage(SeniasService.llaveModo) private var modoSenias: Bool = false
    @State private var showOfflineMapPopup: Bool = false
    @State private var mapsDownloaded: Bool = false
    @State private var offlineIconBounce: Bool = false
    @State private var bannerVisible: Bool = true
    @State private var bannerPulse: Bool = false
    @State private var showUbicacionPopup: Bool = false
    @State private var ubicacionPopupMensaje: String = ""
    @State private var ubicacionPopupSubtitulo: String = ""
    @State private var showEditAlert: Bool = false
    @State private var newNameInput: String = ""
    @State private var showDatosPersonales: Bool = false
    @State private var showVoiceOverHelp: Bool = false
    //  CORREGIDO V3: estado para Wallet
    @State private var showTarjetaSheet: Bool = false
    @State private var showCarneDigital: Bool = false
    @State private var showCarnetScanner: Bool = false
    @State private var carnetVerificado: Bool = false
    @State private var metodoPagoGuardado: String? = nil
    /// Misma foto que en el drawer: ProfileImageStore es la fuente única.
    @State private var fotoPerfil: UIImage? = nil

    var body: some View {
        ZStack(alignment: .top) {
            Color.appBackground.ignoresSafeArea()

            ZStack(alignment: .bottom) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        hero

                        configuracion
                            .padding(.horizontal, 20)
                            .padding(.top, 24)
                        Spacer(minLength: 140)
                    }
                }
                .padding(.bottom, 64)

                BottomNavBar()
            }

            // ── BANNER "SIN CONEXIÓN" (Top Banner en Modo Offline) ──
            if modoOffline && bannerVisible {
                offlineTopBanner
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .modifier(
                                active: SalidaBanner(activo: true),
                                identity: SalidaBanner(activo: false)
                            )
                        )
                    )
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .animation(.easeInOut(duration: 0.28), value: modoOffline)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: mapsDownloaded)
        .onChange(of: modoOffline) { activo in
            if activo {
                AppHaptics.success()
                showOfflineMapPopup = true
                bannerVisible = true
                if mapsDownloaded { programarSalidaBanner() }
            } else {
                AppHaptics.impact(.light)
                bannerVisible = true
            }
            // Rebote del icono de la fila al cambiar el modo
            withAnimation(.spring(response: 0.28, dampingFraction: 0.5)) { offlineIconBounce = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) { offlineIconBounce = false }
            }
        }
        .onChange(of: mapsDownloaded) { listo in
            // Tras descargar: el banner pasa al color de marca unos segundos y se despide con animación
            if listo { programarSalidaBanner() }
        }
        // Foto de perfil: recargar al entrar y al volver de Datos Personales.
        .onAppear {
            fotoPerfil = ProfileImageStore.load()
            // Solo DEBUG: abre directo el Carné Digital, p.ej.
            // xcrun simctl launch ... apolito.RutaUTP --pantalla perfil --carne
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--carne") { showCarneDigital = true }
            #endif
        }
        .onChange(of: showDatosPersonales) { abierto in
            if !abierto { fotoPerfil = ProfileImageStore.load() }
        }
        // La foto puede cambiar dentro del Carné Digital: recargar al cerrar.
        .onChange(of: showCarneDigital) { abierto in
            if !abierto { fotoPerfil = ProfileImageStore.load() }
        }
        .onChange(of: ubicacionOn) { activo in
            if activo {
                ubicacionPopupMensaje = "Ubicación compartida"
                ubicacionPopupSubtitulo = "Tu ubicación en tiempo real se compartirá para el seguimiento de rutas UTP."
            } else {
                ubicacionPopupMensaje = "Sin ubicación compartida"
                ubicacionPopupSubtitulo = "Tu ubicación en tiempo real no se compartirá con otros usuarios."
            }
            showUbicacionPopup = true
        }
        .alert(ubicacionPopupMensaje, isPresented: $showUbicacionPopup) {
            Button("Entendido", role: .cancel) { }
        } message: {
            Text(ubicacionPopupSubtitulo)
        }
        .alert("Editar nombre", isPresented: $showEditAlert) {
            TextField("Nombre completo", text: $newNameInput)
            Button("Guardar") {
                if !newNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    nombre = newNameInput
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(L.t("Ingresa tu nuevo nombre para actualizar tu perfil.", "Enter your new name to update your profile."))
        }
        // Sheet de Tarjeta
        .sheet(isPresented: $showTarjetaSheet) {
            TarjetaFormSheet { numero in
                let ultimos4 = numero.filter { $0.isNumber }.suffix(4)
                metodoPagoGuardado = String(ultimos4)
            }
            .presentationDetents([.large])
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
                carnetVerificado = true
            }
        }
        // Sheet de Datos Personales (reutilizado del SideDrawer)
        .sheet(isPresented: $showDatosPersonales) {
            DatosPersonalesSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        // Sheet Modal de Descarga de Mapas Offline (se abre a pantalla completa)
        .sheet(isPresented: $showOfflineMapPopup) {
            OfflineMapSheet(mapsDownloaded: $mapsDownloaded)
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
    private var offlineTopBanner: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: 40, height: 40)
                Image(systemName: mapsDownloaded ? "checkmark.seal.fill" : "wifi.slash")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(mapsDownloaded ? "MAPAS LISTOS" : "SIN CONEXIÓN")
                        .font(.labelCapsSm)
                        .appTracking(AppTracking.wideLabel)
                    if !mapsDownloaded {
                        Text("• Modo Offline")
                            .font(.bodySm)
                            .foregroundStyle(.white.opacity(0.90))
                    }
                }
                Text(mapsDownloaded ? "Navegación sin conexión disponible" : "Operando con datos almacenados")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.90))
            }
            Spacer()

            if !mapsDownloaded {
                Button {
                    AppHaptics.impact(.light)
                    showOfflineMapPopup = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .accessibilityHidden(true)
                        Text("Descargar")
                            .font(.system(size: 12, weight: .heavy))
                    }
                    .foregroundStyle(Color.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.white))
                    .shadow(color: Color.black.opacity(0.14), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .scaleEffect(bannerPulse ? 1.07 : 1.0)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: bannerPulse)
                .accessibilityLabel("Descargar mapas offline")
                .accessibilityHint("Doble toque para administrar los mapas locales")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: mapsDownloaded
                            ? [Color.appPrimary, Color.primaryContainer]
                            : [Color.orange, Color(red: 0.80, green: 0.35, blue: 0.02)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .shadow(
                    color: (mapsDownloaded ? Color.appPrimary : Color.orange).opacity(0.45),
                    radius: 14, x: 0, y: 8
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 50)
        .onAppear { bannerPulse = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(mapsDownloaded ? "Mapas offline descargados correctamente" : "Aviso: sin conexión, modo offline activo")
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// Después de descargar, deja ver el estado de éxito del banner y lo desvanece hacia arriba.
    private func programarSalidaBanner() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.78)) {
                bannerVisible = false
            }
        }
    }

    // MARK: - Hero
    private var hero: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color.appPrimary, Color.primaryContainer, Color.tertiary],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .frame(height: 420)
            .accessibilityHidden(true)

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
                    .accessibilityLabel("Foto de perfil, \(iniciales(nombre))")
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
                            if carnetVerificado {
                                HStack(spacing: 3) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 10, weight: .bold))
                                        .accessibilityHidden(true)
                                    Text(L.t("VERIFICADO", "VERIFIED"))
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
                .accessibilityLabel("\(nombre), estudiante UTP\(carnetVerificado ? ", carnet verificado" : "")")
                .accessibilityAddTraits(.isHeader)

                // Mi Wallet integrado debajo del nombre
                VStack(alignment: .leading, spacing: 10) {
                    Text(L.t("MI BILLETERA", "MY WALLET"))
                        .font(.labelCapsSm)
                        .foregroundStyle(.white.opacity(0.85))
                        .appTracking(AppTracking.wideLabel)
                        .padding(.horizontal, 4)
                        .accessibilityAddTraits(.isHeader)

                    HStack(spacing: 12) {
                        // Tarjeta de pago translúcida
                        Button {
                            AppHaptics.impact(.light)
                            showTarjetaSheet = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "creditcard.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.white)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L.t("Método Pago", "Payment"))
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(.white)
                                    Text(metodoPagoGuardado.map { "Visa •••• \($0)" } ?? L.t("Agregar tarjeta", "Add card"))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.white.opacity(0.8))
                                        .lineLimit(1)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.18)))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.white.opacity(0.25), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Método de pago")
                        .accessibilityValue(metodoPagoGuardado.map { "Visa terminación \($0)" } ?? "Sin tarjeta, agregar")
                        .accessibilityHint("Doble toque para administrar tu tarjeta")

                        // Carnet UTP translúcido
                        Button {
                            AppHaptics.impact(.light)
                            showCarnetScanner = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "person.text.rectangle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.white)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L.t("Carnet UTP", "UTP Card"))
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(.white)
                                    Text(carnetVerificado ? "Verificado" : L.t("Escanear ahora", "Scan now"))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.white.opacity(0.8))
                                        .lineLimit(1)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.18)))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.white.opacity(0.25), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // Carné Digital: debajo del método de pago
                    Button {
                        AppHaptics.impact(.light)
                        showCarneDigital = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "person.crop.rectangle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L.t("Carné Digital", "Digital ID"))
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                                Text(L.t("Tu identificación para ingresar al campus", "Your ID to enter the campus"))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.8))
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white.opacity(0.7))
                                .accessibilityHidden(true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.18)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.white.opacity(0.25), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L.t("Carné Digital", "Digital ID"))
                    .accessibilityHint(L.t("Doble toque para mostrar tu identificación con código de barras", "Double tap to show your ID with barcode"))
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)

                Spacer()
            }
        }
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
                          label: L.t("Notificaciones", "Notifications"), isOn: $notifOn)
                Divider().padding(.leading, 56).accessibilityHidden(true)
                toggleRow(icon: "mappin.circle.fill", iconColor: .secondary,
                          label: L.t("Compartir ubicación", "Share location"), isOn: $ubicacionOn)
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
                    Text(voiceOverOn ? "Activado" : "Desactivado")
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
        .accessibilityValue(voiceOverOn ? "Activado" : "Desactivado")
        .accessibilityHint("Doble toque para ver cómo activar VoiceOver en tu iPhone")
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
            Text(label)
                .font(.bodyMdMedium)
                .foregroundStyle(.onSurface)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(.appPrimary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(isOn.wrappedValue ? "Activado" : "Desactivado")
        .accessibilityHint("Doble toque para cambiar")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Fila Modo Offline (icono animado + subtítulo según estado)
    private var offlineToggleRow: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(modoOffline ? Color.orange : Color.orange.opacity(0.14))
                    .frame(width: 36, height: 36)
                Image(systemName: "wifi.slash")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(modoOffline ? Color.white : Color.orange)
            }
            .scaleEffect(offlineIconBounce ? 1.2 : 1.0)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(L.t("Modo offline", "Offline mode"))
                    .font(.bodyMdMedium)
                    .foregroundStyle(.onSurface)
                Text(subtituloOffline)
                    .font(.bodySm)
                    .foregroundStyle(.onSurfaceVariant)
            }
            Spacer()
            Toggle("", isOn: $modoOffline)
                .labelsHidden()
                .tint(Color.orange)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L.t("Modo offline", "Offline mode"))
        .accessibilityValue(modoOffline ? "Activado" : "Desactivado")
        .accessibilityHint("Doble toque para cambiar")
        .accessibilityAddTraits(.isButton)
    }

    private var subtituloOffline: String {
        if !modoOffline {
            return L.t("Descarga mapas para navegar sin señal", "Download maps to navigate without signal")
        }
        return mapsDownloaded
            ? L.t("Activo • Mapas de Trujillo listos", "Active • Trujillo maps ready")
            : L.t("Activo • Descarga los mapas locales", "Active • Download local maps")
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
        .accessibilityHint("Doble toque para abrir")
    }

    // MARK: - Helpers
    private func iniciales(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first }.map { String($0) }.joined()
    }
}

// MARK: - Transición de salida del banner offline
// Al irse, el banner se eleva, se encoge y se disuelve con un desenfoque suave.
private struct SalidaBanner: ViewModifier {
    var activo: Bool

    func body(content: Content) -> some View {
        content
            .offset(y: activo ? -70 : 0)
            .scaleEffect(activo ? 0.85 : 1.0, anchor: .top)
            .opacity(activo ? 0 : 1)
            .blur(radius: activo ? 5 : 0)
    }
}

// MARK: - Sheet Modal de Descarga de Mapas Offline
private struct OfflineMapSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var mapsDownloaded: Bool

    private enum Fase { case reposo, descargando, listo }

    @State private var fase: Fase = .reposo
    @State private var progress: Double = 0.0
    @State private var pulso: Bool = false
    @State private var tarea: Task<Void, Never>? = nil

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)

            headerIcono
                .padding(.top, 20)

            VStack(spacing: 6) {
                Text(titulo)
                    .font(.headlineLgMobile)
                    .foregroundStyle(.onSurface)
                    .multilineTextAlignment(.center)
                Text(subtitulo)
                    .font(.bodySm)
                    .foregroundStyle(.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .padding(.top, 14)

            VStack(spacing: 10) {
                mapPackageRow(
                    icon: "graduationcap.fill",
                    title: L.t("Campus UTP Trujillo", "UTP Trujillo Campus"),
                    detail: L.t("Edificios, pabellones y paraderos • 12 MB", "Buildings, halls and stops • 12 MB")
                )
                mapPackageRow(
                    icon: "bus.fill",
                    title: L.t("Rutas de Transporte Urbano", "Urban Transport Routes"),
                    detail: L.t("Líneas 10, 4 y paraderos cercanos • 28 MB", "Lines 10, 4 and nearby stops • 28 MB")
                )
            }
            .padding(.top, 18)

            if fase == .descargando {
                seccionProgreso
                    .padding(.top, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if fase == .listo {
                seccionListo
                    .padding(.top, 16)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }

            Spacer(minLength: 20)

            botonPrincipal

            if fase == .reposo {
                Button {
                    dismiss()
                } label: {
                    Text(L.t("Ahora no", "Not now"))
                        .font(.bodyMdMedium)
                        .foregroundStyle(.onSurfaceVariant)
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
                .accessibilityLabel(L.t("Cerrar sin descargar", "Close without downloading"))
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appSurface)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: fase)
        .onChange(of: fase) { nueva in
            // El pulso se activa DESPUÉS de que los anillos aparecen:
            // si se asignara en la misma transacción, la animación no correría.
            pulso = (nueva == .descargando)
        }
        .onAppear {
            if mapsDownloaded { fase = .listo }
        }
        .onDisappear { tarea?.cancel() }
    }

    // MARK: Header con icono y anillos de pulso mientras descarga
    private var headerIcono: some View {
        ZStack {
            if fase == .descargando {
                anillo(delay: 0)
                anillo(delay: 0.7)
            }
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.appPrimary, Color.primaryContainer],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 84, height: 84)
                Image(systemName: fase == .listo ? "checkmark" : "map.fill")
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .shadow(
                color: Color.appPrimary.opacity(0.35),
                radius: 14, x: 0, y: 6
            )
        }
        .frame(height: 110)
        .accessibilityHidden(true)
    }

    private func anillo(delay: TimeInterval) -> some View {
        Circle()
            .stroke(Color.appPrimary.opacity(0.4), lineWidth: 2)
            .frame(width: 84, height: 84)
            .scaleEffect(pulso ? 1.5 : 1.0)
            .opacity(pulso ? 0.0 : 0.6)
            .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false).delay(delay), value: pulso)
    }

    // MARK: Sección de progreso
    private var seccionProgreso: some View {
        let mb = Int((progress * 40).rounded())
        return VStack(spacing: 8) {
            HStack {
                Text(L.t("Descargando paquetes…", "Downloading packages…"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.onSurface)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.appPrimary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.surfaceContainerHigh)
                    Capsule()
                        .fill(LinearGradient(colors: [Color.appPrimary, Color.primaryContainer], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, geo.size.width * progress))
                        .animation(.linear(duration: 0.15), value: progress)
                }
            }
            .frame(height: 8)
            HStack {
                Text(L.t("Mapa de Trujillo", "Trujillo map"))
                Spacer()
                Text(L.t("\(mb) MB de 40 MB", "\(mb) MB of 40 MB"))
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.onSurfaceVariant)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.surfaceContainerLow)
        )
    }

    // MARK: Sección de éxito
    private var seccionListo: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(.appPrimary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(L.t("40 MB guardados en tu iPhone", "40 MB saved on your iPhone"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.onSurface)
                Text(L.t("Esta ventana se cerrará automáticamente", "This window will close automatically"))
                    .font(.system(size: 11))
                    .foregroundStyle(.onSurfaceVariant)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.appPrimary.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.appPrimary.opacity(0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: Botón principal (descargar / descargando / listo)
    private var botonPrincipal: some View {
        Button {
            switch fase {
            case .reposo: iniciarDescarga()
            case .descargando: break
            case .listo: dismiss()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: iconoBoton)
                    .accessibilityHidden(true)
                Text(textoBoton)
            }
            .font(.headlineSm)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(fondoBoton)
                    .shadow(
                        color: Color.appPrimary.opacity(0.30),
                        radius: 10, x: 0, y: 4
                    )
            )
            .opacity(fase == .descargando ? 0.75 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(fase == .descargando)
        .accessibilityLabel(textoBoton)
    }

    private var iconoBoton: String {
        switch fase {
        case .reposo: return "arrow.down.circle.fill"
        case .descargando: return "arrow.triangle.2.circlepath"
        case .listo: return "checkmark.circle.fill"
        }
    }

    private var textoBoton: String {
        switch fase {
        case .reposo: return L.t("Descargar Mapas (40 MB)", "Download Maps (40 MB)")
        case .descargando: return L.t("Descargando…", "Downloading…")
        case .listo: return L.t("¡Listo!", "Done!")
        }
    }

    private var fondoBoton: LinearGradient {
        switch fase {
        case .reposo:
            LinearGradient(colors: [Color.appPrimary, Color.primaryContainer], startPoint: .leading, endPoint: .trailing)
        case .descargando:
            LinearGradient(colors: [Color.appPrimary.opacity(0.7), Color.primaryContainer.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
        case .listo:
            LinearGradient(colors: [Color.appPrimary, Color.primaryContainer], startPoint: .leading, endPoint: .trailing)
        }
    }

    private var titulo: String {
        switch fase {
        case .reposo: return L.t("Descargar Mapas Locales", "Download Local Maps")
        case .descargando: return L.t("Descargando mapas…", "Downloading maps…")
        case .listo: return L.t("¡Mapas Listos!", "Maps Ready!")
        }
    }

    private var subtitulo: String {
        switch fase {
        case .reposo:
            return L.t(
                "Descarga los mapas del campus UTP y rutas de Trujillo para seguir navegando aun sin datos o señal.",
                "Download UTP campus and Trujillo route maps to keep navigating without data or signal."
            )
        case .descargando:
            return L.t(
                "Guardando el mapa de Trujillo en tu iPhone. No cierres esta ventana.",
                "Saving the Trujillo map to your iPhone. Don't close this window."
            )
        case .listo:
            return L.t(
                "El mapa de Trujillo y el campus UTP quedaron guardados. Podrás navegar completamente sin conexión.",
                "Trujillo and UTP campus maps are saved. You can navigate fully offline."
            )
        }
    }

    private func mapPackageRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(fase == .listo ? Color.appPrimary.opacity(0.12) : Color.surfaceContainerHigh)
                    .frame(width: 42, height: 42)
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(Color.appPrimary)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.onSurface)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.onSurfaceVariant)
            }
            Spacer()
            ZStack {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.onSurfaceVariant.opacity(0.5))
                    .opacity(fase == .listo ? 0 : 1)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.appPrimary)
                    .scaleEffect(fase == .listo ? 1.0 : 0.3)
                    .opacity(fase == .listo ? 1.0 : 0)
            }
            .accessibilityHidden(true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.surfaceContainerLow)
        )
    }

    private func iniciarDescarga() {
        guard fase == .reposo else { return }
        fase = .descargando
        progress = 0.0
        AppHaptics.impact(.light)

        tarea = Task {
            // Progreso simulado: 3.0 s
            let pasos = 60
            for _ in 0..<pasos {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard !Task.isCancelled else { return }
                progress = min(1.0, progress + 1.0 / Double(pasos))
            }

            fase = .listo
            mapsDownloaded = true
            pulso = false
            AppHaptics.success()

            // Cierre automático: la ventana desaparece a los 4 s de presionar Descargar
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }
}

// MARK: - Sheet de ayuda para activar VoiceOver
private struct VoiceOverHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let pasos: [(icon: String, texto: String)] = [
        ("gearshape.fill", L.t("Abre la app Ajustes de tu iPhone", "Open your iPhone Settings app")),
        ("hand.point.right.fill", L.t("Toca Accesibilidad", "Tap Accessibility")),
        ("speaker.wave.2.fill", L.t("Toca VoiceOver, primera opción", "Tap VoiceOver, first option")),
        ("togglepower", L.t("Activa el interruptor VoiceOver", "Turn on the VoiceOver switch"))
    ]

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
                    .accessibilityLabel("Paso \(i + 1): \(pasos[i].texto)")
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
            .accessibilityLabel("Abrir Ajustes del iPhone")
            .accessibilityHint("Doble toque para ir directamente a la configuración de la app")

            Button {
                dismiss()
            } label: {
                Text(L.t("Cerrar", "Close"))
                    .font(.bodyMdMedium)
                    .foregroundStyle(.onSurfaceVariant)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cerrar instrucciones")
        }
        .padding(20)
    }
}

#Preview {
    PerfilView().environmentObject(AppRouter())
}

