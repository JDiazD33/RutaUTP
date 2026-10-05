//
//  GTFSLoadRecoveryTests.swift
//  RutaUTPTests
//
//  E10: un fallo de lectura no es un catálogo válido vacío. Las cargas y
//  reintentos compartidos conservan el diagnóstico sin tocar el feed real,
//  el entorno del proceso ni las preferencias de una instalación del usuario.
//

import XCTest
import CoreLocation
import SwiftUI
import Combine
@testable import RutaUTP

final class GTFSLoadRecoveryTests: XCTestCase {

    func testEstadoInicialYCargaExitosaSeCacheanSinReleer() async throws {
        let feed = try GTFSFixtureE10.parsear()
        let cargador = SecuenciaCargaE10([.success(feed)])
        let repo = GTFSRepository(cargador: { try await cargador.cargar() })
        let inicial = await repo.estadoCarga
        XCTAssertEqual(inicial, .sinCargar)

        let primera = try await repo.cargarRutas()
        let segunda = try await repo.cargarRutas()
        let reintentoYaCargado = try await repo.cargarRutas(reintentar: true)

        XCTAssertEqual(primera.map(\.id), ["ruta-1"])
        XCTAssertEqual(segunda.map(\.id), primera.map(\.id))
        XCTAssertEqual(reintentoYaCargado.map(\.id), primera.map(\.id))
        let llamadas = await cargador.llamadas
        let final = await repo.estadoCarga
        XCTAssertEqual(llamadas, 1)
        XCTAssertEqual(final, .cargado)
    }

    func testCatalogoVacioValidoEsExitoCacheadoYNoUnFallo() async throws {
        let cargador = SecuenciaCargaE10([.success([])])
        let repo = GTFSRepository(cargador: { try await cargador.cargar() })

        let primera = try await repo.cargarRutas()
        let segunda = try await repo.cargarRutas(reintentar: true)

        XCTAssertTrue(primera.isEmpty)
        XCTAssertTrue(segunda.isEmpty)
        let llamadas = await cargador.llamadas
        let estado = await repo.estadoCarga
        XCTAssertEqual(llamadas, 1)
        XCTAssertEqual(estado, .cargado)
    }

    func testFalloConservaDiagnosticoYSoloSeReintentaConAccionExplicita() async {
        let cargador = SecuenciaCargaE10([.failure(ErrorLecturaE10.danado)])
        let repo = GTFSRepository(cargador: { try await cargador.cargar() })

        let primero = await capturarFallo(repo)
        let segundo = await capturarFallo(repo)
        let tercero = await capturarFallo(repo)

        XCTAssertEqual(primero?.detalle, ErrorLecturaE10.danado.localizedDescription)
        XCTAssertEqual(segundo, primero)
        XCTAssertEqual(tercero, primero)
        XCTAssertFalse(primero?.mensajeUsuario.isEmpty ?? true)
        let llamadas = await cargador.llamadas
        let estado = await repo.estadoCarga
        XCTAssertEqual(llamadas, 1, "Consultar otra vez no inicia un bucle de lectura")
        if let primero { XCTAssertEqual(estado, .fallido(primero)) }
    }

    func testReintentoExplicitoRecuperaDatosSinCachearElFalloAnterior() async throws {
        let feed = try GTFSFixtureE10.parsear()
        let cargador = SecuenciaCargaE10([.failure(ErrorLecturaE10.danado), .success(feed)])
        let repo = GTFSRepository(cargador: { try await cargador.cargar() })
        _ = await capturarFallo(repo)

        let recuperadas = try await repo.cargarRutas(reintentar: true)
        let siguientes = try await repo.cargarRutas()

        XCTAssertEqual(recuperadas.map(\.id), ["ruta-1"])
        XCTAssertEqual(siguientes.map(\.id), recuperadas.map(\.id))
        let llamadas = await cargador.llamadas
        let estado = await repo.estadoCarga
        XCTAssertEqual(llamadas, 2)
        XCTAssertEqual(estado, .cargado)
    }

    func testReintentoFallidoSigueSiendoFalloSinReleerAutomaticamente() async {
        let cargador = SecuenciaCargaE10([.failure(ErrorLecturaE10.danado), .failure(ErrorLecturaE10.incompleto)])
        let repo = GTFSRepository(cargador: { try await cargador.cargar() })
        _ = await capturarFallo(repo)

        let reintentado = await capturarFallo(repo, reintentar: true)
        let siguiente = await capturarFallo(repo)

        XCTAssertEqual(reintentado?.detalle, ErrorLecturaE10.incompleto.localizedDescription)
        XCTAssertEqual(siguiente, reintentado)
        let llamadas = await cargador.llamadas
        let estado = await repo.estadoCarga
        XCTAssertEqual(llamadas, 2)
        if let reintentado { XCTAssertEqual(estado, .fallido(reintentado)) }
    }

    func testLectoresSimultaneosCompartenUnaCargaYElEstadoPendiente() async throws {
        let iniciado = expectation(description: "carga compartida iniciada")
        let cargador = CargaSuspendidaE10(alIniciar: { llamada in
            if llamada == 1 { iniciado.fulfill() }
        })
        let repo = GTFSRepository(cargador: { try await cargador.cargar() })
        let lectores = (0..<16).map { indice in
            Task { try await repo.cargarRutas(reintentar: indice.isMultiple(of: 2)) }
        }
        await fulfillment(of: [iniciado], timeout: 2)

        let pendiente = await repo.estadoCarga
        XCTAssertEqual(pendiente, .cargando)
        let feed = try GTFSFixtureE10.parsear()
        await cargador.resolverTodas(.success(feed))
        for lector in lectores {
            let rutas = try await lector.value
            XCTAssertEqual(rutas.map(\.id), ["ruta-1"])
        }

        let llamadas = await cargador.llamadas
        let final = await repo.estadoCarga
        XCTAssertEqual(llamadas, 1)
        XCTAssertEqual(final, .cargado)
    }

