import Foundation
import Observation
import UserNotifications
import UIKit

@MainActor @Observable
final class NotificacionesService {
    static let shared = NotificacionesService()
    nonisolated static let prefijo = "rutautp.recordatorio."
    nonisolated static let prefijoDiarios = "rutautp.diario."
    nonisolated static let idPrueba = "rutautp.prueba.notificaciones"
    let preferencias = PreferenciasNotificacionesStore()
    let avisosDiarios = AvisosDiariosStore()
    private(set) var autorizacion: UNAuthorizationStatus = .notDetermined
    private(set) var consultado = false
    private(set) var bannersPermitidos = false
    private(set) var sonidoPermitido = false
    private(set) var programando = false
    private(set) var solicitandoPermiso = false
    private(set) var destinos: [DestinoRecordatorio] = []
    private(set) var fechasProgramadas: [Date] = []
    private(set) var fechasDiarias: [Date] = []
    private(set) var errorMensaje: String?
    private(set) var mensajePrueba: String?
    var toquePendiente: UUID?
    var toqueDiario: TipoAvisoDiario?
    var navegacionAbierta = false

    @ObservationIgnored private let centro = UNUserNotificationCenter.current()
    @ObservationIgnored private let delegado = DelegadoNotificaciones()
    @ObservationIgnored private var observadores: [NSObjectProtocol] = []
    @ObservationIgnored private var defaultsPrevios: NSDictionary?
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var tarea: Task<Void, Never>?
    @ObservationIgnored private var iniciado = false
    @ObservationIgnored private var falloPermiso = false

    var permitido: Bool { autorizacion == .authorized || autorizacion == .provisional || autorizacion == .ephemeral }
    var destinoActual: DestinoRecordatorio? {
        guard let id = preferencias.configuracion.recordatorio?.destinoID else { return nil }
        return destinos.first { $0.id == id }
    }

    func resumen(ahora: Date = Date()) -> String {
        if preferencias.datosInvalidos { return L.t("Revisa tus ajustes", "Check your settings") }
        if !preferencias.activadas { return L.t("Desactivadas", "Disabled") }
        if !consultado { return L.t("Consultando iOS…", "Checking iOS…") }
        if autorizacion == .denied { return L.t("Bloqueadas por iOS", "Blocked by iOS") }
        if !permitido { return L.t("Pendientes de permiso", "Awaiting permission") }
        if let fin = preferencias.configuracion.pausaHasta, fin > ahora {
            return L.f("Pausadas hasta {0}", "Paused until {0}", [fechaTexto(fin)])
        }
        if !preferencias.configuracion.permite(ahora, calendario: ProgramadorRecordatorios.calendario) {
            return L.t("Horario de silencio", "Quiet hours")
        }
        if preferencias.configuracion.recordatorio == nil {
            if avisosDiarios.datosInvalidos || avisosDiarios.registroInvalido { return L.t("Revisa tus ajustes", "Check your settings") }
            if avisosDiarios.configuracion.activa && fechasDiarias.contains(where: { $0 > ahora }) {
                return L.t("Activas", "Active")
            }
            if PushRutasService.shared.activadas && PushRutasService.shared.registroConfirmado {
                return L.t("Registro remoto confirmado", "Remote registration confirmed")
            }
            return L.t("Sin recordatorios", "No reminders")
        }
        if destinoActual == nil { return L.t("Revisa el destino", "Check the destination") }
        if errorMensaje != nil { return L.t("Revisa la programación", "Check the schedule") }
        if fechasProgramadas.contains(where: { $0 > ahora }) { return L.t("Activas", "Active") }
        return L.t("Sin fechas programadas", "No scheduled dates")
    }

    func fechaTexto(_ fecha: Date) -> String {
        fecha.formatted(.dateTime.day().month(.abbreviated).year().hour().minute().locale(IdiomaManager.shared.idioma.locale))
    }

