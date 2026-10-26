//
//  RootView.swift
//  RutaUTP
//
//  Navegación central. Las cinco pestañas conservan su contenido y
//  cambian de forma inmediata, sin disolver paneles sobre el mapa.
//

import SwiftUI
import UIKit

struct RootView: View {
    @StateObject private var router: AppRouter
    @EnvironmentObject private var trackingCoordinator: PassiveTrackingCoordinator
    @AppStorage(PreferenciasApp.busesUTP) private var preferenciaBusesUTP = false
    private var busesUTPActivos: Bool {
        preferenciaBusesUTP && TransporteApp.busesUTPDisponibles
    }
    /// El flujo de seguimiento conserva su modelo al salir de su pantalla.
    @StateObject private var trackingStore: ScreenModelStore<RouteTrackingViewModel>
    @AppStorage(SeniasService.llaveModo) private var modoSenias = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bottomNavBarHeight: CGFloat = 64
    private let notificaciones = NotificacionesService.shared
    @State private var avisoRecordatorio: String?
    @State private var mostrarAvisoRecordatorio = false
    @State private var tituloAviso = ""
    @State private var cambioParaMostrar: ToqueCambioRuta?
    @State private var abriendoCambio = false
    @State private var diarioParaMostrar: TipoAvisoDiario?
    @State private var mostrarMenuMapa = false
    private let mapMenu: Binding<Bool>?

    /// Servicio de ubicación compartido con el rastreo pasivo. Se recibe desde
    /// `RutaUTPApp`; el valor por defecto solo sirve para las previsualizaciones.
    private let locationService: LocationServiceProtocol

    /// Tema claro/oscuro. Se aplica SOLO con aplicarTemaEnVentanas (abajo):
    /// un único escritor de overrideUserInterfaceStyle. No volver a añadir
    /// cuando ambos canales escriben la misma propiedad de la ventana y el
    /// cambio va dentro de una animación, SwiftUI deja de re-aplicar el
    /// estilo al VOLVER a claro (el tema quedaba "pegado" en oscuro).
    @AppStorage("isDarkMode") private var isDarkMode = false

    /// Fuerza el tema a nivel de VENTANA (UIKit), en todas las ventanas de
    /// todas las escenas — incluye la ventana propia de los sheets (iOS 16+).
    /// Al ser imperativo pisa el trait collection completo en ambas
    /// direcciones (claro ↔ oscuro) sin depender de la invalidación de
    /// SwiftUI.
    private func aplicarTemaEnVentanas(_ oscuro: Bool) {
        let estilo: UIUserInterfaceStyle = oscuro ? .dark : .light
        for escena in UIApplication.shared.connectedScenes {
            guard let windowScene = escena as? UIWindowScene else { continue }
            windowScene.windows.forEach { $0.overrideUserInterfaceStyle = estilo }
        }
    }