    func testReintentosSimultaneosYUnLectorNormalCompartenLaRecuperacion() async throws {
        let iniciado = expectation(description: "reintento compartido iniciado")
        let cargador = CargaSuspendidaE10(primera: .failure(ErrorLecturaE10.danado), alIniciar: { llamada in
            if llamada == 2 { iniciado.fulfill() }
        })
        let repo = GTFSRepository(cargador: { try await cargador.cargar() })
        _ = await capturarFallo(repo)
        let lectores = (0..<12).map { _ in
            Task { try await repo.cargarRutas(reintentar: true) }
        }
        await fulfillment(of: [iniciado], timeout: 2)
        let lectorNormal = Task { try await repo.cargarRutas() }
        let pendiente = await repo.estadoCarga
        XCTAssertEqual(pendiente, .cargando)
        await cargador.resolverTodas(.success(try GTFSFixtureE10.parsear()))

        for lector in lectores {
            let rutas = try await lector.value
            XCTAssertEqual(rutas.map(\.id), ["ruta-1"])
        }
        let normales = try await lectorNormal.value
        XCTAssertEqual(normales.map(\.id), ["ruta-1"])
        let llamadas = await cargador.llamadas
        let final = await repo.estadoCarga
        XCTAssertEqual(llamadas, 2)
        XCTAssertEqual(final, .cargado)
    }

    func testCancelarUnLectorNoCancelaLaCargaQueNecesitaOtroConsumidor() async throws {
        let iniciado = expectation(description: "carga sin cancelar iniciada")
        let cargador = CargaSuspendidaE10(alIniciar: { llamada in
            if llamada == 1 { iniciado.fulfill() }
        })
        let repo = GTFSRepository(cargador: { try await cargador.cargar() })
        let cancelado = Task { try await repo.cargarRutas() }
        await fulfillment(of: [iniciado], timeout: 2)
        let otro = Task { try await repo.cargarRutas() }
        cancelado.cancel()
        await cargador.resolverTodas(.success(try GTFSFixtureE10.parsear()))

        _ = try? await cancelado.value
        let rutas = try await otro.value
        let posteriores = try await repo.cargarRutas()
        XCTAssertEqual(rutas.map(\.id), ["ruta-1"])
        XCTAssertEqual(posteriores.map(\.id), rutas.map(\.id))
        let llamadas = await cargador.llamadas
        let cancelaciones = await cargador.cargasCanceladas
        let final = await repo.estadoCarga
        XCTAssertEqual(llamadas, 1)
        XCTAssertEqual(cancelaciones, 0)
        XCTAssertEqual(final, .cargado)
    }

    func testAPICompatiblesConservanConsultasYCarganUnaSolaVez() async throws {
        let cargador = SecuenciaCargaE10([.success(try GTFSFixtureE10.parsear())])
        let repo = GTFSRepository(cargador: { try await cargador.cargar() })

        let todas = await repo.rutas()
        let cercanas = await repo.rutasQuePasanPor(GTFSRepository.coordenadaUTP, radioMetros: 400)
        let primeras = await repo.rutasCercaDeUTP(n: 1)
        let diagnosticadas = try await repo.consultarRutasQuePasanPor(GTFSRepository.coordenadaUTP, radioMetros: 800)

        XCTAssertEqual(todas.map(\.id), ["ruta-1"])
        XCTAssertEqual(cercanas.map(\.id), todas.map(\.id))
        XCTAssertEqual(primeras.map(\.id), todas.map(\.id))
        XCTAssertEqual(diagnosticadas.map(\.id), todas.map(\.id))
        let llamadas = await cargador.llamadas
        XCTAssertEqual(llamadas, 1)
    }

    func testAPICompatiblesDevuelvenVacioPeroNoOcultanElEstadoFallidoNiReleen() async {
        let cargador = SecuenciaCargaE10([.failure(ErrorLecturaE10.danado)])
        let repo = GTFSRepository(cargador: { try await cargador.cargar() })

        let todas = await repo.rutas()
        let cercanas = await repo.rutasQuePasanPor(GTFSRepository.coordenadaUTP, radioMetros: 400)
        let ampliadas = await repo.rutasQuePasanPor(GTFSRepository.coordenadaUTP, radioMetros: 800)
        let primeras = await repo.rutasCercaDeUTP(n: 1)
        let fallo = await capturarFallo(repo)

        XCTAssertTrue(todas.isEmpty)
        XCTAssertTrue(cercanas.isEmpty)
        XCTAssertTrue(ampliadas.isEmpty)
        XCTAssertTrue(primeras.isEmpty)
        XCTAssertEqual(fallo?.detalle, ErrorLecturaE10.danado.localizedDescription)
        let llamadas = await cargador.llamadas
        XCTAssertEqual(llamadas, 1)
    }

