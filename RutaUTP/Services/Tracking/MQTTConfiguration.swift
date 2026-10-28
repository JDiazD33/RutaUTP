import Foundation
import Security

/// Configuración MQTT: aprovisionamiento desde Xcode y reapertura autónoma.
///
/// Las credenciales aprovisionadas se conservan en Keychain, separadas por
/// servidor, puerto y transporte. Nunca se leen del paquete de la app.
struct MQTTConfiguration {
    let host: String
    let port: UInt16
    let username: String
    let password: String
    /// Cuenta aprovisionada para presentar el mapa sin publicar aportes.
    let isReadOnly: Bool

    /// Cifrado TLS. Sin TLS las credenciales y las ubicaciones viajan en
    /// texto plano por la red, así que cualquier despliegue accesible
    /// desde internet debe activarlo.
    let useTLS: Bool

    /// Certificados de una CA propia en los que confiar.
    ///
    /// Mosquitto con certificado autofirmado no está en el almacén del
    /// sistema, así que sin esto el handshake TLS falla. Se declaran aquí
    /// en lugar de desactivar la validación: siguen verificándose la
    /// cadena, el nombre del servidor y la vigencia.
    let trustedCACertificates: [SecCertificate]

    /// Puerto por defecto cuando el canal viaja sin cifrar.
    static let defaultPlainPort: UInt16 = 1883

    /// Puerto por defecto cuando se activa TLS.
    static let defaultTLSPort: UInt16 = 8883

    init(
        host: String,
        port: UInt16,
        username: String,
        password: String,
        useTLS: Bool = false,
        trustedCACertificates: [SecCertificate] = [],
        isReadOnly: Bool = false
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.isReadOnly = isReadOnly
        self.useTLS = useTLS
        self.trustedCACertificates = trustedCACertificates
    }

    /// Variables reconocidas en el Scheme de Xcode:
    ///   MQTT_USERNAME, MQTT_PASSWORD (pareja para aprovisionar cada iPhone)
    ///   MQTT_HOST (opcional si el servidor ya está incluido en Info.plist)
    ///   MQTT_PORT (opcional; por defecto 1883, o 8883 si MQTT_TLS=1)
    ///   MQTT_TLS (opcional, "1"/"true"/"yes" habilita TLS)
    ///   MQTT_CA_CERT (opcional, ruta a la CA propia en PEM o DER)
    ///
    /// Host, puerto, TLS y CA: entorno, UserDefaults y finalmente Info.plist.
    /// Credenciales: pareja completa del entorno, Keychain o migración de
    /// UserDefaults. La migración solo borra el original tras guardarlo.
    /// Cada instalación debe recibir una cuenta propia registrada en el broker.
    static func fromEnvironment() -> MQTTConfiguration? {
        from(
            environment: ProcessInfo.processInfo.environment,
            defaults: .standard,
            bundle: .main,
            credentialStore: MQTTKeychainStore()
        )
    }

    /// Ensayo deliberado desde devicectl: cuenta lectora efímera, sin persistir
    /// servidor/secretos ni recuperar la configuración habitual si falta algo.
    static var isReadOnlyTrial: Bool {
        ProcessInfo.processInfo.environment["RUTAUTP_S10_TRIAL"] != nil
    }

    static func contributionFromEnvironment() -> MQTTConfiguration? {
        contributionFrom(environment: ProcessInfo.processInfo.environment,
                         defaults: .standard, bundle: .main, credentialStore: MQTTKeychainStore())
    }