    func instalar() {
        centro.delegate = delegado
        guard !iniciado else { return }
        iniciado = true
        registrarDefaults()
        observadores.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.defaultsCambiaron() else { return }
                await self.refrescar()
            }
        })
        for nombre in [UIApplication.significantTimeChangeNotification, Notification.Name.NSSystemTimeZoneDidChange] {
            observadores.append(NotificationCenter.default.addObserver(forName: nombre, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in await self?.refrescar() }
            })
        }
    }

    private func snapshotDefaults() -> NSDictionary {
        var valores: [String: Any] = [:]
        for key in [PreferenciasNotificacionesStore.llave, PreferenciasApp.notificaciones,
                    LugaresStore.key, SedeTrabajoStore.llave, SedeTrabajoStore.llaveReferenciaUTP, "idioma.app",
                    PushRutasService.llave, "lineas.guardadas.v1", AvisosDiariosStore.llave] {
            valores[key] = UserDefaults.standard.object(forKey: key) ?? "<ausente>"
        }
        return NSDictionary(dictionary: valores)
    }
    private func registrarDefaults() { defaultsPrevios = snapshotDefaults() }
    private func defaultsCambiaron() -> Bool {
        let actuales = snapshotDefaults()
        guard defaultsPrevios != actuales else { return false }
        defaultsPrevios = actuales
        return true
    }

    func refrescar() async {
        preferencias.recargar()
        avisosDiarios.recargar()
        destinos = DestinoRecordatorio.disponibles()
        registrarDefaults()
        revision &+= 1
        if tarea == nil {
            tarea = Task { @MainActor in await self.procesarAgenda() }
        }
        await tarea?.value
        PushRutasService.shared.sincronizar()
    }

    private func consultarPermiso() async {
        let ajustes = await centro.notificationSettings()
        autorizacion = ajustes.authorizationStatus
        bannersPermitidos = ajustes.alertSetting == .enabled
        sonidoPermitido = ajustes.soundSetting == .enabled
        consultado = true
        if autorizacion != .notDetermined { falloPermiso = false }
    }

    private func solicitarSiHaceFalta() async {
        await consultarPermiso()
        guard autorizacion == .notDetermined, !solicitandoPermiso else { return }
        solicitandoPermiso = true
        falloPermiso = false
        defer { solicitandoPermiso = false }
        do { _ = try await centro.requestAuthorization(options: [.alert, .sound]) }
        catch { falloPermiso = true }
        await consultarPermiso()
    }

    func solicitarPermisoParaPush() async {
        await solicitarSiHaceFalta()
        await refrescar()
    }

    func guardarAvisosDiarios(_ config: ConfiguracionAvisosDiarios) async -> Bool {
        guard avisosDiarios.guardar(config) else {
            errorMensaje = L.t("No pudimos guardar los avisos diarios. Tus datos anteriores se conservan.", "We could not save daily notifications. Your previous data has been preserved.")
            return false
        }
        if config.activa && preferencias.activadas { await solicitarSiHaceFalta() }
        await refrescar()
        return true
    }

    func activarAvisosDiarios(_ activa: Bool) async {
        var config = avisosDiarios.configuracion
        config.activa = activa
        _ = await guardarAvisosDiarios(config)
    }

    func activar(_ activa: Bool) async {
        preferencias.activar(activa)
        mensajePrueba = nil
        if !activa, !preferencias.datosInvalidos {
            var config = preferencias.configuracion
            config.pausaHasta = nil
            preferencias.guardar(config)
        }
        if activa { await solicitarSiHaceFalta() }
        await refrescar()
    }

    @discardableResult
    func cambiar(_ cambios: (inout ConfiguracionNotificaciones) -> Void) async -> Bool {
        var config = preferencias.configuracion
        cambios(&config)
        guard preferencias.guardar(config) else {
            await refrescar()
            errorMensaje = L.t("No pudimos guardar tus ajustes. Tus datos anteriores se conservan.", "We could not save your settings. Your previous data has been preserved.")
            return false
        }
        mensajePrueba = nil
        await refrescar()
        return true
    }

    func guardarRecordatorio(_ recordatorio: RecordatorioViaje) async -> Bool {
        destinos = DestinoRecordatorio.disponibles()
        guard recordatorio.esValido, destinos.contains(where: { $0.id == recordatorio.destinoID }) else { return false }
        guard await cambiar({ $0.recordatorio = recordatorio }) else { return false }
        if preferencias.activadas { await solicitarSiHaceFalta() }
        await refrescar()
        return true
    }

    func reactivar() async {
        guard await cambiar({ $0.pausaHasta = nil }) else { return }
        await activar(true)
    }

    func prepararPresentacion() async {
        preferencias.recargar()
        avisosDiarios.recargar()
        await consultarPermiso()
    }

    func permiteAviso(_ fecha: Date) -> Bool {
        preferencias.activadas && !preferencias.datosInvalidos && permitido
            && preferencias.configuracion.permite(fecha, calendario: ProgramadorRecordatorios.calendario)
    }

    func probar() async {
        await refrescar()
        let fecha = Date().addingTimeInterval(5)
        guard permiteAviso(fecha) else { return }
        let contenido = UNMutableNotificationContent()
        contenido.title = L.t("Notificación de prueba", "Test notification")
        contenido.body = L.t("Esta es una prueba de los avisos locales de RutaUTP.", "This is a test of RutaUTP's local notifications.")
        contenido.userInfo = ["fechaPrueba": fecha.timeIntervalSince1970]
        if preferencias.configuracion.sonido && sonidoPermitido { contenido.sound = .default }
        let solicitud = UNNotificationRequest(identifier: Self.idPrueba, content: contenido,
                                             trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false))
        do {
            try await centro.add(solicitud)
            // Una desactivacion concurrente no puede dejar escapar la prueba.
            if !permiteAviso(fecha) {
                centro.removePendingNotificationRequests(withIdentifiers: [Self.idPrueba])
                return
            }
            let pendientes = await centro.pendingNotificationRequests()
            guard pendientes.contains(where: { $0.identifier == Self.idPrueba }) else { return }
            mensajePrueba = L.t("iOS aceptó la prueba. El aviso está programado para dentro de 5 segundos.", "iOS accepted the test. The notification is scheduled in 5 seconds.")
        } catch {
            errorMensaje = L.t("iOS no pudo programar la prueba. Intenta de nuevo.", "iOS could not schedule the test. Try again.")
        }
    }

    private func procesarAgenda() async {
        programando = true
        defer { programando = false; tarea = nil }
        var procesada = -1
        while procesada != revision {
            let version = revision
            procesada = version
            errorMensaje = nil
            await consultarPermiso()
            if version != revision { continue }
            let config = preferencias.configuracion
            let diario = avisosDiarios.configuracion
            let recordatorio = config.recordatorio
            let destino = destinoActual
            let pendientes = await centro.pendingNotificationRequests()
            if version != revision { continue }
            // Presupuesto propio, no un supuesto sobre el limite de iOS.
            // Conservar avisos ajenos y reservar una plaza para la prueba local.
            let ajenos = pendientes.filter { !$0.identifier.hasPrefix(Self.prefijo) && !$0.identifier.hasPrefix(Self.prefijoDiarios) && $0.identifier != Self.idPrueba }.count
            let presupuesto = max(0, 59 - ajenos)
            let fechas = preferencias.activadas && permitido && !preferencias.datosInvalidos && destino != nil
                ? ProgramadorRecordatorios.fechas(config: config, desde: Date(), limite: min(30, presupuesto)) : []
            let planesDiarios = preferencias.activadas && permitido && !preferencias.datosInvalidos
                && !avisosDiarios.datosInvalidos && !avisosDiarios.registroInvalido
                ? ProgramadorAvisosDiarios.planes(config: diario, silencios: config, registro: avisosDiarios.planes,
                                                 desde: Date(), limite: min(30, max(0, presupuesto - fechas.count))) : []
            let textoDestino = destino.map { L.f("Es hora de salir hacia {0}. Abre RutaUTP para revisar tu destino.", "Time to head to {0}. Open RutaUTP to check your destination.", [$0.nombre]) }
            let idsDeseados = Set(fechas.map { Self.prefijo + (recordatorio?.id.uuidString ?? "") + "." + String(Int($0.timeIntervalSince1970)) })
            let sonido = config.sonido && sonidoPermitido
            var validos = Set(pendientes.filter {
                idsDeseados.contains($0.identifier)
                    && $0.content.body == textoDestino
                    && $0.content.title == L.t("Hora de salir", "Time to leave")
                    && ($0.content.sound != nil) == sonido
                    && $0.content.userInfo["zona"] as? String == TimeZone.current.identifier
            }.map(\.identifier))
            for plan in planesDiarios {
                let id = Self.prefijoDiarios + plan.clave
                if let existente = pendientes.first(where: { $0.identifier == id }),
                   existente.content.title == plan.tipo.titulo, existente.content.body == plan.tipo.mensaje,
                   (existente.content.sound != nil) == sonido,
                   existente.content.userInfo["zona"] as? String == plan.zona,
                   existente.content.userInfo["avisosDiariosID"] as? String == diario.id.uuidString,
                   existente.content.userInfo["tipoAvisoDiario"] as? String == plan.tipo.rawValue,
                   (existente.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() == plan.fecha {
                    validos.insert(id)
                }
            }
            // Conservar las solicitudes que ya coinciden evita retirar un
            // aviso inminente solo porque la app volvio a primer plano.
            var retirar = pendientes.filter {
                ($0.identifier.hasPrefix(Self.prefijo) || $0.identifier.hasPrefix(Self.prefijoDiarios)) && !validos.contains($0.identifier)
            }.map(\.identifier)
            if let prueba = pendientes.first(where: { $0.identifier == Self.idPrueba }) {
                let fecha = (prueba.content.userInfo["fechaPrueba"] as? Double).map(Date.init(timeIntervalSince1970:))
                if fecha.map({ !permiteAviso($0) }) ?? true { retirar.append(Self.idPrueba) }
            }
            // Confirmar la retirada antes de volver a programar. Las APIs de
            // cancelacion son asincronas y no ofrecen callback de finalizacion.
            var sinRetirar = Set(retirar)
            for _ in 0..<3 where !sinRetirar.isEmpty {
                centro.removePendingNotificationRequests(withIdentifiers: Array(sinRetirar))
                let actuales = await centro.pendingNotificationRequests()
                sinRetirar.formIntersection(actuales.map(\.identifier))
            }
            if version != revision { continue }
            if !sinRetirar.isEmpty {
                errorMensaje = L.t("No pudimos confirmar la cancelación de todos los avisos. Intenta de nuevo.", "We could not confirm cancellation of all notifications. Try again.")
            } else if let recordatorio, let destino {
                for fecha in fechas {
                    guard version == revision else { break }
                    let id = Self.prefijo + recordatorio.id.uuidString + "." + String(Int(fecha.timeIntervalSince1970))
                    if validos.contains(id) || fecha <= Date() { continue }
                    let contenido = UNMutableNotificationContent()
                    contenido.title = L.t("Hora de salir", "Time to leave")
                    contenido.body = L.f("Es hora de salir hacia {0}. Abre RutaUTP para revisar tu destino.", "Time to head to {0}. Open RutaUTP to check your destination.", [destino.nombre])
                    contenido.userInfo = ["recordatorioID": recordatorio.id.uuidString, "zona": TimeZone.current.identifier]
                    contenido.threadIdentifier = "rutautp.viajes"
                    if config.sonido && sonidoPermitido { contenido.sound = .default }
                    let calendar = ProgramadorRecordatorios.calendario
                    var componentes = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fecha)
                    componentes.calendar = calendar
                    componentes.timeZone = calendar.timeZone
                    let solicitud = UNNotificationRequest(identifier: id, content: contenido,
                                                         trigger: UNCalendarNotificationTrigger(dateMatching: componentes, repeats: false))
                    do { try await centro.add(solicitud) }
                    catch { errorMensaje = L.t("No se pudieron programar todos los avisos. Vuelve a intentarlo.", "Not all notifications could be scheduled. Try again.") }
                    if version != revision { centro.removePendingNotificationRequests(withIdentifiers: [id]); break }
                }
            }
            if version != revision { continue }
            if sinRetirar.isEmpty {
                for plan in planesDiarios {
                    guard version == revision else { break }
                    let id = Self.prefijoDiarios + plan.clave
                    if plan.fecha <= Date() { continue }
                    if !validos.contains(id) {
                        let contenido = UNMutableNotificationContent()
                        contenido.title = plan.tipo.titulo
                        contenido.body = plan.tipo.mensaje
                        contenido.userInfo = ["avisosDiariosID": diario.id.uuidString,
                                              "tipoAvisoDiario": plan.tipo.rawValue, "zona": plan.zona]
                        contenido.threadIdentifier = "rutautp.diarios"
                        if sonido { contenido.sound = .default }
                        let calendar = ProgramadorRecordatorios.calendario
                        var componentes = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: plan.fecha)
                        componentes.calendar = calendar
                        componentes.timeZone = calendar.timeZone
                        let solicitud = UNNotificationRequest(identifier: id, content: contenido,
                                                             trigger: UNCalendarNotificationTrigger(dateMatching: componentes, repeats: false))
                        do { try await centro.add(solicitud) }
                        catch {
                            errorMensaje = L.t("No se pudieron programar todos los avisos. Vuelve a intentarlo.", "Not all notifications could be scheduled. Try again.")
                            continue
                        }
                    }
                    // Guardar tambien si cambio la revision durante el await:
                    // un aviso aceptado y vencido no se vuelve a sortear hoy.
                    if !avisosDiarios.registrar(plan, ahora: Date()) {
                        centro.removePendingNotificationRequests(withIdentifiers: [id])
                        errorMensaje = L.t("No pudimos conservar la agenda diaria. Intenta de nuevo; tus datos anteriores se conservan.", "We could not save the daily schedule. Try again; your previous data has been preserved.")
                    }
                    if version != revision { centro.removePendingNotificationRequests(withIdentifiers: [id]); break }
                }
            }
            if version != revision { continue }
            let aceptadas = await centro.pendingNotificationRequests()
            if version != revision { continue }
            fechasProgramadas = aceptadas.compactMap { solicitud in
                guard solicitud.identifier.hasPrefix(Self.prefijo),
                      solicitud.content.userInfo["recordatorioID"] as? String == recordatorio?.id.uuidString,
                      let trigger = solicitud.trigger as? UNCalendarNotificationTrigger,
                      let fecha = trigger.nextTriggerDate(), fecha > Date() else { return nil }
                return fecha
            }.sorted()
            fechasDiarias = aceptadas.compactMap { solicitud in
                guard solicitud.identifier.hasPrefix(Self.prefijoDiarios),
                      solicitud.content.userInfo["avisosDiariosID"] as? String == diario.id.uuidString,
                      let fecha = (solicitud.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate(), fecha > Date() else { return nil }
                return fecha
            }.sorted()
            if preferencias.datosInvalidos {
                errorMensaje = L.t("No pudimos leer tus ajustes de notificaciones. Tus datos se conservan.", "We could not read your notification settings. Your data has been preserved.")
            } else if avisosDiarios.datosInvalidos || avisosDiarios.registroInvalido {
                errorMensaje = L.t("No pudimos leer los ajustes o la agenda de avisos diarios. Tus datos se conservan.", "We could not read daily notification settings or the schedule. Your data has been preserved.")
            } else if falloPermiso && errorMensaje == nil {
                errorMensaje = L.t("No pudimos consultar el permiso de notificaciones. Intenta de nuevo.", "We could not request notification permission. Try again.")
            } else if errorMensaje == nil && (fechasProgramadas.count != fechas.filter({ $0 > Date() }).count
                                            || fechasDiarias.count != planesDiarios.filter({ $0.fecha > Date() }).count) {
                errorMensaje = L.t("No se pudieron programar todos los avisos. Vuelve a intentarlo.", "Not all notifications could be scheduled. Try again.")
            }
        }
    }

    func destinoDelToque() -> DestinoRecordatorio? {
        guard let id = toquePendiente, let recordatorio = preferencias.configuracion.recordatorio,
              id == recordatorio.id else { return nil }
        return DestinoRecordatorio.disponibles().first { $0.id == recordatorio.destinoID }
    }
}

