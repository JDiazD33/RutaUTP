import Foundation
import Security

/// Configuración del canal MQTT, construida desde el Scheme de Xcode.
///
/// Ninguna credencial vive en el repositorio: host, usuario, contraseña y
/// la ruta al certificado de la CA se leen de variables de entorno.
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
    static func fromEnvironment() -> MQTTConfiguration? {
        from(environment: ProcessInfo.processInfo.environment)
    }

    /// Variante que recibe el entorno ya resuelto.
    ///
    /// Permite probar el análisis de variables y el puerto por defecto sin
    /// depender de `ProcessInfo`, que es estado global del proceso.
    static func from(
        environment: [String: String]
    ) -> MQTTConfiguration? {
        guard
            let host = environment["MQTT_HOST"],
            !host.isEmpty,
            let username = environment["MQTT_USERNAME"],
            !username.isEmpty,
            let password = environment["MQTT_PASSWORD"],
            !password.isEmpty
        else {
            return nil
        }

        let tlsFlags = ["1", "true", "yes"]

        let useTLS = tlsFlags.contains(
            (environment["MQTT_TLS"] ?? "").lowercased()
        )

        // TLS implica 8883. Exigir además MQTT_PORT era una trampa: activar
        // MQTT_TLS sin fijar el puerto intentaba TLS contra 1883 y fallaba.
        let fallbackPort = useTLS
            ? defaultTLSPort
            : defaultPlainPort

        let port = environment["MQTT_PORT"]
            .flatMap { UInt16($0) } ?? fallbackPort

        let caPath = environment["MQTT_CA_CERT"] ?? ""

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
            username: username,
            password: password,
            useTLS: useTLS,
            trustedCACertificates: trustedCA
        )
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