    init(locationService: LocationServiceProtocol? = nil, router: AppRouter? = nil,
         mapMenu: Binding<Bool>? = nil) {
        self.mapMenu = mapMenu
        let compartido = locationService ?? LocationService()
        self.locationService = compartido
        _trackingStore = StateObject(wrappedValue: ScreenModelStore(
            RouteTrackingViewModel(locationService: compartido)
        ))

        // Solo DEBUG: permite abrir directo en una pantalla desde consola,
        // p.ej. xcrun simctl launch ... apolito.RutaUTP --pantalla rutas
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--pantalla"), i + 1 < args.count {
            switch args[i + 1] {
            case "mapa":     AppRouter.pantallaInicial = .mapaPrincipal
            case "rutas":    AppRouter.pantallaInicial = .rutas
            case "guardado": AppRouter.pantallaInicial = .guardado
            case "seguridad":AppRouter.pantallaInicial = .seguridad
            case "perfil":   AppRouter.pantallaInicial = .perfil
            case "tracking": AppRouter.pantallaInicial = .trackingDemo
            default:         break
            }
        }
        #endif
        _router = StateObject(wrappedValue: router ?? AppRouter())
    }

    var body: some View {
        ZStack {
            switch router.currentScreen {
            case .bienvenida:    BienvenidaView()
            case .trackingDemo:  RouteTrackingDemoView(model: trackingStore.model)
                    .id(ObjectIdentifier(trackingStore.model))
            default:            MainTabsView(locationService: locationService, busesUTPActivos: busesUTPActivos,
                                             mostrarMenuMapa: mapMenu ?? $mostrarMenuMapa)
            }
        }
        .ignoresSafeArea(edges: .bottom) // permite que BottomNavBar llegue al borde físico
        .environmentObject(router)
        .environment(\.locale, IdiomaManager.shared.idioma.locale)
        .environment(\.bottomNavBarHeight, bottomNavBarHeight)
        .onPreferenceChange(BottomNavBarHeightPreferenceKey.self) { height in
            guard height.isFinite, height > 0, abs(height - bottomNavBarHeight) > 0.5 else { return }
            bottomNavBarHeight = height
        }
        .task(id: IdiomaManager.shared.codigo) { await notificaciones.refrescar() }
        .onChange(of: SedeTrabajoStore.shared.sede?.id) { _, _ in
            Task { await notificaciones.refrescar() }
        }
        .onChange(of: notificaciones.toquePendiente, initial: true) { _, _ in abrirRecordatorioSiCorresponde() }
        .onChange(of: PushRutasService.shared.toquePendiente, initial: true) { _, _ in abrirCambioSiCorresponde() }
        .onChange(of: notificaciones.toqueDiario, initial: true) { _, _ in abrirAvisoDiarioSiCorresponde() }
        .sheet(item: $cambioParaMostrar) { cambio in
            CambioRutaNotificadoView(cambio: cambio, locationService: locationService)
                .seguirTemaForzado()
                .presentationDetents([.large])
        }
        .sheet(item: $diarioParaMostrar) { tipo in
            detalleAvisoDiario(tipo).seguirTemaForzado().presentationDetents([.large])
        }
        .alert(L.aviso(tituloAviso), isPresented: $mostrarAvisoRecordatorio) {
            Button(L.t("Listo", "Done"), role: .cancel) {}
        } message: {
            Text(L.aviso(avisoRecordatorio ?? ""))
        }
        .tint(.appAccent)
        .onAppear { aplicarTemaEnVentanas(isDarkMode) }
        .onChange(of: TransporteApp.busesUTPDisponibles, initial: true) { _, disponibles in
            // Descarta también una activación antigua guardada fuera de UTP;
            // volver después al campus no debe reactivar el modo oculto.
            if !disponibles { preferenciaBusesUTP = false }
        }
        .onChange(of: busesUTPActivos) { _, _ in
            // Terminar el contexto anterior evita mezclar viajes, flotas o selecciones.
            trackingStore.model.cancelTrip()
            trackingStore.model.suspenderPantalla()
            trackingStore.reemplazar(RouteTrackingViewModel(locationService: locationService))
            trackingCoordinator.actualizarModoTransporte()
            router.rutaPendiente = nil
            router.destinoPendiente = nil
            router.lugarCercanoPendiente = nil
        }
        .onChange(of: isDarkMode) { _, nuevo in
            // Un único escritor del tema: inmediato y en ambos sentidos.
            aplicarTemaEnVentanas(nuevo)
        }
        .onChange(of: modoSenias) { _, activo in
            if activo {
                SeniasPresenter.shared.mostrarActivacionDelModo()
            } else {
                SeniasPresenter.shared.cancelarAccionPendiente()
                SeniasPresenter.shared.ocultar()
            }
        }
        .onChange(of: scenePhase, initial: true) { _, fase in
            PushRutasService.shared.primerPlano(fase == .active)
            if fase == .active {
                abrirRecordatorioSiCorresponde()
                abrirCambioSiCorresponde()
                abrirAvisoDiarioSiCorresponde()
                Task { await notificaciones.refrescar() }
            }
            if fase == .background {
                SeniasPresenter.shared.cancelarAccionPendiente()
                SeniasPresenter.shared.ocultar()
            }
        }
        .onChange(of: router.currentScreen) { _, screen in
            if screen != .mapaPrincipal { (mapMenu ?? $mostrarMenuMapa).wrappedValue = false }
            abrirRecordatorioSiCorresponde()
            abrirCambioSiCorresponde()
            abrirAvisoDiarioSiCorresponde()
            // Pantallas como NavegaciónRuta fuerzan .dark sobre la ventana;
            // al salir de ellas se re-afirma el tema elegido por el usuario.
            aplicarTemaEnVentanas(isDarkMode)
        }
        // Modo Señas: el miniplayer NO va en overlay aquí — vive en su propia
        // UIWindow a nivel .alert (SeniasOverlayVentana) para verse por encima
        // de sheets y fullScreenCovers. La ventana sigue el estado de
        // SeniasPresenter y sólo se muestra mientras hay una seña visible.
    }

    private func abrirRecordatorioSiCorresponde() {
        guard scenePhase == .active, router.currentScreen != .bienvenida,
              notificaciones.toquePendiente != nil else { return }
        let destino = notificaciones.destinoDelToque()
        notificaciones.toquePendiente = nil
        if trackingCoordinator.selectedTripRoute != nil || trackingStore.model.tripInProgress || notificaciones.navegacionAbierta {
            avisoRecordatorio = L.t("Tienes un viaje en curso. Termínalo antes de abrir otro destino.",
                                    "You have a trip in progress. Finish it before opening another destination.")
        } else if let destino {
            router.destinoPendiente = destino.pendiente
            router.navigate(to: .mapaPrincipal)
            return
        } else {
            avisoRecordatorio = L.t("Este recordatorio ya no está disponible. Revisa tus ajustes de notificaciones.",
                                    "This reminder is no longer available. Check your notification settings.")
        }
        presentarAviso(titulo: L.t("Recordatorio de viaje", "Trip reminder"))
    }

    private func abrirCambioSiCorresponde() {
        guard scenePhase == .active, router.currentScreen != .bienvenida, !abriendoCambio,
              let cambio = PushRutasService.shared.toquePendiente else { return }
        abriendoCambio = true
        PushRutasService.shared.toquePendiente = nil
        Task { @MainActor in
            defer { abriendoCambio = false }
            let titulo = L.t("Cambios de ruta", "Route changes")
            guard PushRutasService.shared.toqueVigente(cambio) else {
                avisoRecordatorio = L.t("Este aviso ya venció o la línea ya no está guardada. Revisa los reportes actuales en Seguridad.", "This notification has expired or the line is no longer saved. Check current reports in Safety.")
                presentarAviso(titulo: titulo)
                return
            }
            guard trackingCoordinator.selectedTripRoute == nil, !trackingStore.model.tripInProgress, !notificaciones.navegacionAbierta else {
                avisoRecordatorio = L.t("Tienes un viaje en curso. Puedes revisar los cambios de ruta en Seguridad al terminarlo.", "You have a trip in progress. You can check route changes in Safety when it ends.")
                presentarAviso(titulo: titulo)
                return
            }
            do {
                let rutas = try await GTFSRepository.shared.cargarRutas()
                guard rutas.contains(where: { $0.id == cambio.routeID }), PushRutasService.shared.toqueVigente(cambio) else {
                    avisoRecordatorio = L.t("Este aviso ya venció o la línea ya no está guardada. Revisa los reportes actuales en Seguridad.", "This notification has expired or the line is no longer saved. Check current reports in Safety.")
                    presentarAviso(titulo: titulo)
                    return
                }
                // Volver a comprobar tras la carga: el usuario pudo comenzar
                // un viaje mientras el catalogo se resolvia.
                guard scenePhase == .active, trackingCoordinator.selectedTripRoute == nil,
                      !trackingStore.model.tripInProgress, !notificaciones.navegacionAbierta else {
                    PushRutasService.shared.toquePendiente = cambio
                    return
                }
                if let superior = controladorPresentado() {
                    let vista = CambioRutaNotificadoView(cambio: cambio, locationService: locationService)
                        .environment(\.locale, IdiomaManager.shared.idioma.locale).seguirTemaForzado()
                    let controller = UIHostingController(rootView: vista)
                    controller.sheetPresentationController?.detents = [.large()]
                    superior.present(controller, animated: !reduceMotion)
                } else { cambioParaMostrar = cambio }
            } catch {
                avisoRecordatorio = L.t("No pudimos cargar las rutas. Puedes reintentar.", "We couldn't load the routes. You can try again.")
                presentarAviso(titulo: titulo)
            }
        }
    }

    private func controladorPresentado() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController,
              root.presentedViewController != nil else { return nil }
        var superior = root
        while let presentada = superior.presentedViewController { superior = presentada }
        return superior
    }

    private var viajeEnCurso: Bool {
        trackingCoordinator.selectedTripRoute != nil || trackingStore.model.tripInProgress || notificaciones.navegacionAbierta
    }

    private func detalleAvisoDiario(_ tipo: TipoAvisoDiario) -> some View {
        AvisoDiarioDetalleView(tipo: tipo, locationService: locationService, puedeNavegar: !viajeEnCurso) { pantalla in
            // Una deteccion pudo comenzar mientras el aviso estaba abierto.
            guard !viajeEnCurso else { return }
            router.navigate(to: pantalla)
        }
    }

    private func abrirAvisoDiarioSiCorresponde() {
        guard scenePhase == .active, router.currentScreen != .bienvenida,
              let tipo = notificaciones.toqueDiario else { return }
        notificaciones.toqueDiario = nil
        if let superior = controladorPresentado() {
            let vista = detalleAvisoDiario(tipo).environment(\.locale, IdiomaManager.shared.idioma.locale).seguirTemaForzado()
            let controller = UIHostingController(rootView: vista)
            controller.sheetPresentationController?.detents = [.large()]
            superior.present(controller, animated: !reduceMotion)
        } else { diarioParaMostrar = tipo }
    }

    private func presentarAviso(titulo: String) {
        tituloAviso = titulo
        // Un alert de la vista de fondo no se presenta sobre un cover activo.
        // Informar encima de la navegacion preserva su modelo y su pantalla.
        if let superior = controladorPresentado() {
            let aviso = UIAlertController(title: titulo,
                                          message: avisoRecordatorio.map(L.aviso), preferredStyle: .alert)
            aviso.addAction(UIAlertAction(title: L.t("Listo", "Done"), style: .default))
            superior.present(aviso, animated: !reduceMotion)
        } else {
            mostrarAvisoRecordatorio = true
        }
    }

}

