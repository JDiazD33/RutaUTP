//
//  MQTTConfigurationTests.swift
//  RutaUTPTests
//
//  Pruebas del análisis de variables de entorno del canal MQTT y de la
//  carga de la CA propia.
//
//  No abren conexiones: verifican el puerto por defecto, la detección de
//  TLS y la lectura del certificado de la CA desde disco.
//

import XCTest
import Security
@testable import RutaUTP

final class MQTTConfigurationTests: XCTestCase {

    // MARK: - Variables obligatorias

    func testSinHostNoConstruyeConfiguracion() {
        XCTAssertNil(
            MQTTConfiguration.from(environment: [
                "MQTT_USERNAME": "observer",
                "MQTT_PASSWORD": "secreto"
            ])
        )
    }

    func testSinUsuarioNoConstruyeConfiguracion() {
        XCTAssertNil(
            MQTTConfiguration.from(environment: [
                "MQTT_HOST": "mqtt.ejemplo.com",
                "MQTT_PASSWORD": "secreto"
            ])
        )
    }

    func testSinContrasenaNoConstruyeConfiguracion() {
        XCTAssertNil(
            MQTTConfiguration.from(environment: [
                "MQTT_HOST": "mqtt.ejemplo.com",
                "MQTT_USERNAME": "observer"
            ])
        )
    }

    func testValorVacioNoCuentaComoPresente() {
        XCTAssertNil(
            MQTTConfiguration.from(environment: [
                "MQTT_HOST": "",
                "MQTT_USERNAME": "observer",
                "MQTT_PASSWORD": "secreto"
            ])
        )
    }

    func testEntornoCompletoConstruyeConfiguracion() throws {
        let configuration = try XCTUnwrap(
            MQTTConfiguration.from(environment: baseEnvironment())
        )

        XCTAssertEqual(configuration.host, "mqtt.ejemplo.com")
        XCTAssertEqual(configuration.username, "observer")
        XCTAssertEqual(configuration.password, "secreto")
        XCTAssertFalse(configuration.useTLS)
        XCTAssertTrue(configuration.trustedCACertificates.isEmpty)
    }

    // MARK: - Puerto por defecto

    /// Sin TLS y sin puerto explícito se usa el 1883.
    func testPuertoPorDefectoEsElPlano() throws {
        let configuration = try XCTUnwrap(
            MQTTConfiguration.from(environment: baseEnvironment())
        )

        XCTAssertEqual(
            configuration.port,
            MQTTConfiguration.defaultPlainPort
        )
    }

    /// Activar TLS sin fijar el puerto debe llevar al 8883.
    ///
    /// Antes se quedaba en 1883: el cliente intentaba un handshake TLS
    /// contra el puerto plano y la conexión fallaba sin explicación.
    func testTLSImplicaElPuertoCifrado() throws {
        var environment = baseEnvironment()
        environment["MQTT_TLS"] = "1"

        let configuration = try XCTUnwrap(
            MQTTConfiguration.from(environment: environment)
        )

        XCTAssertTrue(configuration.useTLS)
        XCTAssertEqual(
            configuration.port,
            MQTTConfiguration.defaultTLSPort
        )
    }

    /// Un puerto explícito gana sobre el valor por defecto de TLS.
    func testPuertoExplicitoGanaSobreElDefecto() throws {
        var environment = baseEnvironment()
        environment["MQTT_TLS"] = "1"
        environment["MQTT_PORT"] = "1234"

        let configuration = try XCTUnwrap(
            MQTTConfiguration.from(environment: environment)
        )

        XCTAssertEqual(configuration.port, 1234)
    }

    /// Un puerto ilegible no debe romper la configuración.
    func testPuertoInvalidoCaeAlDefecto() throws {
        var environment = baseEnvironment()
        environment["MQTT_PORT"] = "no-es-un-puerto"

        let configuration = try XCTUnwrap(
            MQTTConfiguration.from(environment: environment)
        )

        XCTAssertEqual(
            configuration.port,
            MQTTConfiguration.defaultPlainPort
        )
    }