    func testConsultaConDiagnosticoPuedeRecuperarElFeedYAplicarElRadioE09() async throws {
        let cargador = SecuenciaCargaE10([.failure(ErrorLecturaE10.danado), .success(try GTFSFixtureE10.parsear())])
        let repo = GTFSRepository(cargador: { try await cargador.cargar() })
        do {
            _ = try await repo.consultarRutasQuePasanPor(GTFSRepository.coordenadaUTP, radioMetros: 400)
            XCTFail("Un fallo no debe parecer una consulta sin coincidencias")
        } catch {
            XCTAssertNotNil(error as? FalloCargaGTFS)
        }

        let recuperadas = try await repo.consultarRutasQuePasanPor(GTFSRepository.coordenadaUTP,
                                                                 radioMetros: 400, reintentar: true)
        XCTAssertEqual(recuperadas.map(\.id), ["ruta-1"])
        let llamadas = await cargador.llamadas
        XCTAssertEqual(llamadas, 2)
    }

    private func capturarFallo(_ repo: GTFSRepository, reintentar: Bool = false) async -> FalloCargaGTFS? {
        do {
            _ = try await repo.cargarRutas(reintentar: reintentar)
            XCTFail("Se esperaba un fallo de lectura")
            return nil
        } catch {
            let fallo = error as? FalloCargaGTFS
            XCTAssertNotNil(fallo, "El repositorio conserva un diagnóstico uniforme")
            return fallo
        }
    }
}

final class GTFSFeedValidationTests: XCTestCase {

    func testArchivoAusentePropagaElFalloEnVezDeDevolverUnCatalogoVacio() throws {
        let directorio = try GTFSFixtureE10.directorioTemporal()
        defer { try? FileManager.default.removeItem(at: directorio) }
        try FileManager.default.removeItem(at: directorio.appendingPathComponent("shapes.txt"))

        XCTAssertThrowsError(try GTFSFixtureE10.parsear(desde: directorio)) { error in
            XCTAssertFalse(error.localizedDescription.isEmpty)
            XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain)
        }
    }

    func testTextoUTF8InvalidoPropagaElFalloDeDecodificacion() throws {
        let directorio = try GTFSFixtureE10.directorioTemporal()
        defer { try? FileManager.default.removeItem(at: directorio) }
        try Data([0xFF, 0xFE, 0xFF]).write(to: directorio.appendingPathComponent("agency.txt"))

        XCTAssertThrowsError(try GTFSFixtureE10.parsear(desde: directorio)) { error in
            XCTAssertFalse(error.localizedDescription.isEmpty)
            XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain)
        }
    }

    func testCadaEncabezadoIndispensableAusenteIdentificaSuTablaYColumna() {
        for (nombre, requeridas) in GTFSFixtureE10.requeridas {
            for columna in requeridas {
                var tablas = GTFSFixtureE10.tablas()
                let original = tablas[nombre]!
                var columnas = original.columns
                columnas.removeValue(forKey: columna)
                tablas[nombre] = GTFSTable(columns: columnas, rowCount: original.rowCount)

                XCTAssertThrowsError(try GTFSRepository.parsearFeed(tabla: { tablas[$0]! })) { error in
                    XCTAssertTrue(error.localizedDescription.contains(nombre), "Tabla \(nombre), columna \(columna)")
                    XCTAssertTrue(error.localizedDescription.contains(columna), "Tabla \(nombre), columna \(columna)")
                }
            }
        }
    }

    func testMetadatosOpcionalesAusentesMantienenLosFallbacksDelDominio() throws {
        let tablas = GTFSFixtureE10.tablas().mapValues { original in
            GTFSTable(columns: original.columns, rowCount: original.rowCount)
        }
        var minimas: [String: GTFSTable] = [:]
        for (nombre, requeridas) in GTFSFixtureE10.requeridas {
            let original = tablas[nombre]!
            let columnas = original.columns.filter { requeridas.contains($0.key) }
            minimas[nombre] = GTFSTable(columns: columnas, rowCount: original.rowCount)
        }

        let rutas = try GTFSRepository.parsearFeed(tabla: { minimas[$0]! })
        let ruta = try XCTUnwrap(rutas.first)
        XCTAssertEqual(rutas.count, 1)
        XCTAssertEqual(ruta.id, "ruta-1")
        XCTAssertEqual(ruta.linea, "")
        XCTAssertEqual(ruta.variante, "")
        XCTAssertEqual(ruta.recorrido, "")
        XCTAssertEqual(ruta.empresa, "", "Se conserva el enlace por clave vacía de la agencia única")
        XCTAssertEqual(ruta.colorHex, "00CC00")
        XCTAssertEqual(ruta.duracionMin, 0)
        XCTAssertEqual(ruta.headwayMin, 0)
        XCTAssertEqual(ruta.precio, 0)
        XCTAssertEqual(ruta.paraderos.map(\.id), ["parada-1", "parada-2"])
        XCTAssertEqual(ruta.paraderos.map(\.nombre), ["", ""])
    }

    func testUnaAgenciaSinIDsConservaSuNombreCuandoLaRutaNoDeclaraAgencia() throws {
        var tablas = GTFSFixtureE10.tablas()
        tablas["agency"] = GTFSCSV.parsear(texto: "agency_name\nEmpresa única\n")
        let rutasOriginales = tablas["routes"]!
        var columnas = rutasOriginales.columns
        columnas.removeValue(forKey: "agency_id")
        tablas["routes"] = GTFSTable(columns: columnas, rowCount: rutasOriginales.rowCount)

        let rutas = try GTFSRepository.parsearFeed(tabla: { tablas[$0]! })
        XCTAssertEqual(rutas.first?.id, "ruta-1")
        XCTAssertEqual(rutas.first?.empresa, "Empresa única")
    }

    func testFeedConEncabezadosValidosYSinFilasEsUnCatalogoVacioValido() throws {
        let tablas = GTFSFixtureE10.tablas().mapValues { original in
            GTFSTable(columns: original.columns.mapValues { _ in [] }, rowCount: 0)
        }

        let rutas = try GTFSRepository.parsearFeed(tabla: { tablas[$0]! })
        XCTAssertTrue(rutas.isEmpty)
    }

    func testFixtureConservaIdentidadMetadatosOrdenDeGeometriaYDistanciaAlInteriorE09() throws {
        let rutas = try GTFSFixtureE10.parsear()
        let ruta = try XCTUnwrap(rutas.first)
        let campus = GTFSRepository.coordenadaUTP

        XCTAssertEqual(rutas.count, 1)
        XCTAssertEqual(ruta.id, "ruta-1")
        XCTAssertEqual(ruta.linea, "C-01")
        XCTAssertEqual(ruta.variante, "B")
        XCTAssertEqual(ruta.recorrido, "Alfa → Beta")
        XCTAssertEqual(ruta.empresa, "Empresa local")
        XCTAssertEqual(ruta.colorHex, "A1B2C3")
        XCTAssertEqual(ruta.shape.count, 2)
        XCTAssertEqual(ruta.shape.first?.latitude ?? 0, campus.latitude, accuracy: 0.000000001)
        XCTAssertEqual(ruta.shape.first?.longitude ?? 0, campus.longitude - 0.006, accuracy: 0.000000001)
        XCTAssertEqual(ruta.shape.last?.longitude ?? 0, campus.longitude + 0.006, accuracy: 0.000000001)
        XCTAssertEqual(ruta.paraderos.map(\.id), ["parada-1", "parada-2"])
        XCTAssertEqual(ruta.paraderos.map(\.nombre), ["Alfa", "Beta"])
        XCTAssertEqual(ruta.duracionMin, 20, "GTFS permite horas de salida mayores que 24")
        XCTAssertEqual(ruta.headwayMin, 10)
        XCTAssertEqual(ruta.precio, 2.5)
        XCTAssertEqual(ruta.distanciaKm, 1.3, accuracy: 0.0001)
        XCTAssertEqual(ruta.distanciaUTPMetros, 0, accuracy: 0.001)
        for vertice in ruta.shape {
            XCTAssertGreaterThan(CLLocation(latitude: vertice.latitude, longitude: vertice.longitude)
                .distance(from: CLLocation(latitude: campus.latitude, longitude: campus.longitude)), 400)
        }
    }
}