/// Contenedor nativo de las cinco pestañas; conserva contenido y ciclo de visibilidad.
struct MainTabsView: View {
    let locationService: LocationServiceProtocol
    let busesUTPActivos: Bool
    @Binding var mostrarMenuMapa: Bool
    @EnvironmentObject private var router: AppRouter
    @State private var mapNavigation = MapNavigationBarPresentation()

    private struct ContentIdentity: Hashable {
        let screen: AppScreen
        let busesUTP: Bool
    }

    var body: some View {
        // TabView conserva la identidad de cada pestaña y entrega onAppear /
        // onDisappear solo al contenido visible. Así el mapa conserva su cámara
        // y los catálogos cargados se reutilizan sin dejar GPS o timers ocultos.
        ZStack {
            VStack(spacing: 0) {
                contenidoPestanas
                    .environment(\.mainNavigationHostedExternally, true)
                    // La barra ocupa su propia fila; el contenido ya no necesita
                    // reservar su altura ni puede quedar encima de sus botones.
                    .environment(\.bottomNavBarHeight, 0)

                // Una única barra vive fuera del contenido que TabView presenta.
                // Cambiar de pestaña no la retira, oculta ni vuelve a crear.
                if router.currentScreen != .mapaPrincipal || mapNavigation.isVisible {
                    BottomNavBar()
                        .accessibilityHidden(mostrarMenuMapa || (router.currentScreen == .mapaPrincipal && mapNavigation.accessibilityHidden))
                        .allowsHitTesting(!mostrarMenuMapa)
                        .zIndex(1)
                }
            }
            .allowsHitTesting(!mostrarMenuMapa)
            .accessibilityHidden(mostrarMenuMapa)

            // El menú cubre también la barra inferior sin cambiar el tamaño del mapa.
            SideDrawer(isOpen: $mostrarMenuMapa)
        }
        .onPreferenceChange(MapNavigationBarPresentationKey.self) { presentation in
            if let presentation { mapNavigation = presentation }
        }
        .ignoresSafeArea(edges: .bottom)
        .background(Color.appBackground.ignoresSafeArea())
        .transition(.identity)
    }