    /// Un puerto fuera del rango de 16 bits también cae al valor por defecto.
    func testPuertoFueraDeRangoCaeAlDefecto() throws {
        var environment = baseEnvironment()
        environment["MQTT_PORT"] = "70000"

        let configuration = try XCTUnwrap(
            MQTTConfiguration.from(environment: environment)
        )

        XCTAssertEqual(
            configuration.port,
            MQTTConfiguration.defaultPlainPort
        )
    }

    // MARK: - Detección de TLS

    func testReconoceLasVariantesDeTLS() {
        for valor in ["1", "true", "TRUE", "yes", "Yes"] {
            var environment = baseEnvironment()
            environment["MQTT_TLS"] = valor

            XCTAssertTrue(
                MQTTConfiguration.from(
                    environment: environment
                )?.useTLS == true,
                "«\(valor)» debería activar TLS"
            )
        }
    }

    func testNoActivaTLSSinMarcaExplicita() {
        for valor in ["0", "false", "no", "", "tal vez"] {
            var environment = baseEnvironment()
            environment["MQTT_TLS"] = valor

            XCTAssertFalse(
                MQTTConfiguration.from(
                    environment: environment
                )?.useTLS == true,
                "«\(valor)» no debería activar TLS"
            )
        }
    }

    // MARK: - CA propia

    func testSinRutaDeCANoConfiaEnCertificadosExtra() throws {
        let configuration = try XCTUnwrap(
            MQTTConfiguration.from(environment: baseEnvironment())
        )

        XCTAssertTrue(configuration.trustedCACertificates.isEmpty)
    }

    func testRutaDeCAInexistenteNoAportaCertificados() throws {
        var environment = baseEnvironment()
        environment["MQTT_CA_CERT"] = "/ruta/que/no/existe/ca.crt"

        let configuration = try XCTUnwrap(
            MQTTConfiguration.from(environment: environment)
        )

        // Fallar aquí no debe impedir construir la configuración: la
        // conexión fallará cerrada en el handshake.
        XCTAssertTrue(configuration.trustedCACertificates.isEmpty)
    }

    func testCargaLaCAEnFormatoPEM() throws {
        let url = try writeTemporary(
            Data(Self.testCAPEM.utf8),
            named: "ca.pem"
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let certificates = MQTTCertificateLoader.load(
            fromPath: url.path
        )

        XCTAssertEqual(certificates.count, 1)
    }

    func testCargaLaCAEnFormatoDER() throws {
        let base64 = try XCTUnwrap(
            MQTTCertificateLoader.pemBlocks(in: Self.testCAPEM).first
        )
        let der = try XCTUnwrap(Data(base64Encoded: base64))

        let url = try writeTemporary(der, named: "ca.der")
        defer { try? FileManager.default.removeItem(at: url) }

        let certificates = MQTTCertificateLoader.load(
            fromPath: url.path
        )

        XCTAssertEqual(certificates.count, 1)
    }

    func testContenidoQueNoEsCertificadoNoAportaNada() throws {
        let url = try writeTemporary(
            Data("esto no es un certificado".utf8),
            named: "basura.crt"
        )
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(
            MQTTCertificateLoader.load(fromPath: url.path).isEmpty
        )
    }

    /// Un bloque PEM sin su cierre se ignora en lugar de leerse a medias.
    func testBloquePEMSinCierreSeIgnora() {
        let texto = """
        -----BEGIN CERTIFICATE-----
        QUJD
        """

        XCTAssertTrue(
            MQTTCertificateLoader.pemBlocks(in: texto).isEmpty
        )
    }

    /// El base64 partido en varias líneas se recompone en un solo bloque.
    func testRecomponeElBase64PartidoEnVariasLineas() {
        let texto = """
        -----BEGIN CERTIFICATE-----
        QUJD
        REVG
        -----END CERTIFICATE-----
        """

        XCTAssertEqual(
            MQTTCertificateLoader.pemBlocks(in: texto),
            ["QUJDREVG"]
        )
    }

    /// Un archivo PEM con dos certificados produce dos entradas.
    func testLeeVariosCertificadosDelMismoArchivo() {
        let texto = Self.testCAPEM + "\n" + Self.testCAPEM

        XCTAssertEqual(
            MQTTCertificateLoader.pemBlocks(in: texto).count,
            2
        )
    }

    // MARK: - Apoyo

    private func baseEnvironment() -> [String: String] {
        [
            "MQTT_HOST": "mqtt.ejemplo.com",
            "MQTT_USERNAME": "observer",
            "MQTT_PASSWORD": "secreto"
        ]
    }

    private func writeTemporary(
        _ data: Data,
        named name: String
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "rutautp-tests-\(UUID().uuidString)-\(name)"
            )

        try data.write(to: url)
        return url
    }