    /// El lector de presentación no reemplaza la cuenta propia del teléfono.
    /// Reutilizar únicamente la credencial habitual del MISMO endpoint: no
    /// enviar ubicaciones con el lector ni a un destino anterior diferente.
    static func contributionFrom(environment: [String: String], defaults: UserDefaults,
                                 bundle: Bundle? = nil, credentialStore: MQTTCredentialStoring) -> MQTTConfiguration? {
        guard environment["RUTAUTP_S10_TRIAL"] == nil,
              let receiver = from(environment: environment, defaults: defaults,
                                  bundle: bundle, credentialStore: credentialStore) else { return nil }
        guard receiver.isReadOnly else { return receiver }
        let endpoint = "\(receiver.useTLS ? "mqtts" : "mqtt")://\(receiver.host.lowercased()):\(receiver.port)"
        let credentials: MQTTCredentials
        do {
            if environment["MQTT_CONTRIBUTION_USERNAME"] != nil || environment["MQTT_CONTRIBUTION_PASSWORD"] != nil {
                guard let username = environment["MQTT_CONTRIBUTION_USERNAME"],
                      let password = environment["MQTT_CONTRIBUTION_PASSWORD"] else { return nil }
                credentials = MQTTCredentials(username: username, password: password)
            } else {
                guard let stored = try credentialStore.load(endpoint: endpoint) else { return nil }
                credentials = stored
            }
        } catch { return nil }
        guard credentials.isValid,
              credentials.username != receiver.username,
              !["backend", "observer", "presentation-reader"].contains(credentials.username),
              !credentials.username.hasPrefix("sim-") else { return nil }
        if environment["MQTT_CONTRIBUTION_USERNAME"] != nil {
            do { try credentialStore.save(credentials, endpoint: endpoint) }
            catch { return nil }
        }
        return MQTTConfiguration(host: receiver.host, port: receiver.port,
                                 username: credentials.username, password: credentials.password,
                                 useTLS: receiver.useTLS, trustedCACertificates: receiver.trustedCACertificates)
    }

