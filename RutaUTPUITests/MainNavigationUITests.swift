import XCTest
import CoreLocation

/// Usa la app real y toques de interfaz: las pruebas de modelos no detectan
/// una barra que conserva su estado pero deja de mostrar los botones.
final class MainNavigationUITests: XCTestCase {
    @MainActor
    func testElegirHuanchacoOcultaLaBarraSinReservarUnPieVacio() {
        continueAfterFailure = false
        let ubicacionAnterior = XCUIDevice.shared.location
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(
            latitude: -8.098247879173792, longitude: -79.03818104755645))
        defer { XCUIDevice.shared.location = ubicacionAnterior }
        let app = XCUIApplication()
        app.launchArguments = ["--pantalla", "mapa"]
        app.launch()
        permitirUbicacionSiSeSolicita()

        let navegacion = app.otherElements["main-navigation"]
        XCTAssertTrue(navegacion.waitForExistence(timeout: 5))
        let destino = app.buttons["Huanchaco"].firstMatch
        XCTAssertTrue(destino.waitForExistence(timeout: 5))
        destino.tap()

        let quitarRuta = app.buttons["Quitar ruta"]
        XCTAssertTrue(quitarRuta.waitForExistence(timeout: 45), "El cálculo inicial debe terminar y permitir quitar el destino")
        verificarMapaHastaElBorde(app)
        adjuntarCaptura(app, nombre: "Destino-Huanchaco-sin-pie")

        // Comprueba también el estado que antes montaba el TabView paginado
        // del resumen: su aparición no debe recuperar ninguna barra ni hueco.
        let alternativas = app.descendants(matching: .any)["route-options-carousel"]
        XCTAssertTrue(alternativas.waitForExistence(timeout: 10), "Huanchaco debe presentar el resumen de alternativas con el GPS cerca de UTP")
        verificarMapaHastaElBorde(app)
        adjuntarCaptura(app, nombre: "Alternativas-Huanchaco-sin-pie")

        // El reemplazo del paginador debe conservar los botones y el gesto
        // para cambiar de alternativa, sin recuperar el pie de navegación.
        let siguiente = app.buttons["Ruta siguiente"]
        XCTAssertTrue(siguiente.exists && siguiente.isEnabled)
        siguiente.tap()
        let segundaRuta = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Ruta 2 de ")).firstMatch
        XCTAssertTrue(segundaRuta.waitForExistence(timeout: 5))
        verificarMapaHastaElBorde(app)
        adjuntarCaptura(app, nombre: "Segunda-alternativa-Huanchaco-sin-pie")
        alternativas.swipeRight()
        let primeraRuta = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Ruta 1 de ")).firstMatch
        XCTAssertTrue(primeraRuta.waitForExistence(timeout: 5))
        verificarMapaHastaElBorde(app)

        quitarRuta.tap()
        let volverAlMapa = app.descendants(matching: .any)["main-navigation.mapa"]
        XCTAssertTrue(volverAlMapa.waitForExistence(timeout: 5))
        XCTAssertTrue(volverAlMapa.isHittable)
        XCTAssertEqual(app.otherElements.matching(identifier: "main-navigation").count, 1)
        XCTAssertEqual(app.tabBars.count, 0)
        adjuntarCaptura(app, nombre: "Mapa-tras-quitar-Huanchaco")
    }

    @MainActor
    private func verificarMapaHastaElBorde(_ app: XCUIApplication, archivo: StaticString = #filePath, linea: UInt = #line) {
        let expandido = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let mapa = app.maps.firstMatch
            guard mapa.exists, !app.otherElements["main-navigation"].exists,
                  app.tabBars.count == 0 else { return false }
            return abs(mapa.frame.maxY - app.windows.firstMatch.frame.maxY) <= 1
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expandido], timeout: 5), .completed,
                       "Al ocultarse la barra el mapa debe ocupar también su antigua fila", file: archivo, line: linea)
    }

    @MainActor
    private func adjuntarCaptura(_ app: XCUIApplication, nombre: String) {
        let captura = XCTAttachment(screenshot: app.screenshot())
        captura.name = nombre
        captura.lifetime = .keepAlways
        add(captura)
    }

    @MainActor
    private func permitirUbicacionSiSeSolicita() {
        let permiso = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if permiso.waitForExistence(timeout: 2) {
            let titulos = ["Allow While Using App", "Allow Once", "Permitir al usar la app",
                           "Permitir mientras se usa la app", "Permitir una vez"]
            let permitir = permiso.buttons.matching(NSPredicate(format: "label IN %@", titulos)).firstMatch
            if permitir.exists { permitir.tap() }
        }
    }

    @MainActor
    func testLosCincoIconosPermanecenVisiblesAlNavegar() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--pantalla", "mapa", "-isDarkMode", "YES"]
        app.launch()

        // Un simulador nuevo puede pedir ubicación antes del primer toque.
        let permiso = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if permiso.waitForExistence(timeout: 2) {
            let titulos = ["Allow While Using App", "Allow Once", "Permitir al usar la app",
                           "Permitir mientras se usa la app", "Permitir una vez"]
            let permitir = permiso.buttons.matching(NSPredicate(format: "label IN %@", titulos)).firstMatch
            if permitir.exists { permitir.tap() }
        }

        let pantallas = ["mapa", "rutas", "guardado", "seguridad", "perfil"]
        func verificarBarra() {
            XCTAssertEqual(app.otherElements.matching(identifier: "main-navigation").count, 1)
            XCTAssertEqual(app.tabBars.count, 0)
            for pantalla in pantallas {
                let boton = app.descendants(matching: .any)["main-navigation.\(pantalla)"]
                XCTAssertTrue(boton.exists || boton.waitForExistence(timeout: 5), "Falta \(pantalla)")
                XCTAssertTrue(boton.isHittable, "\(pantalla) debe verse y recibir toques")
                XCTAssertTrue(boton.images.firstMatch.exists, "Falta el icono de \(pantalla)")
            }
        }

        verificarBarra()
        var capturadas: Set<String> = []
        for pantalla in ["guardado", "seguridad", "mapa", "rutas", "perfil",
                         "guardado", "rutas", "mapa", "seguridad", "perfil", "mapa"] {
            app.descendants(matching: .any)["main-navigation.\(pantalla)"].tap()
            let seleccionado = app.descendants(matching: .any)["main-navigation.\(pantalla)"]
            let cambio = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: seleccionado)
            XCTAssertEqual(XCTWaiter.wait(for: [cambio], timeout: 5), .completed)
            verificarBarra()
            if capturadas.insert(pantalla).inserted {
                let captura = XCTAttachment(screenshot: app.screenshot())
                captura.name = "Navegacion-\(pantalla)"
                captura.lifetime = .keepAlways
                add(captura)
            }
        }

        app.buttons["Abrir menú"].tap()
        XCTAssertTrue(app.buttons["Cerrar menú"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["main-navigation"].exists)
        adjuntarCaptura(app, nombre: "Menu-oscuro-sin-franja")
        app.buttons["Cerrar menú"].tap()
        verificarBarra()

        app.descendants(matching: .any)["main-navigation.perfil"].tap()
        app.scrollViews.firstMatch.swipeUp()
        adjuntarCaptura(app, nombre: "Perfil-desplazado-sin-franja")
    }
}