    private var contenidoPestanas: some View {
        TabView(selection: $router.currentScreen) {
            MapaView(locationService: locationService, mapMenu: $mostrarMenuMapa)
                .id(ContentIdentity(screen: .mapaPrincipal, busesUTP: busesUTPActivos))
                .modifier(MainTabBarHidden())
                .tag(AppScreen.mapaPrincipal)
            RutasView(locationService: locationService)
                .id(ContentIdentity(screen: .rutas, busesUTP: busesUTPActivos))
                .modifier(MainTabBarHidden())
                .tag(AppScreen.rutas)
            GuardadoView(locationService: locationService)
                .id(ContentIdentity(screen: .guardado, busesUTP: busesUTPActivos))
                .modifier(MainTabBarHidden())
                .tag(AppScreen.guardado)
            SeguridadView(locationService: locationService)
                .id(ContentIdentity(screen: .seguridad, busesUTP: busesUTPActivos))
                .modifier(MainTabBarHidden())
                .tag(AppScreen.seguridad)
            PerfilView()
                .modifier(MainTabBarHidden())
                .tag(AppScreen.perfil)
        }
    }

}

/// La navegación visible pertenece a RutaUTP. iOS 17 puede reactivar la barra
/// vacía de TabView al regresar al mapa, aunque su preferencia siga oculta.
private struct MainTabBarHidden: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .tabBar)
            .toolbarBackground(.hidden, for: .tabBar)
            .background(NativeTabBarHider().frame(width: 0, height: 0))
    }
}