@MainActor
final class GTFSLoadPresentationTests: XCTestCase {

    func testRutasPresentaFalloSinMarcarElFeedComoVacio() async {
        let cargador = SecuenciaCargaE10([.failure(ErrorLecturaE10.danado)])
        let repo = GTFSRepository(cargador: { try await cargador.cargar() })
        let modelo = RutasViewModel(repositorioGTFS: repo)

        await modelo.cargar()
        await modelo.cargar()

        XCTAssertFalse(modelo.cargando)
        XCTAssertFalse(modelo.feedVacio)
        XCTAssertTrue(modelo.rutas.isEmpty)
        XCTAssertEqual(modelo.errorCarga?.detalle, ErrorLecturaE10.danado.localizedDescription)
        let llamadas = await cargador.llamadas
        XCTAssertEqual(llamadas, 1)
    }

    func testRutasDistingueUnCatalogoVacioValidoDeUnError() async {
        let repo = GTFSRepository(cargador: { [] })
        let modelo = RutasViewModel(repositorioGTFS: repo)

        await modelo.cargar()

        XCTAssertFalse(modelo.cargando)
        XCTAssertTrue(modelo.feedVacio)
        XCTAssertNil(modelo.errorCarga)
        XCTAssertTrue(modelo.rutas.isEmpty)
    }

    func testRutasReintentaYConservaLaBusquedaMientrasRecuperaElCatalogo() async throws {
        let cargador = SecuenciaCargaE10([.failure(ErrorLecturaE10.danado), .success(try GTFSFixtureE10.parsear())])
        let repo = GTFSRepository(cargador: { try await cargador.cargar() })
        let modelo = RutasViewModel(repositorioGTFS: repo)
        modelo.textoBusqueda = "Empresa local"
        await modelo.cargar()

        await modelo.cargar(reintentar: true)

        XCTAssertFalse(modelo.cargando)
        XCTAssertFalse(modelo.feedVacio)
        XCTAssertNil(modelo.errorCarga)
        XCTAssertEqual(modelo.textoBusqueda, "Empresa local")
        XCTAssertEqual(modelo.rutas.map(\.id), ["ruta-1"])
        XCTAssertEqual(modelo.rutasFiltradas.map(\.id), ["ruta-1"])
    }

    func testRutasMuestraCargaPendienteAntesDeRecibirElResultado() async throws {
        let iniciado = expectation(description: "catálogo de Rutas pendiente")
        let cargador = CargaSuspendidaE10(alIniciar: { llamada in
            if llamada == 1 { iniciado.fulfill() }
        })
        let modelo = RutasViewModel(repositorioGTFS: GTFSRepository(cargador: { try await cargador.cargar() }))
        let tarea = Task { await modelo.cargar() }
        await fulfillment(of: [iniciado], timeout: 2)

        XCTAssertTrue(modelo.cargando)
        XCTAssertNil(modelo.errorCarga)
        XCTAssertFalse(modelo.feedVacio)
        await cargador.resolverTodas(.success(try GTFSFixtureE10.parsear()))
        await tarea.value
        XCTAssertFalse(modelo.cargando)
        XCTAssertEqual(modelo.rutas.map(\.id), ["ruta-1"])
    }

