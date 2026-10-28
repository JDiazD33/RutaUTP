import XCTest
import UIKit

/// Toca los controles reales y comprueba el modelo confirmado por RealityKit,
/// no solo el texto de la opcion que SwiftUI tiene seleccionada.
final class Transportes3DUITests: XCTestCase {
    @MainActor
    func testLasSeisCombinacionesCarganAlPrimerToque() {
        let app = abrirApp()
        abrirGaleria(app)
        for (tipo, variante) in [("Micro", "Detallado"), ("Combi", "Detallado"),
                                 ("Colectivo", "Detallado"), ("Colectivo", "Original"),
                                 ("Combi", "Original"), ("Micro", "Original")] {
            elegirTipo(tipo, en: app)
            elegirVariante(variante, en: app)
            esperarModelo(tipo, variante, en: app)
            captura(modelo(app), nombre: tipo + "-" + variante)
        }
    }

    @MainActor
    func testCambiosRepetidosYCierreDuranteLaCargaConservanLaUltimaOpcion() {
        let app = abrirApp()
        abrirGaleria(app)
        elegirVariante("Original", en: app)
        esperarModelo("Micro", "Original", en: app)
        for tipo in ["Combi", "Colectivo", "Micro", "Colectivo", "Combi", "Micro"] {
            elegirTipo(tipo, en: app)
            elegirVariante("Detallado", en: app)
            elegirVariante("Original", en: app)
            elegirVariante("Detallado", en: app)
            esperarModelo(tipo, "Detallado", en: app)
        }
        elegirTipo("Colectivo", en: app)
        elegirVariante("Original", en: app)
        elegirVariante("Detallado", en: app)
        app.buttons["Cerrar"].tap()
        abrirGaleria(app)
        esperarModelo("Micro", "Detallado", en: app)
        XCUIDevice.shared.press(.home)
        app.activate()
        esperarModelo("Micro", "Detallado", en: app)
        captura(modelo(app), nombre: "Ultima-opcion-tras-reabrir")
    }

    @MainActor
    func testGiroZoomYRestablecerRespondenConCambiosEnElModelo() {
        let app = abrirApp()
        abrirGaleria(app)
        elegirVariante("Detallado", en: app)
        esperarModelo("Micro", "Detallado", en: app)
        for accion in ["izquierda", "derecha", "acercar", "alejar"] {
            comprobarCambioVisual(accion, en: app)
        }
        app.buttons["transportes3d.control.izquierda"].tap()
        app.buttons["transportes3d.control.acercar"].tap()
        comprobarCambioVisual("restablecer", en: app)
    }

    @MainActor
    private func abrirApp() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--pantalla", "rutas", "--idioma", "es"]
        app.launch()
        return app
    }

    @MainActor
    private func abrirGaleria(_ app: XCUIApplication) {
        let abrir = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Transportes en 3D")).firstMatch
        XCTAssertTrue(abrir.waitForExistence(timeout: 15))
        abrir.tap()
        XCTAssertTrue(app.descendants(matching: .any)["transportes3d.tipo"].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    private func elegirTipo(_ tipo: String, en app: XCUIApplication) {
        let boton = app.buttons["transportes3d.tipo." + tipo.lowercased()]
        XCTAssertTrue(boton.waitForExistence(timeout: 5))
        XCTAssertTrue(boton.isHittable)
        boton.tap()
        XCTAssertTrue(boton.isSelected)
    }

    @MainActor
    private func elegirVariante(_ variante: String, en app: XCUIApplication) {
        let boton = app.buttons["transportes3d.variante." + variante.lowercased()]
        XCTAssertTrue(boton.waitForExistence(timeout: 5))
        XCTAssertTrue(boton.isHittable)
        boton.tap()
        XCTAssertTrue(boton.isSelected)
    }

    @MainActor
    private func modelo(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["transportes3d.modelo"].firstMatch
    }

    @MainActor
    private func esperarModelo(_ tipo: String, _ variante: String, en app: XCUIApplication) {
        let listo = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.modelo(app).value as? String == tipo + ", " + variante
                && app.buttons["transportes3d.control.restablecer"].isEnabled
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [listo], timeout: 30), .completed,
                       "Debe cargar \(tipo) \(variante) sin necesitar otro toque.\n\(app.debugDescription)")
        for accion in ["izquierda", "derecha", "acercar", "alejar", "restablecer"] {
            let boton = app.buttons["transportes3d.control." + accion]
            XCTAssertTrue(boton.isEnabled && boton.isHittable, accion)
        }
    }

    @MainActor
    private func comprobarCambioVisual(_ accion: String, en app: XCUIApplication) {
        let anterior = pixeles(modelo(app).screenshot().image)
        app.buttons["transportes3d.control." + accion].tap()
        let cambio = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let actual = self.pixeles(self.modelo(app).screenshot().image)
            let diferencia = zip(anterior, actual).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
            return Double(diferencia) / Double(max(actual.count, 1)) > 1.0
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [cambio], timeout: 5), .completed,
                       "\(accion) debe cambiar la imagen del vehiculo")
        captura(modelo(app), nombre: "Control-" + accion)
    }

    @MainActor
    private func pixeles(_ imagen: UIImage) -> [UInt8] {
        var datos = [UInt8](repeating: 0, count: 32 * 32 * 4)
        datos.withUnsafeMutableBytes { buffer in
            let contexto = CGContext(data: buffer.baseAddress, width: 32, height: 32,
                                     bitsPerComponent: 8, bytesPerRow: 32 * 4,
                                     space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            contexto.draw(imagen.cgImage!, in: CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        return datos
    }

    @MainActor
    private func captura(_ elemento: XCUIElement, nombre: String) {
        let adjunto = XCTAttachment(screenshot: elemento.screenshot())
        adjunto.name = nombre
        adjunto.lifetime = .keepAlways
        add(adjunto)
    }
}