    /// Solo cantidades y tiempos del ensayo; nunca payloads o credenciales.
    static func trialLog(_ event: String, _ counts: [String: Int]) {
        let environment = ProcessInfo.processInfo.environment
        guard environment["RUTAUTP_S10_TRIAL"] == "1"
            || environment["RUTAUTP_PRESENTATION_DIAGNOSTICS"] == "1" else { return }
        let body: [String: Any] = ["event": event, "counts": counts,
            "wall": Date().timeIntervalSince1970, "uptime": ProcessInfo.processInfo.systemUptime]
        if let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]),
           let line = String(data: data, encoding: .utf8) { print("[S10] " + line) }
    }

    /// Variante que recibe el entorno ya resuelto.
    ///
    /// Permite probar el análisis de variables, el orden de precedencia y el
    /// puerto por defecto sin depender de `ProcessInfo`, que es estado global
    /// del proceso.
    static func from(
        environment: [String: String],
        defaults: UserDefaults? = nil,
        bundle: Bundle? = nil,
        credentialStore: MQTTCredentialStoring? = nil
    ) -> MQTTConfiguration? {
        if let trial = environment["RUTAUTP_S10_TRIAL"] {
            guard trial == "1",
                  ["MQTT_HOST", "MQTT_PORT", "MQTT_TLS", "MQTT_USERNAME", "MQTT_PASSWORD"]
                    .allSatisfy({ !(environment[$0] ?? "").isEmpty }),
                  ["0", "1"].contains(environment["MQTT_TLS"] ?? "") else { return nil }
            var ephemeral = environment
            ephemeral.removeValue(forKey: "RUTAUTP_S10_TRIAL")
            ephemeral.removeValue(forKey: "MQTT_PRESENTATION_MODE")
            return from(environment: ephemeral)
        }
        // Aprovisionamiento explícito una sola vez; nunca guardar secretos en
        // preferencias. La selección lectora pertenece a endpoint + cuenta.
        let presentation = environment["MQTT_PRESENTATION_MODE"]
        if let presentation {
            guard ["0", "1"].contains(presentation) else { return nil }
            if presentation == "1" {
                guard defaults != nil, credentialStore != nil,
                      ["MQTT_HOST", "MQTT_PORT", "MQTT_TLS", "MQTT_USERNAME", "MQTT_PASSWORD"]
                        .allSatisfy({ !(environment[$0] ?? "").isEmpty }),
                      ["0", "1"].contains(environment["MQTT_TLS"] ?? "") else { return nil }
            }
        }
        let destinationKeys = ["MQTT_HOST", "MQTT_PORT", "MQTT_TLS", "MQTT_CA_CERT"]
        let previousDestination = defaults?.dictionary(forKey: "MQTT_PRESENTATION_PREVIOUS_DESTINATION") as? [String: String]
        if presentation == "0", let defaults {
            if let previousDestination {
                for key in destinationKeys {
                    if let value = previousDestination[key] { defaults.set(value, forKey: key) }
                    else { defaults.removeObject(forKey: key) }
                }
            }
            for key in ["MQTT_PRESENTATION_ENDPOINT", "MQTT_PRESENTATION_USERNAME", "MQTT_PRESENTATION_PREVIOUS_DESTINATION"] {
                defaults.removeObject(forKey: key)
            }
        }
        func valor(_ clave: String) -> String? {
            let candidatos: [String?] = [
                environment[clave],
                defaults?.string(forKey: clave),
                bundle?.object(forInfoDictionaryKey: clave) as? String
            ]

            return candidatos
                .compactMap { $0 }
                .first { !$0.isEmpty }
        }

        guard let host = valor("MQTT_HOST") else { return nil }

        let tlsFlags = ["1", "true", "yes"]

        let useTLS = tlsFlags.contains(
            (valor("MQTT_TLS") ?? "").lowercased()
        )

        // TLS implica 8883. Exigir además MQTT_PORT era una trampa: activar
        // MQTT_TLS sin fijar el puerto intentaba TLS contra 1883 y fallaba.
        let fallbackPort = useTLS
            ? defaultTLSPort
            : defaultPlainPort

        let port: UInt16
        if let configuredPort = valor("MQTT_PORT") {
            // Un error explícito no debe redirigir la conexión a otro puerto.
            guard let parsedPort = UInt16(configuredPort), parsedPort > 0 else {
                return nil
            }
            port = parsedPort
        } else {
            port = fallbackPort
        }

        let endpoint = "\(useTLS ? "mqtts" : "mqtt")://\(host.lowercased()):\(port)"
        let hasEnvironmentCredentials = environment["MQTT_USERNAME"] != nil || environment["MQTT_PASSWORD"] != nil
        let presentationCredentials = presentation == "1" || (presentation == nil
            && !hasEnvironmentCredentials && defaults?.string(forKey: "MQTT_PRESENTATION_ENDPOINT") == endpoint)
        // La cuenta lectora usa otra entrada: conservar la credencial habitual
        // incluso cuando ambos roles pertenecen al mismo broker.
        let credentialEndpoint = presentationCredentials ? endpoint + "#presentation" : endpoint
        let credentials: MQTTCredentials
        do {
            // No mezclar usuario de una fuente con contraseña de otra.
            if environment["MQTT_USERNAME"] != nil || environment["MQTT_PASSWORD"] != nil {
                guard let username = environment["MQTT_USERNAME"],
                      let password = environment["MQTT_PASSWORD"] else { return nil }
                credentials = MQTTCredentials(username: username, password: password)
                guard credentials.isValid else { return nil }
                try credentialStore?.save(credentials, endpoint: credentialEndpoint)
            } else if let stored = try credentialStore?.load(endpoint: credentialEndpoint) {
                credentials = stored
            } else {
                guard let credentialStore,
                      let username = defaults?.string(forKey: "MQTT_USERNAME"),
                      let password = defaults?.string(forKey: "MQTT_PASSWORD") else { return nil }
                credentials = MQTTCredentials(username: username, password: password)
                guard credentials.isValid else { return nil }
                try credentialStore.save(credentials, endpoint: credentialEndpoint)
            }
            guard credentials.isValid else { return nil }
            if credentialStore != nil,
               defaults?.string(forKey: "MQTT_USERNAME") == credentials.username,
               defaults?.string(forKey: "MQTT_PASSWORD") == credentials.password {
                defaults?.removeObject(forKey: "MQTT_USERNAME")
                defaults?.removeObject(forKey: "MQTT_PASSWORD")
            }
        } catch {
            // Keychain bloqueado o escritura fallida: no conectar con secretos
            // alternativos ni eliminar los datos pendientes de migración.
            return nil
        }

        let configuredCA = valor("MQTT_CA_CERT") ?? ""
        let caPath = resolveCertificatePath(
            configuredCA,
            bundle: bundle
        )

        let trustedCA = caPath.isEmpty
            ? []
            : MQTTCertificateLoader.load(fromPath: caPath)

        #if DEBUG
        if !caPath.isEmpty && trustedCA.isEmpty {
            print(
                "[MQTTConfiguration] No se pudo cargar la CA en " +
                "\(caPath); el handshake TLS fallará si el servidor " +
                "usa un certificado autofirmado"
            )
        }
        #endif

        // Solo recordar el destino después de resolver/guardar sus credenciales.
        // Así, un fallo de Keychain no reemplaza la conexión anterior. Se guarda
        // el nombre relativo de la CA, no la ruta variable del paquete instalado.
        if credentialStore != nil, let defaults {
            if presentation == "1", previousDestination == nil {
                let previous = Dictionary(uniqueKeysWithValues: destinationKeys.compactMap { key in
                    defaults.string(forKey: key).map { (key, $0) }
                })
                defaults.set(previous, forKey: "MQTT_PRESENTATION_PREVIOUS_DESTINATION")
            }
            defaults.set(host, forKey: "MQTT_HOST")
            defaults.set(String(port), forKey: "MQTT_PORT")
            defaults.set(useTLS ? "1" : "0", forKey: "MQTT_TLS")
            defaults.set(configuredCA, forKey: "MQTT_CA_CERT")
            if presentation == "1" {
                defaults.set(endpoint, forKey: "MQTT_PRESENTATION_ENDPOINT")
                defaults.set(credentials.username, forKey: "MQTT_PRESENTATION_USERNAME")
            } else if presentation == "0" || hasEnvironmentCredentials {
                defaults.removeObject(forKey: "MQTT_PRESENTATION_ENDPOINT")
                defaults.removeObject(forKey: "MQTT_PRESENTATION_USERNAME")
                defaults.removeObject(forKey: "MQTT_PRESENTATION_PREVIOUS_DESTINATION")
            }
        }

        let isReadOnly = presentationCredentials && defaults?.string(forKey: "MQTT_PRESENTATION_ENDPOINT") == endpoint
            && defaults?.string(forKey: "MQTT_PRESENTATION_USERNAME") == credentials.username

        return MQTTConfiguration(
            host: host,
            port: port,
            username: credentials.username,
            password: credentials.password,
            useTLS: useTLS,
            trustedCACertificates: trustedCA,
            isReadOnly: isReadOnly
        )
    }

    /// Resuelve la ruta del certificado de la CA.
    ///
    /// Una ruta absoluta se usa tal cual. Una relativa se busca dentro del
    /// paquete de la app: en una instalación distribuida el certificado viaja
    /// con el binario y no tiene sentido exigir una ruta absoluta del sistema
    /// de archivos, que además cambia en cada instalación.
    private static func resolveCertificatePath(
        _ value: String,
        bundle: Bundle?
    ) -> String {
        if value.isEmpty || value.hasPrefix("/") {
            return value
        }

        guard let bundle else {
            return value
        }

        let nombre = (value as NSString).deletingPathExtension
        let extension_ = (value as NSString).pathExtension

        return bundle.path(
            forResource: nombre,
            ofType: extension_.isEmpty ? nil : extension_
        ) ?? value
    }
}