    func testGuardadoDistingueCatalogoVacioValidoDelFallo() async throws {
        let dominio = "rutautp.e10.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: dominio))
        defer { defaults.removePersistentDomain(forName: dominio) }
        let almacen = AlmacenLugares(defaults: defaults)
        let vacio = GuardadoViewModel(almacen: almacen, repositorioGTFS: GTFSRepository(cargador: { [] }))
        let fallo = GuardadoViewModel(almacen: almacen, repositorioGTFS: GTFSRepository(cargador: {
            throw ErrorLecturaE10.danado
        }))

        await vacio.cargarCatalogo()
        await fallo.cargarCatalogo()

        XCTAssertTrue(vacio.catalogoCargado)
        XCTAssertFalse(vacio.cargandoCatalogo)
        XCTAssertNil(vacio.errorCatalogo)
        XCTAssertTrue(vacio.lineasGTFS.isEmpty)
        XCTAssertTrue(fallo.catalogoCargado)
        XCTAssertFalse(fallo.cargandoCatalogo)
        XCTAssertNotNil(fallo.errorCatalogo)
        XCTAssertTrue(fallo.lineasGTFS.isEmpty)
    }

    func testGuardadoRecuperaReferenciasPersistidasSinBorrarlasDuranteElFallo() async throws {
        let dominio = "rutautp.e10.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: dominio))
        defer { defaults.removePersistentDomain(forName: dominio) }
        let referencias = [LineaGuardadaRef(routeId: "ruta-1")]
        let bytes = try JSONEncoder().encode(referencias)
        defaults.set(bytes, forKey: "lineas.guardadas.v1")
        let cargador = SecuenciaCargaE10([.failure(ErrorLecturaE10.danado), .success(try GTFSFixtureE10.parsear())])
        let modelo = GuardadoViewModel(almacen: AlmacenLugares(defaults: defaults),
                                       repositorioGTFS: GTFSRepository(cargador: { try await cargador.cargar() }))
        modelo.cargar()
        await modelo.cargarCatalogo()
        await modelo.cargarCatalogo()

        XCTAssertNotNil(modelo.errorCatalogo)
        XCTAssertEqual(modelo.lineaRefs.map(\.routeId), ["ruta-1"])
        XCTAssertTrue(modelo.lineasGuardadas.isEmpty)
        XCTAssertEqual(defaults.data(forKey: "lineas.guardadas.v1"), bytes)
        let intentosAntes = await cargador.llamadas
        XCTAssertEqual(intentosAntes, 1)

        await modelo.cargarCatalogo(reintentar: true)

        XCTAssertNil(modelo.errorCatalogo)
        XCTAssertFalse(modelo.cargandoCatalogo)
        XCTAssertEqual(modelo.lineasGuardadas.map(\.id), ["ruta-1"])
        XCTAssertEqual(modelo.lineaRefs.map(\.routeId), ["ruta-1"])
        XCTAssertEqual(defaults.data(forKey: "lineas.guardadas.v1"), bytes)
        let intentosDespues = await cargador.llamadas
        XCTAssertEqual(intentosDespues, 2)
    }
}

@MainActor
final class GTFSLoadCascadeTests: XCTestCase {
    func testMapaNoAmpliaUnErrorA800NiReleeHastaUnReintentoDelMismoPunto() async throws {
        let cargador = SecuenciaCargaE10([.failure(ErrorLecturaE10.danado), .success(try GTFSFixtureE10.parsear())])
        let repo = GTFSRepository(cargador: { try await cargador.cargar() })
        let consultas = ConsultasGTFSRegistradasE10(repo)
        let modelo = MapaViewModel(locationService: GPSE10(), repositorioGTFS: consultas,
                                   crearProveedorReal: { nil })
        defer { modelo.detener() }
        modelo.recargarLineas(cercaDe: GTFSRepository.coordenadaUTP)
        await esperar("fallo del panel") { !modelo.cargandoLineas && modelo.errorLineas != nil }

        XCTAssertTrue(modelo.rutasCercanas.isEmpty)
        XCTAssertTrue(modelo.busesAnimados.isEmpty)
        let radiosFallidos = await consultas.radios
        XCTAssertEqual(radiosFallidos, [400], "Un error no es una búsqueda vacía que deba ampliarse")
        modelo.recargarLineas(cercaDe: GTFSRepository.coordenadaUTP)
        for _ in 0..<20 { await Task.yield() }
        let intentosSinAccion = await cargador.llamadas
        let radiosSinAccion = await consultas.radios
        XCTAssertEqual(intentosSinAccion, 1)
        XCTAssertEqual(radiosSinAccion, [400])

        modelo.reintentarCatalogo()
        await esperar("recuperación del mismo punto") { !modelo.cargandoLineas && modelo.errorLineas == nil }

        XCTAssertEqual(modelo.rutasCercanas.map(\.id), ["ruta-1"])
        let radiosRecuperados = await consultas.radios
        let intentosRecuperados = await cargador.llamadas
        XCTAssertEqual(radiosRecuperados, [400, 400])
        XCTAssertEqual(intentosRecuperados, 2)
    }