private final class DelegadoNotificaciones: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in
            let servicio = NotificacionesService.shared
            await servicio.prepararPresentacion()
            guard servicio.permiteAviso(Date()) else { completionHandler([]); return }
            if notification.request.trigger is UNPushNotificationTrigger {
                guard let toque = ToqueCambioRuta(contenido: notification.request.content.userInfo),
                      PushRutasService.shared.permitePresentar(toque) else { completionHandler([]); return }
            }
            if notification.request.identifier.hasPrefix(NotificacionesService.prefijoDiarios) {
                guard servicio.avisosDiarios.configuracion.activa, !servicio.avisosDiarios.datosInvalidos,
                      !servicio.avisosDiarios.registroInvalido,
                      notification.request.content.userInfo["avisosDiariosID"] as? String == servicio.avisosDiarios.configuracion.id.uuidString else {
                    completionHandler([]); return
                }
            }
            var opciones: UNNotificationPresentationOptions = [.banner, .list]
            if servicio.preferencias.configuracion.sonido { opciones.insert(.sound) }
            completionHandler(opciones)
            await servicio.refrescar()
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { completionHandler(); return }
        if response.notification.request.trigger is UNPushNotificationTrigger {
            let toque = ToqueCambioRuta(contenido: response.notification.request.content.userInfo)
            Task { @MainActor in PushRutasService.shared.toquePendiente = toque; completionHandler() }
            return
        }
        if response.notification.request.identifier.hasPrefix(NotificacionesService.prefijoDiarios),
           let raw = response.notification.request.content.userInfo["tipoAvisoDiario"] as? String,
           let tipo = TipoAvisoDiario(rawValue: raw) {
            Task { @MainActor in NotificacionesService.shared.toqueDiario = tipo; completionHandler() }
            return
        }
        guard response.notification.request.identifier.hasPrefix(NotificacionesService.prefijo),
              let texto = response.notification.request.content.userInfo["recordatorioID"] as? String,
              let id = UUID(uuidString: texto) else { completionHandler(); return }
        Task { @MainActor in NotificacionesService.shared.toquePendiente = id; completionHandler() }
    }
}

final class NotificacionesAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        NotificacionesService.shared.instalar()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushRutasService.shared.recibioToken(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // No registrar tokens, credenciales ni detalles internos en logs.
        PushRutasService.shared.falloRegistro()
    }
}