struct MQTTCredentials: Codable, Equatable {
    let username: String
    let password: String

    var isValid: Bool {
        !username.isEmpty && !password.isEmpty && username.count <= 128 &&
        username.rangeOfCharacter(from: CharacterSet(charactersIn: "/+#\0")) == nil
    }
}

protocol MQTTCredentialStoring {
    func load(endpoint: String) throws -> MQTTCredentials?
    func save(_ credentials: MQTTCredentials, endpoint: String) throws
}

struct MQTTKeychainStore: MQTTCredentialStoring {
    private struct KeychainError: Error { let status: OSStatus }

    private func query(endpoint: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "RutaUTP.MQTT.credentials",
         kSecAttrAccount as String: endpoint,
         kSecAttrSynchronizable as String: false]
    }

    func load(endpoint: String) throws -> MQTTCredentials? {
        var request = query(endpoint: endpoint)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        guard let data = result as? Data else { throw KeychainError(status: errSecDecode) }
        return try JSONDecoder().decode(MQTTCredentials.self, from: data)
    }

    func save(_ credentials: MQTTCredentials, endpoint: String) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: try JSONEncoder().encode(credentials),
            // No se sincroniza ni migra a otro dispositivo mediante backups.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let request = query(endpoint: endpoint)
        var status = SecItemUpdate(request as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(request.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }
}

