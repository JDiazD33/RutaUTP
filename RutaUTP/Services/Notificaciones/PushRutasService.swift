import Foundation
import CoreFoundation
import Observation
import UserNotifications
import UIKit
import CocoaMQTT

struct ToqueCambioRuta: Identifiable, Equatable {
    let id: UUID
    let routeID: String
    let expiresAt: Date

    init?(contenido: [AnyHashable: Any]) {
        guard let body = contenido["rutaUTP"] as? [String: Any],
              body["schemaVersion"] as? Int == 1, body["kind"] as? String == "routeChange",
              let rawID = body["eventID"] as? String, let id = UUID(uuidString: rawID),
              let route = body["routeID"] as? String, !route.isEmpty, route.count <= 128,
              let expires = body["expiresAt"] as? Double, expires.isFinite,
              (0..<4102444800).contains(expires) else { return nil }
        self.id = id
        routeID = route
        expiresAt = Date(timeIntervalSince1970: expires)
    }
}

private struct ReciboPush: Decodable {
    let requestID: UUID
    let revision: Int
    let accepted: Bool
    let providerReady: Bool
    let code: String
    let leaseUntil: Double
}

/// MQTT solo registra preferencias. Apple entrega el aviso visible a iOS,
/// incluso cuando esta conexion ya esta cerrada por entrar en segundo plano.
@MainActor @Observable
final class PushRutasService {
    static let shared = PushRutasService()
    static let llave = "notificaciones.push.rutas.v1"
    private static let llaveInstalacion = "notificaciones.push.instalacion.v1"
    private static let llaveRevision = "notificaciones.push.revision.v1"
    private static let llaveCobertura = "notificaciones.push.cobertura.v1"
    private(set) var activadas = false
    private(set) var lineas: [String] = []
    private(set) var datosInvalidos = false
    private(set) var registroConfirmado = false
    private(set) var fechaCobertura = UserDefaults.standard.object(forKey: PushRutasService.llaveCobertura) as? Date
    private(set) var estado: Estado = .desactivadas
    var toquePendiente: ToqueCambioRuta?

    enum Estado { case desactivadas, versionSinPush, faltaConexion, requiereTLS, faltaPermiso,
                       registrandoApple, errorApple, sincronizando, pendiente, confirmado,
                       faltaProveedor, rechazado }
    @ObservationIgnored private var enPrimerPlano = false
    @ObservationIgnored private var token: String?
    @ObservationIgnored private var registrando = false
    @ObservationIgnored private var mqtt: CocoaMQTT?
    @ObservationIgnored private var endpoint: String?
    @ObservationIgnored private var principal = ""
    @ObservationIgnored private var suscrito = false
    @ObservationIgnored private var firmaEnviada: Data?
    @ObservationIgnored private var firmaConfirmada: Data?
    @ObservationIgnored private var solicitud: UUID?
    @ObservationIgnored private var revisionEnviada = 0
    @ObservationIgnored private var timeout: Task<Void, Never>?
    @ObservationIgnored private var registroTimeout: Task<Void, Never>?
    @ObservationIgnored private var ultimoRegistro: Date?

    var disponibleEnVersion: Bool {
        let valor = Bundle.main.object(forInfoDictionaryKey: "RutaPushEnabled") as? String
        return ["1", "YES", "true"].contains(valor ?? "")
    }
    private var entorno: String {
        Bundle.main.object(forInfoDictionaryKey: "RutaAPNSEnvironment") as? String ?? "development"
    }
    var pendienteSincronizar: Bool {
        fechaCobertura.map { $0 > Date() && firmaConfirmada != cuerpoBase() } ?? false
    }