    func testMapaConservaPosicionesRealesDuranteFalloYRecuperaSoloSusMetadatos() async throws {
        let feed = try GTFSFixtureE10.parsear()
        let cargador = SecuenciaCargaE10([.failure(ErrorLecturaE10.danado), .success(feed)])
        let campus = GTFSRepository.coordenadaUTP
        let posicion = VehiclePosition(id: "observado-1", linea: "C-01", routeId: "ruta-1",
                                       lat: campus.latitude, lon: campus.longitude - 0.005,
                                       heading: 90, speed: 10)
        let vehiculos = VehiculosE10(posiciones: [posicion])
        let modelo = MapaViewModel(locationService: GPSE10(),
                                   repositorioGTFS: GTFSRepository(cargador: { try await cargador.cargar() }),
                                   crearProveedorReal: { vehiculos })
        defer { modelo.detener() }
        modelo.iniciarSimulacionBuses()
        await esperar("snapshot real pese a fallo de metadatos") {
            !modelo.cargandoLineas && modelo.errorLineas != nil && modelo.busesAnimados.count == 1
        }
        let antes = try XCTUnwrap(modelo.busesAnimados.first)
        XCTAssertEqual(antes.id, "real-observado-1")
        XCTAssertEqual(antes.fuente, .real)
        XCTAssertTrue(antes.rutaCoordenadas.isEmpty)
        XCTAssertTrue(modelo.busesDelPanel.isEmpty)
        XCTAssertNil(antes.minutosLlegada)

        modelo.reintentarCatalogo()
        await esperar("metadatos recuperados") {
            !modelo.cargandoLineas && modelo.errorLineas == nil
                && modelo.busesAnimados.first?.empresa == "Empresa local"
        }

        let despues = try XCTUnwrap(modelo.busesAnimados.first)
        XCTAssertEqual(despues.id, antes.id)
        XCTAssertEqual(despues.lat, posicion.lat)
        XCTAssertEqual(despues.lon, posicion.lon)
        XCTAssertEqual(despues.heading, posicion.heading)
        XCTAssertEqual(despues.fuente, .real)
        XCTAssertTrue(despues.rutaCoordenadas.isEmpty)
        XCTAssertEqual(despues.variante, "B")
        XCTAssertEqual(despues.minutosLlegada, VehicleETAEstimator.minutes(position: posicion,
                                                                          route: feed[0], target: campus))
        XCTAssertEqual(modelo.busesDelPanel.map(\.id), [antes.id])
        XCTAssertEqual(vehiculos.inicios, 1)
        XCTAssertEqual(vehiculos.paradas, 0)
        let llamadas = await cargador.llamadas
        XCTAssertEqual(llamadas, 2)
    }

    func testDeteccionConConsentimientoNoActivaSensoresSiElFeedFallaYSeRecuperaExplicitamente() async throws {
        try await conConsentimiento {
            let cargador = SecuenciaCargaE10([.failure(ErrorLecturaE10.danado), .success(try GTFSFixtureE10.parsear())])
            let repo = GTFSRepository(cargador: { try await cargador.cargar() })
            let gps = GPSE10()
            let movimiento = MovimientoE10()
            let publicador = PublicadorE10()
            let coordinador = PassiveTrackingCoordinator(locationService: gps, motionService: movimiento,
                repository: repo, observationPublisher: publicador,
                tripOccupancy: OccupancyService(configurationProvider: { nil }), configurationProvider: { nil })
            defer { coordinador.stop() }

            await coordinador.startIfConsented()

            XCTAssertTrue(coordinador.isEnabled)
            XCTAssertFalse(coordinador.isRunning)
            XCTAssertNotNil(coordinador.errorCargaRutas)
            XCTAssertEqual(gps.inicios, 0)
            XCTAssertEqual(movimiento.inicios, 0)
            XCTAssertEqual(publicador.inicios, 0)
            XCTAssertEqual(publicador.publicaciones, 0)
            // Otro consumidor puede recuperar el mismo actor. El coordinador
            // necesita todavía la acción explícita de iniciar la detección.
            _ = try await repo.cargarRutas(reintentar: true)
            XCTAssertFalse(coordinador.isRunning)
            coordinador.setContributionEnabled(true)
            await esperar("detección recuperada") { coordinador.isRunning }

            XCTAssertNil(coordinador.errorCargaRutas)
            XCTAssertEqual(gps.inicios, 1)
            XCTAssertEqual(movimiento.inicios, 1)
            XCTAssertEqual(publicador.inicios, 0, "Cargar rutas no confirma un abordaje ni crea una sesión")
            XCTAssertEqual(publicador.publicaciones, 0)
            XCTAssertNil(coordinador.confirmedLine)
            XCTAssertNil(coordinador.selectedTripRoute)
            let llamadas = await cargador.llamadas
            XCTAssertEqual(llamadas, 2)
        }
    }

    func testDeteccionConCatalogoVacioValidoNoIniciaSensoresNiLoMarcaComoFallo() async throws {
        await conConsentimiento {
            let cargador = SecuenciaCargaE10([.success([])])
            let gps = GPSE10()
            let movimiento = MovimientoE10()
            let coordinador = PassiveTrackingCoordinator(locationService: gps, motionService: movimiento,
                repository: GTFSRepository(cargador: { try await cargador.cargar() }),
                observationPublisher: PublicadorE10(),
                tripOccupancy: OccupancyService(configurationProvider: { nil }), configurationProvider: { nil })
            defer { coordinador.stop() }

            await coordinador.startIfConsented()
            await coordinador.startIfConsented()

            XCTAssertFalse(coordinador.isRunning)
            XCTAssertNil(coordinador.errorCargaRutas)
            XCTAssertEqual(gps.inicios, 0)
            XCTAssertEqual(movimiento.inicios, 0)
            let llamadas = await cargador.llamadas
            XCTAssertEqual(llamadas, 1)
        }
    }