/// Carga certificados de una CA propia desde disco.
///
/// Acepta PEM (lo que produce `openssl req -x509 ... -out ca.crt`) y DER.
/// Se mantiene aparte de la configuración para poder probarlo con archivos
/// controlados, sin abrir conexiones.
enum MQTTCertificateLoader {

    /// Devuelve los certificados legibles del archivo indicado.
    ///
    /// Un archivo ilegible o mal formado produce una lista vacía: el
    /// llamador sigue funcionando, y la conexión falla en el handshake si
    /// el servidor no está en el almacén del sistema. Es decir, falla
    /// cerrado.
    static func load(fromPath path: String) -> [SecCertificate] {
        guard let data = FileManager.default.contents(atPath: path) else {
            return []
        }

        return certificates(from: data)
    }

    /// Interpreta los datos como PEM y, si no hay bloques, como DER.
    static func certificates(from data: Data) -> [SecCertificate] {
        let fromPEM = pemCertificates(from: data)

        if !fromPEM.isEmpty {
            return fromPEM
        }

        if let der = SecCertificateCreateWithData(
            nil,
            data as CFData
        ) {
            return [der]
        }

        return []
    }

    /// Extrae los bloques `BEGIN/END CERTIFICATE` de un archivo PEM.
    ///
    /// El contenido base64 puede venir partido en varias líneas, como
    /// hace `openssl` por defecto.
    static func pemCertificates(from data: Data) -> [SecCertificate] {
        guard let text = String(data: data, encoding: .utf8) else {
            return []
        }

        return pemBlocks(in: text).compactMap { base64 in
            guard let der = Data(base64Encoded: base64) else {
                return nil
            }

            return SecCertificateCreateWithData(nil, der as CFData)
        }
    }

    /// Aísla el base64 de cada bloque de certificado.
    ///
    /// Separado del resto para poder verificar el encuadre del PEM sin
    /// necesitar un certificado real.
    static func pemBlocks(in text: String) -> [String] {
        let apertura = "-----BEGIN CERTIFICATE-----"
        let cierre = "-----END CERTIFICATE-----"

        var bloques: [String] = []

        for fragmento in text.components(separatedBy: apertura).dropFirst() {
            guard let fin = fragmento.range(of: cierre) else {
                continue
            }

            let base64 = fragmento[..<fin.lowerBound]
                .components(separatedBy: .whitespacesAndNewlines)
                .joined()

            if !base64.isEmpty {
                bloques.append(base64)
            }
        }

        return bloques
    }
}
