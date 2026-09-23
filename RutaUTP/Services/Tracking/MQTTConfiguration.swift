import Foundation
import Security

/// Configuración del canal MQTT, construida desde el Scheme de Xcode.
///
/// Las credenciales aprovisionadas se conservan en Keychain, separadas por
/// servidor, puerto y transporte. Nunca se leen del paquete de la app.
struct MQTTConfiguration {
    let host: String
    let port: UInt16
    let username: String
    let password: String

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
        trustedCACertificates: [SecCertificate] = []
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.useTLS = useTLS
        self.trustedCACertificates = trustedCACertificates
    }

    /// Variables reconocidas en el Scheme de Xcode:
    ///   MQTT_HOST, MQTT_USERNAME, MQTT_PASSWORD (obligatorias)
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
        let credentials: MQTTCredentials
        do {
            // No mezclar usuario de una fuente con contraseña de otra.
            if environment["MQTT_USERNAME"] != nil || environment["MQTT_PASSWORD"] != nil {
                guard let username = environment["MQTT_USERNAME"],
                      let password = environment["MQTT_PASSWORD"] else { return nil }
                credentials = MQTTCredentials(username: username, password: password)
                guard credentials.isValid else { return nil }
                try credentialStore?.save(credentials, endpoint: endpoint)
            } else if let stored = try credentialStore?.load(endpoint: endpoint) {
                credentials = stored
            } else {
                guard let credentialStore,
                      let username = defaults?.string(forKey: "MQTT_USERNAME"),
                      let password = defaults?.string(forKey: "MQTT_PASSWORD") else { return nil }
                credentials = MQTTCredentials(username: username, password: password)
                guard credentials.isValid else { return nil }
                try credentialStore.save(credentials, endpoint: endpoint)
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

        let caPath = resolveCertificatePath(
            valor("MQTT_CA_CERT") ?? "",
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

        return MQTTConfiguration(
            host: host,
            port: port,
            username: credentials.username,
            password: credentials.password,
            useTLS: useTLS,
            trustedCACertificates: trustedCA
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
