import XCTest
import CoreLocation

/// Usa la app real y toques de interfaz: las pruebas de modelos no detectan
/// una barra que conserva su estado pero deja de mostrar los botones.
final class MainNavigationUITests: XCTestCase {
    @MainActor
    func testSelectorLugarConservaLaFlechaAlCentrarYVerLaCiudad() {
        continueAfterFailure = false
        let ubicacionAnterior = XCUIDevice.shared.location
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(
            latitude: -8.098247879173792, longitude: -79.03818104755645))
        defer { XCUIDevice.shared.location = ubicacionAnterior }
        let app = XCUIApplication()
        app.launchArguments = ["--pantalla", "guardado", "--idioma", "es"]
        app.launch()
        permitirUbicacionSiSeSolicita()

        let anadir = app.buttons["Añadir lugar guardado"]
        XCTAssertTrue(anadir.waitForExistence(timeout: 10))
        anadir.tap()
        permitirUbicacionSiSeSolicita()
        let ampliar = app.buttons["place-picker.expand"]
        XCTAssertTrue(ampliar.waitForExistence(timeout: 10))
        XCTAssertTrue(ampliar.isHittable)
        XCTAssertLessThanOrEqual(ampliar.frame.width, 44.5)
        XCTAssertFalse(app.buttons["place-picker.my-location"].exists)
        XCTAssertFalse(app.buttons["place-picker.city"].exists)
        adjuntarCaptura(app, nombre: "Lugar-mapa-pequeno-solo-ampliar")
        ampliar.tap()

        let flecha = app.buttons["place-picker.my-location"]
        let ciudad = app.buttons["place-picker.city"]
        XCTAssertTrue(flecha.waitForExistence(timeout: 10))
        XCTAssertTrue(ciudad.exists && ciudad.isHittable)
        XCTAssertTrue(flecha.isHittable && flecha.isEnabled)
        XCTAssertEqual(flecha.frame.midY, ciudad.frame.midY, accuracy: 1)
        XCTAssertLessThan(flecha.frame.maxX, ciudad.frame.minX)
        XCTAssertGreaterThan(flecha.frame.minY, app.buttons["Cerrar"].frame.maxY + 4,
                             "Los controles deben quedar debajo de la cabecera sin tapar Cerrar")
        XCTAssertFalse(ampliar.isHittable)

        let mapa = app.descendants(matching: .any)["place-picker.full-map"].firstMatch
        XCTAssertTrue(mapa.waitForExistence(timeout: 5))
        mapa.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.55)).tap()
        let pinListo = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (mapa.value as? String)?.contains("Latitud") == true
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [pinListo], timeout: 5), .completed)
        let pinElegido = mapa.value as? String

        // Alternar vista general y seguimiento verifica el target/action real
        // y las respuestas de MapKit, sin modificar el punto elegido.
        for _ in 0..<2 {
            ciudad.tap()
            let vistaCiudad = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == false"), object: flecha)
            XCTAssertEqual(XCTWaiter.wait(for: [vistaCiudad], timeout: 5), .completed)
            XCTAssertTrue(flecha.exists && flecha.isHittable && flecha.isEnabled)
            flecha.tap()
            let seguimiento = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: flecha)
            XCTAssertEqual(XCTWaiter.wait(for: [seguimiento], timeout: 10), .completed)
            XCTAssertEqual(mapa.value as? String, pinElegido)
        }
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(
            latitude: -8.1002, longitude: -79.0361))
        let desaparece = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !flecha.exists || !flecha.isHittable || !flecha.isEnabled
        }, object: nil)
        desaparece.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [desaparece], timeout: 3), .completed,
                       "La flecha debe seguir visible y recibir toques tras actualizar el GPS")
        adjuntarCaptura(app, nombre: "Lugar-flecha-y-ciudad-tras-centrar")
        app.buttons["Cerrar"].tap()
        XCTAssertTrue(ampliar.waitForExistence(timeout: 5))
        XCTAssertFalse(flecha.exists)
        XCTAssertFalse(ciudad.exists)
    }

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
    private func verificarNavegacionBloqueadaPorElMenu(_ app: XCUIApplication) {
        // La fila se conserva para no redimensionar el mapa. Su contenedor
        // puede existir en XCTest aunque sus controles estén ocultos/inactivos.
        XCTAssertEqual(app.tabBars.count, 0)
        for pantalla in ["mapa", "rutas", "guardado", "seguridad", "perfil"] {
            let boton = app.descendants(matching: .any)["main-navigation.\(pantalla)"]
            if boton.exists { XCTAssertFalse(boton.isHittable, "El menú debe bloquear \(pantalla)") }
        }
    }

    @MainActor
    func testMenuPermiteLosTresCierresSinCambiarElMapa() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--pantalla", "mapa", "-isDarkMode", "YES"]
        app.launch()
        permitirUbicacionSiSeSolicita()

        let abrir = app.buttons["Abrir menú"]
        let ubicacion = app.buttons["Centrar en mi ubicación"]
        XCTAssertTrue(abrir.waitForExistence(timeout: 5))
        XCTAssertTrue(ubicacion.waitForExistence(timeout: 5))
        // El foco puede ampliar el rectángulo accesible hasta toda la cabecera.
        // Volver a tocar el mismo punto visible comprueba que el icono no se mueve.
        let puntoMenu = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: abrir.frame.midX, dy: abrir.frame.midY))
        let mapaInicial = app.maps.firstMatch.frame
        adjuntarCaptura(app, nombre: "Mapa-antes-del-menu")

        for cierre in 0..<3 {
            puntoMenu.tap()
            let cerrar = app.buttons["Cerrar menú"]
            XCTAssertTrue(cerrar.waitForExistence(timeout: 5))
            let menuVisible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                cerrar.exists && cerrar.isHittable
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [menuVisible], timeout: 5), .completed)
            verificarNavegacionBloqueadaPorElMenu(app)
            if cierre == 0 { adjuntarCaptura(app, nombre: "Menu-sobre-mapa-inmovil") }
            switch cierre {
            case 0: cerrar.tap()
            // Tocar donde queda Perfil bajo el fondo debe cerrar el menú,
            // conservando Mapa, sin activar la navegación que hay debajo.
            case 1: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.95)).tap()
            default: app.staticTexts["Menú principal"].swipeLeft()
            }
            XCTAssertTrue(abrir.waitForExistence(timeout: 5))
            XCTAssertTrue(ubicacion.isHittable)
            XCTAssertTrue(app.descendants(matching: .any)["main-navigation.mapa"].isSelected)
            let actual = app.maps.firstMatch.frame
            let inicial = mapaInicial
            XCTAssertEqual(actual.minX, inicial.minX, accuracy: 1)
            XCTAssertEqual(actual.minY, inicial.minY, accuracy: 1)
            XCTAssertEqual(actual.width, inicial.width, accuracy: 1)
            XCTAssertEqual(actual.height, inicial.height, accuracy: 1)
        }
        adjuntarCaptura(app, nombre: "Mapa-tras-cerrar-menu")
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
        verificarNavegacionBloqueadaPorElMenu(app)
        adjuntarCaptura(app, nombre: "Menu-oscuro-sin-franja")
        app.buttons["Cerrar menú"].tap()
        verificarBarra()

        app.descendants(matching: .any)["main-navigation.perfil"].tap()
        app.scrollViews.firstMatch.swipeUp()
        adjuntarCaptura(app, nombre: "Perfil-desplazado-sin-franja")
    }
}