private struct NativeTabBarHider: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.hideNativeBar()
        // SwiftUI termina de aplicar sus preferencias tras actualizar al hijo.
        DispatchQueue.main.async { [weak controller] in controller?.hideNativeBar() }
    }

    final class Controller: UIViewController {
        override func loadView() {
            view = UIView()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            hideNativeBar()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            hideNativeBar()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            guard let controller = tabBarController else { return }
            if #available(iOS 18.0, *) {
                if !controller.isTabBarHidden { hideNativeBar() }
            } else if !controller.tabBar.isHidden {
                hideNativeBar()
            }
        }

        func hideNativeBar() {
            guard let controller = tabBarController else { return }
            if #available(iOS 18.0, *) {
                controller.setTabBarHidden(true, animated: false)
            } else if !controller.tabBar.isHidden {
                controller.tabBar.isHidden = true
            }
        }
    }
}

private struct CambioRutaNotificadoView: View {
    let cambio: ToqueCambioRuta
    let locationService: LocationServiceProtocol
    @StateObject private var servicio = RouteChangesService()

    var body: some View {
        // Consultar el estado actual al abrir; el payload no se convierte en
        // un cierre vigente ni se inserta como un reporte artificial.
        RouteChangesSheet(service: servicio, initialRouteID: cambio.routeID, locationService: locationService)
            .onAppear { servicio.start() }
            .onDisappear { servicio.stop() }
    }
}

private struct AvisoDiarioDetalleView: View {
    let tipo: TipoAvisoDiario
    let locationService: LocationServiceProtocol
    let puedeNavegar: Bool
    let abrirPantalla: (AppScreen) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var mostrarConsulta = false
    @StateObject private var cambios = RouteChangesService()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(tipo.titulo).font(.title3.bold())
                    Text(tipo.mensaje)
                }
                if tipo == .cupones {
                    Text(L.t("El catálogo actual de negocios es de demostración. Todavía no hay descuentos reales verificados para enviar avisos.", "The current business catalog is for demonstration. There are no verified real discounts for notifications yet."))
                        .font(.footnote)
                }
                if puedeNavegar {
                    switch tipo {
                    case .rutas:
                        Button(L.t("Ver rutas", "View routes")) { irA(.rutas) }
                    case .cambios:
                        Button(L.t("Consultar cambios de ruta", "Check route changes")) { mostrarConsulta = true }
                    case .cupones:
                        Button(L.t("Mis cupones", "My coupons")) { irA(.perfil) }
                    case .guardado:
                        Button(L.t("Guardado", "Saved")) { irA(.guardado) }
                    }
                } else {
                    Text(L.t("Puedes leer este consejo y continuar tu viaje. Revisa las otras pantallas cuando termines.", "You can read this tip and continue your trip. Check the other screens when you finish."))
                        .font(.footnote)
                }
            }
            .navigationTitle(L.t("Avisos del día", "Daily notifications"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L.t("Cerrar", "Close")) { dismiss() } } }
            .sheet(isPresented: $mostrarConsulta) {
                RouteChangesSheet(service: cambios, locationService: locationService)
                    .seguirTemaForzado().presentationDetents([.large])
                    .onAppear { cambios.start() }
                    .onDisappear { cambios.stop() }
            }
        }
        .tint(.appAccent)
    }

    private func irA(_ pantalla: AppScreen) {
        dismiss()
        abrirPantalla(pantalla)
    }
}

#Preview {
    RootView()
}