    func testRevocarConsentimientoDuranteLaCargaImpideUnArranqueTardio() async throws {
        try await conConsentimiento {
            let iniciado = expectation(description: "feed pendiente de detección")
            let cargador = CargaSuspendidaE10(alIniciar: { llamada in
                if llamada == 1 { iniciado.fulfill() }
            })
            let gps = GPSE10()
            let movimiento = MovimientoE10()
            let publicador = PublicadorE10()
            let coordinador = PassiveTrackingCoordinator(locationService: gps, motionService: movimiento,
                repository: GTFSRepository(cargador: { try await cargador.cargar() }),
                observationPublisher: publicador,
                tripOccupancy: OccupancyService(configurationProvider: { nil }), configurationProvider: { nil })
            defer { coordinador.stop() }
            let tarea = Task { await coordinador.startIfConsented() }
            await fulfillment(of: [iniciado], timeout: 2)

            coordinador.setContributionEnabled(false)
            await cargador.resolverTodas(.success(try GTFSFixtureE10.parsear()))
            await tarea.value

            XCTAssertFalse(coordinador.isEnabled)
            XCTAssertFalse(coordinador.isRunning)
            XCTAssertEqual(gps.inicios, 0)
            XCTAssertEqual(movimiento.inicios, 0)
            XCTAssertEqual(publicador.inicios, 0)
            XCTAssertEqual(publicador.publicaciones, 0)
        }
    }

    private func esperar(_ descripcion: String, condicion: () -> Bool) async {
        for _ in 0..<400 {
            if condicion() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("No se completó: \(descripcion)")
    }

    private func conConsentimiento<T>(_ cuerpo: () async throws -> T) async rethrows -> T {
        let clave = "rutautp.passive-tracking-consent"
        let anterior = UserDefaults.standard.object(forKey: clave)
        defer {
            if let anterior { UserDefaults.standard.set(anterior, forKey: clave) }
            else { UserDefaults.standard.removeObject(forKey: clave) }
        }
        UserDefaults.standard.set(true, forKey: clave)
        return try await cuerpo()
    }
}

private actor ConsultasGTFSRegistradasE10: RutasGTFSProviding {
    private let repo: GTFSRepository
    private(set) var radios: [Double] = []
    init(_ repo: GTFSRepository) { self.repo = repo }
    func rutas() async -> [RutaGTFS] { await repo.rutas() }
    func rutasQuePasanPor(_ punto: CLLocationCoordinate2D, radioMetros: Double) async -> [RutaGTFS] {
        await repo.rutasQuePasanPor(punto, radioMetros: radioMetros)
    }
    func cargarRutas(reintentar: Bool) async throws -> [RutaGTFS] {
        try await repo.cargarRutas(reintentar: reintentar)
    }
    func consultarRutasQuePasanPor(_ punto: CLLocationCoordinate2D,
                                 radioMetros: Double, reintentar: Bool) async throws -> [RutaGTFS] {
        radios.append(radioMetros)
        return try await repo.consultarRutasQuePasanPor(punto, radioMetros: radioMetros, reintentar: reintentar)
    }
}

private final class GPSE10: LocationServiceProtocol {
    let authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
    var authorizationPublisher: AnyPublisher<CLAuthorizationStatus, Never> {
        Just(authorizationStatus).eraseToAnyPublisher()
    }
    private(set) var inicios = 0
    func requestPermission() async -> CLAuthorizationStatus { authorizationStatus }
    func currentLocation() -> AsyncStream<CLLocation> { AsyncStream { $0.finish() } }
    func startUpdating() { inicios += 1 }
    func stopUpdating() {}
}

private final class MovimientoE10: MotionActivityProviding {
    let currentActivity: DetectedMotionActivity = .unknown
    private(set) var inicios = 0
    func start() { inicios += 1 }
    func stop() {}
    func activities() -> AsyncStream<DetectedMotionActivity> { AsyncStream { $0.finish() } }
}

@MainActor
private final class PublicadorE10: ObservationPublishing {
    var state: ObservationPublisherState = .inactive
    var onStateChange: (@MainActor (ObservationPublisherState) -> Void)?
    private(set) var inicios = 0
    private(set) var publicaciones = 0
    func start(sessionID: String, linea: String) { inicios += 1 }
    func publish(location: CLLocation, routeID: String, activity: DetectedMotionActivity) { publicaciones += 1 }
    func stop() { state = .inactive }
}

private final class VehiculosE10: VehicleTrackingProviding {
    let source: VehicleTrackingSource = .real
    let currentPositions: [VehiclePosition]
    private var continuacion: AsyncStream<[VehiclePosition]>.Continuation!
    private var stream: AsyncStream<[VehiclePosition]>!
    private(set) var inicios = 0
    private(set) var paradas = 0
    init(posiciones: [VehiclePosition]) {
        currentPositions = posiciones
        stream = AsyncStream { continuacion = $0 }
    }
    func start() { inicios += 1 }
    func stop() { paradas += 1; continuacion.finish() }
    func positions() -> AsyncStream<[VehiclePosition]> {
        continuacion.yield(currentPositions)
        return stream
    }
}

private enum ErrorLecturaE10: LocalizedError {
    case danado
    case incompleto