    var textoEstado: String {
        if datosInvalidos { return L.t("No pudimos leer las líneas o los ajustes guardados. Tus datos se conservan.", "We could not read saved lines or settings. Your data has been preserved.") }
        switch estado {
        case .desactivadas: return L.t("Avisos de cambios desactivados", "Route change notifications disabled")
        case .versionSinPush: return L.t("Los avisos remotos aún no están disponibles en esta versión.", "Remote notifications are not available in this version yet.")
        case .faltaConexion: return L.t("Falta configurar la conexión del servicio.", "The service connection needs to be configured.")
        case .requiereTLS: return L.t("La conexión no permite registrar avisos de forma segura.", "The connection cannot register notifications securely.")
        case .faltaPermiso: return L.t("Permite las notificaciones en iOS para recibir cambios de ruta.", "Allow notifications in iOS to receive route changes.")
        case .registrandoApple: return L.t("Registrando este dispositivo…", "Registering this device…")
        case .errorApple: return L.t("No pudimos registrar este dispositivo para avisos remotos. Intenta de nuevo.", "We could not register this device for remote notifications. Try again.")
        case .sincronizando: return L.t("Sincronizando con el servicio…", "Syncing with the service…")
        case .pendiente: return L.t("Cambios pendientes de sincronizar", "Changes waiting to sync")
        case .confirmado: return L.t("Registro remoto confirmado", "Remote registration confirmed")
        case .faltaProveedor: return L.t("El servidor recibió tus ajustes, pero el envío remoto aún no está configurado.", "The server received your settings, but remote delivery is not configured yet.")
        case .rechazado: return L.t("El servicio no aceptó el registro. Revisa la configuración de la conexión.", "The service did not accept registration. Check the connection configuration.")
        }
    }

    func cambiar(_ valor: Bool) async {
        guard !valor || disponibleEnVersion else { return }
        UserDefaults.standard.set(valor, forKey: Self.llave)
        if valor { await NotificacionesService.shared.solicitarPermisoParaPush() }
        sincronizar(forzar: true)
    }

    func primerPlano(_ activo: Bool) {
        enPrimerPlano = activo
        if activo { sincronizar(forzar: true) }
        else { desconectar() }
    }

    private func recargar() {
        let defaults = UserDefaults.standard
        let valor = PreferenciasApp.boolGuardado(para: Self.llave)
        datosInvalidos = defaults.object(forKey: Self.llave) != nil && valor == nil
        activadas = valor ?? false
        guard let original = defaults.object(forKey: "lineas.guardadas.v1") else { lineas = []; return }
        guard let data = original as? Data, let refs = try? JSONDecoder().decode([LineaGuardadaRef].self, from: data),
              refs.count <= 100, refs.allSatisfy({ !$0.routeId.isEmpty && $0.routeId.count <= 128 }) else {
            datosInvalidos = true
            lineas = []
            return
        }
        lineas = Array(Set(refs.map(\.routeId))).sorted()
    }

    private func identificadorInstalacion() -> UUID? {
        let defaults = UserDefaults.standard
        if let original = defaults.object(forKey: Self.llaveInstalacion) {
            let id = (original as? String).flatMap(UUID.init(uuidString:))
            if id == nil { datosInvalidos = true }
            return id
        }
        let id = UUID()
        defaults.set(id.uuidString, forKey: Self.llaveInstalacion)
        return id
    }