    /// CA autofirmada de prueba, generada con:
    /// `openssl req -x509 -newkey rsa:2048 -nodes -days 3650
    ///  -keyout ca.key -out ca.crt -subj "/CN=RutaUTP Test CA"`
    ///
    /// No protege nada: existe solo para comprobar que el archivo se lee.
    private static let testCAPEM = """
    -----BEGIN CERTIFICATE-----
    MIIDFTCCAf2gAwIBAgIUUuE7zlmikQciMnMQvqCBgDYp66EwDQYJKoZIhvcNAQEL
    BQAwGjEYMBYGA1UEAwwPUnV0YVVUUCBUZXN0IENBMB4XDTI2MDkxOTE0MDMyMloX
    DTM2MDkxNjE0MDMyMlowGjEYMBYGA1UEAwwPUnV0YVVUUCBUZXN0IENBMIIBIjAN
    BgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvqKN/jE9IUOWH+z2P4qVHc/EejlS
    fH8Mu7i+0/UIacvciG3JweXANfTZDxizTlmuG9bQY21HwrtTXXH0U1A9UKdA9i0Y
    6wLQ1X3WCzobMpA9lqlXLVAJh3TDJBILKcesXs5FhGMPjYo5aPedaUNzaD9+s9Ev
    Re2EqLTmBH7H4leI/PyDApdE8VH8jQI2ry0b4FCHTy+gBOgblFxHQwzsNMLN9yAI
    DkboWTPFhnRIbtwlkRKPG6Pw0QQ3tYgzVyGmZb5f7lpJVs/0fec6iLQSOFAoHlub
    s437eq8hGTDOTuY5dtCK+zMwEgLENTtoBlaq4KWNVVEUzHaL0CuPUUOsRQIDAQAB
    o1MwUTAdBgNVHQ4EFgQUP5IuFLMqjrjZrnb2NDnGfFlneGIwHwYDVR0jBBgwFoAU
    P5IuFLMqjrjZrnb2NDnGfFlneGIwDwYDVR0TAQH/BAUwAwEB/zANBgkqhkiG9w0B
    AQsFAAOCAQEAosf28WlPdJUPlMKXCCkY/NN2cN/Zy9gVPuWK1d3NeTbxoVJ9c0Ez
    o3KuTQlWpzhI5c+A6KdJLCHzf8JgvVuxto2OSUQlsFTTnxY2dwFUg1yOMZeugmg5
    6m9ZHikJpg/iTob32oZW7GRxOqdVvfBTPkVpK8BzNHcvq8lz6X/fKdFn3eoncu9B
    uXT9gABYbtXH7JhPzQcRN1So3Zp5LWRRR8i6oh0yqTvhcgu4SSMFc0ha9mHcgDN5
    /1rJK4+KE3hBiYFmdK3X31nBzWRAzmU+wNkZj8A3c3lfdtY7zNrvHMcVAIcdGOHU
    VT6pyd7QqKBK0R7Y87oGD1/IuGG6Rj2Feg==
    -----END CERTIFICATE-----
    """
}