    var errorDescription: String? {
        switch self {
        case .danado: return "Feed de prueba ilegible."
        case .incompleto: return "Feed de prueba incompleto."
        }
    }
}

private actor SecuenciaCargaE10 {
    private let resultados: [Result<[RutaGTFS], Error>]
    private(set) var llamadas = 0

    init(_ resultados: [Result<[RutaGTFS], Error>]) { self.resultados = resultados }

    func cargar() throws -> [RutaGTFS] {
        let indice = min(llamadas, resultados.count - 1)
        llamadas += 1
        return try resultados[indice].get()
    }
}

private actor CargaSuspendidaE10 {
    private let primera: Result<[RutaGTFS], Error>?
    private let alIniciar: @Sendable (Int) -> Void
    private var pendientes: [Int: CheckedContinuation<[RutaGTFS], Error>] = [:]
    private var respuestaFinal: Result<[RutaGTFS], Error>?
    private(set) var llamadas = 0
    private(set) var cargasCanceladas = 0

    init(primera: Result<[RutaGTFS], Error>? = nil, alIniciar: @escaping @Sendable (Int) -> Void) {
        self.primera = primera
        self.alIniciar = alIniciar
    }

    func cargar() async throws -> [RutaGTFS] {
        llamadas += 1
        let indice = llamadas
        if indice == 1, let primera { return try primera.get() }
        if let respuestaFinal { return try respuestaFinal.get() }
        let rutas = try await withCheckedThrowingContinuation { continuacion in
            pendientes[indice] = continuacion
            alIniciar(indice)
        }
        if Task.isCancelled { cargasCanceladas += 1 }
        return rutas
    }

    // Resuelve también lectores que llegaron tarde si una regresión hubiera
    // creado más cargas: el test termina y verifica la deduplicación por count.
    func resolverTodas(_ resultado: Result<[RutaGTFS], Error>) {
        respuestaFinal = resultado
        let actuales = pendientes.values
        pendientes.removeAll()
        for continuacion in actuales { continuacion.resume(with: resultado) }
    }
}

private enum GTFSFixtureE10 {
    static let requeridas: [(String, [String])] = [
        ("agency", []),
        ("routes", ["route_id"]),
        ("trips", ["trip_id", "route_id"]),
        ("shapes", ["shape_id", "shape_pt_lat", "shape_pt_lon", "shape_pt_sequence"]),
        ("stops", ["stop_id", "stop_lat", "stop_lon"]),
        ("stop_times", ["trip_id", "stop_id", "stop_sequence"]),
        ("frequencies", ["trip_id"]),
        ("fare_rules", ["route_id", "fare_id"]),
        ("fare_attributes", ["fare_id"])
    ]

    static var textos: [String: String] {
        let campus = GTFSRepository.coordenadaUTP
        return [
            "agency": "agency_id,agency_name\nagencia-1,Empresa local\n",
            "routes": "route_id,agency_id,route_short_name,route_long_name,route_color\nruta-1,agencia-1,C-01 \"B\",C-01 \"B\" : Alfa → Beta,A1B2C3\n",
            "trips": "trip_id,route_id,shape_id\nviaje-1,ruta-1,shape-1\n",
            "shapes": "shape_id,shape_pt_lat,shape_pt_lon,shape_pt_sequence\nshape-1,\(campus.latitude),\(campus.longitude + 0.006),20\nshape-1,\(campus.latitude),\(campus.longitude - 0.006),10\n",
            "stops": "stop_id,stop_name,stop_lat,stop_lon\nparada-2,Beta,\(campus.latitude),\(campus.longitude + 0.006)\nparada-1,Alfa,\(campus.latitude),\(campus.longitude - 0.006)\n",
            "stop_times": "trip_id,stop_id,stop_sequence,departure_time\nviaje-1,parada-2,20,25:20:00\nviaje-1,parada-1,10,25:00:00\n",
            "frequencies": "trip_id,headway_secs\nviaje-1,600\n",
            "fare_rules": "route_id,fare_id\nruta-1,tarifa-1\n",
            "fare_attributes": "fare_id,price\ntarifa-1,2.50\n"
        ]
    }

    static func tablas() -> [String: GTFSTable] {
        textos.mapValues { GTFSCSV.parsear(texto: $0) }
    }

    static func parsear() throws -> [RutaGTFS] {
        let datos = tablas()
        return try GTFSRepository.parsearFeed(tabla: { datos[$0]! })
    }

    static func directorioTemporal() throws -> URL {
        let directorio = FileManager.default.temporaryDirectory
            .appendingPathComponent("rutautp-e10-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directorio, withIntermediateDirectories: true)
        do {
            for (nombre, texto) in textos {
                try texto.write(to: directorio.appendingPathComponent("\(nombre).txt"), atomically: true, encoding: .utf8)
            }
            return directorio
        } catch {
            try? FileManager.default.removeItem(at: directorio)
            throw error
        }
    }

    static func parsear(desde directorio: URL) throws -> [RutaGTFS] {
        try GTFSRepository.parsearFeed(tabla: { nombre in
            let url = directorio.appendingPathComponent("\(nombre).txt")
            return GTFSCSV.parsear(texto: try String(contentsOf: url, encoding: .utf8))
        })
    }
}