    private func cuerpoBase() -> Data? {
        guard let id = identificadorInstalacion() else { return nil }
        let servicio = NotificacionesService.shared
        let config = servicio.preferencias.configuracion
        let pausa: Any
        if let hasta = config.pausaHasta { pausa = max(0, hasta.timeIntervalSince1970) }
        else { pausa = NSNull() }
        let body: [String: Any] = [
            "schemaVersion": 1, "deviceID": id.uuidString, "environment": entorno,
            "token": token ?? "", "routes": lineas, "language": IdiomaManager.shared.codigo,
            "enabled": disponibleEnVersion && activadas && servicio.preferencias.activadas && servicio.permitido && !datosInvalidos && !servicio.preferencias.datosInvalidos && token != nil,
            "timeZone": TimeZone.current.identifier,
            "pauseUntil": pausa,
            "mutedDays": config.diasSilencio.sorted(), "quietHours": config.silencioHorario,
            "quietStart": config.inicioSilencio, "quietEnd": config.finSilencio,
            "sound": config.sonido && servicio.sonidoPermitido
        ]
        return try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    func sincronizar(forzar: Bool = false) {
        recargar()
        if !disponibleEnVersion {
            estado = .versionSinPush
            registroConfirmado = false
            // Una version sin APNs aun debe revocar un registro de una version
            // anterior. No pedir a Apple un token ni simular un registro nuevo.
            guard UserDefaults.standard.object(forKey: Self.llaveRevision) != nil else { return }
        }
        guard enPrimerPlano else { return }
        if !activadas && UserDefaults.standard.object(forKey: Self.llaveRevision) == nil {
            desconectar()
            estado = disponibleEnVersion ? .desactivadas : .versionSinPush
            return
        }
        guard let config = MQTTConfiguration.contributionFromEnvironment() else {
            desconectar(); estado = .faltaConexion; registroConfirmado = false; return
        }
        guard config.useTLS else {
            desconectar(); estado = .requiereTLS; registroConfirmado = false; return
        }
        let servicio = NotificacionesService.shared
        // Se envia enabled=false aun sin permiso o al desactivar la categoria,
        // para revocar un registro anterior. El token nunca se guarda en defaults.
        if disponibleEnVersion && activadas && servicio.preferencias.activadas && servicio.permitido && token == nil && !registrando {
            registrarConApple()
        }
        if forzar { firmaEnviada = nil }
        if firmaConfirmada != cuerpoBase() || fechaCobertura.map({ $0 <= Date() }) == true { registroConfirmado = false }
        let identidad = "\(config.host):\(config.port):\(config.username)"
        if endpoint != identidad || mqtt == nil {
            desconectar()
            endpoint = identidad
            conectar(config)
        } else if suscrito { enviarSiHaceFalta() }
    }

    private func registrarConApple() {
        registrando = true
        estado = .registrandoApple
        UIApplication.shared.registerForRemoteNotifications()
        registroTimeout?.cancel()
        registroTimeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, let self, self.registrando else { return }
            self.registrando = false
            self.estado = .errorApple
        }
    }

    func recibioToken(_ datos: Data) {
        guard !datos.isEmpty else { falloRegistro(); return }
        token = datos.map { String(format: "%02x", $0) }.joined()
        registrando = false
        registroTimeout?.cancel()
        sincronizar(forzar: true)
    }

    func falloRegistro() {
        registrando = false
        registroTimeout?.cancel()
        estado = .errorApple
        registroConfirmado = false
    }

    private func conectar(_ config: MQTTConfiguration) {
        principal = config.username
        let cliente = CocoaMQTT(clientID: "rutautp-push-\(UUID().uuidString)", host: config.host, port: config.port)
        cliente.username = config.username
        cliente.password = config.password
        cliente.delegateQueue = .main
        cliente.keepAlive = 30
        cliente.cleanSession = true
        cliente.autoReconnect = true
        cliente.enableSSL = true
        if !config.trustedCACertificates.isEmpty { cliente.trustedServerCertificates = config.trustedCACertificates }
        cliente.didConnectAck = { [weak self] cliente, ack in
            Task { @MainActor [weak self] in
                guard let self, self.enPrimerPlano, self.mqtt === cliente else { return }
                guard ack == .accept else { self.estado = .rechazado; return }
                cliente.subscribe("rutautp/notificaciones/\(self.principal)/recibo", qos: .qos1)
            }
        }
        cliente.didSubscribeTopics = { [weak self] cliente, exito, fallo in
            Task { @MainActor [weak self] in
                guard let self, self.mqtt === cliente else { return }
                self.suscrito = fallo.isEmpty && exito.count == 1
                if self.suscrito { self.enviarSiHaceFalta() }
                else { self.estado = .rechazado }
            }
        }
        cliente.didReceiveMessage = { [weak self] cliente, mensaje, _ in
            guard let json = mensaje.string, json.utf8.count <= 2048, let data = json.data(using: .utf8) else { return }
            let topic = mensaje.topic
            Task { @MainActor [weak self] in
                guard let self, self.mqtt === cliente, topic == "rutautp/notificaciones/\(self.principal)/recibo" else { return }
                self.recibir(data)
            }
        }
        cliente.didDisconnect = { [weak self] cliente, _ in
            Task { @MainActor [weak self] in
                guard let self, self.mqtt === cliente else { return }
                self.suscrito = false
                self.firmaEnviada = nil
                self.solicitud = nil
                self.timeout?.cancel()
                self.registroConfirmado = false
                self.estado = .pendiente
            }
        }
        mqtt = cliente
        estado = .sincronizando
        // Tambien vence si el broker nunca responde o rechaza la suscripcion.
        programarTimeout()
        _ = cliente.connect()
    }

    private func enviarSiHaceFalta() {
        guard enPrimerPlano, suscrito, let mqtt, let firma = cuerpoBase(),
              var body = (try? JSONSerialization.jsonObject(with: firma)) as? [String: Any] else { return }
        if firmaEnviada == firma, ultimoRegistro.map({ Date().timeIntervalSince($0) < 86400 }) == true { return }
        let defaults = UserDefaults.standard
        let anterior = defaults.object(forKey: Self.llaveRevision)
        let numero: Int
        if let anterior {
            guard let valor = anterior as? NSNumber, CFGetTypeID(valor) != CFBooleanGetTypeID(),
                  valor.doubleValue.isFinite, (0...9007199254740990).contains(valor.doubleValue),
                  valor.doubleValue == valor.doubleValue.rounded(.towardZero) else {
                datosInvalidos = true; estado = .rechazado; return
            }
            numero = valor.intValue
        } else {
            numero = 0
        }
        let revision = numero + 1
        let id = UUID()
        body["revision"] = revision
        body["requestID"] = id.uuidString
        body["timestamp"] = Date().timeIntervalSince1970
        guard let data = try? JSONSerialization.data(withJSONObject: body), data.count <= 32768,
              let json = String(data: data, encoding: .utf8) else { estado = .rechazado; return }
        defaults.set(revision, forKey: Self.llaveRevision)
        revisionEnviada = revision
        firmaEnviada = firma
        solicitud = id
        estado = .sincronizando
        mqtt.publish("rutautp/notificaciones/\(principal)/registro", withString: json, qos: .qos1, retained: false)
        programarTimeout()
    }

    private func programarTimeout() {
        timeout?.cancel()
        timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, let self else { return }
            self.estado = .pendiente
            self.registroConfirmado = false
            self.firmaEnviada = nil
            self.solicitud = nil
        }
    }

    private func recibir(_ data: Data) {
        guard let recibo = try? JSONDecoder().decode(ReciboPush.self, from: data),
              recibo.requestID == solicitud, recibo.revision == revisionEnviada else { return }
        timeout?.cancel()
        solicitud = nil
        guard recibo.accepted, recibo.leaseUntil.isFinite,
              recibo.leaseUntil > Date().timeIntervalSince1970,
              recibo.leaseUntil <= Date().addingTimeInterval(31 * 86400).timeIntervalSince1970 else {
            estado = .rechazado; registroConfirmado = false; firmaEnviada = nil; return
        }
        firmaConfirmada = firmaEnviada
        fechaCobertura = Date(timeIntervalSince1970: recibo.leaseUntil)
        UserDefaults.standard.set(fechaCobertura, forKey: Self.llaveCobertura)
        ultimoRegistro = Date()
        registroConfirmado = disponibleEnVersion && activadas && recibo.providerReady && token != nil && firmaConfirmada == cuerpoBase()
        if !disponibleEnVersion { estado = .versionSinPush }
        else if !recibo.providerReady { estado = .faltaProveedor }
        else if !activadas { estado = .desactivadas }
        else if !NotificacionesService.shared.permitido { estado = .faltaPermiso }
        else if token == nil { estado = registrando ? .registrandoApple : .errorApple }
        else { estado = .confirmado }
        if firmaConfirmada != cuerpoBase() { enviarSiHaceFalta() }
    }

    private func desconectar() {
        timeout?.cancel()
        mqtt?.autoReconnect = false
        mqtt?.disconnect()
        mqtt = nil
        endpoint = nil
        suscrito = false
        solicitud = nil
        firmaEnviada = nil
    }

    func permitePresentar(_ toque: ToqueCambioRuta) -> Bool {
        let vigente = toqueVigente(toque)
        return activadas && vigente
    }

    func toqueVigente(_ toque: ToqueCambioRuta) -> Bool {
        recargar()
        return !datosInvalidos && lineas.contains(toque.routeID) && toque.expiresAt > Date()
    }
}
