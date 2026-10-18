//
//  RutaUTPTests.swift
//  RutaUTPTests
//
//  Pruebas del NÚCLEO PURO del proyecto: las piezas que no dependen de la
//  interfaz ni de la red y que, por tanto, se pueden comprobar sin simulador
//  interactivo. Son las que el Informe 4 (M-38) señalaba como objetivo:
//
//    - GTFSCSV ............ el parser del feed (comillas, comas, columnas)
//    - GTFSNombreParser ... línea/variante y "ramal circular"
//    - PolylineMatching ... proyección sobre el recorrido, decimación, longitudes
//    - TransitItinerary ... búsqueda de línea directa entre dos puntos
//    - CuponNegocio ....... vigencia de un cupón
//    - ParaderosIluminados  selección estable y sin duplicados
//    - SeguridadLugaresModel  regla de orden de los tiles de Seguridad
//
//  `SeguridadLugaresModel` sí lee `UserDefaults` (vía `LugaresStore`), pero se
//  prueba porque la regla que contiene —UTP fijo primero, luego el orden que
//  eligió el usuario— era justo la que no se podía comprobar mientras vivía
//  dentro de la vista. Las pruebas limpian las llaves antes y después.
//

import XCTest
import CoreLocation
import MapKit
import SwiftUI
import Observation
import Combine
@testable import RutaUTP

final class GTFSCSVTests: XCTestCase {

    func testParserCuentaFilasYColumnas() {
        let tabla = GTFSCSV.parsear(texto: "a,b,c\n1,2,3\n4,5,6\n")
        XCTAssertEqual(tabla.rowCount, 2)
        XCTAssertEqual(tabla.columna("a"), ["1", "4"])
        XCTAssertEqual(tabla.columna("b"), ["2", "5"])
        XCTAssertEqual(tabla.columna("c"), ["3", "6"])
    }

    func testParserRespetaComasDentroDeComillas() {
        let tabla = GTFSCSV.parsear(texto: "a,b,c\n1,\"x,y\",3\n")
        XCTAssertEqual(tabla.columna("a"), ["1"])
        XCTAssertEqual(tabla.columna("b"), ["x,y"], "la coma entrecomillada no debe partir el campo")
        XCTAssertEqual(tabla.columna("c"), ["3"])
    }

    func testParserTrataLaComillaEmbebidaComoTexto() {
        // Los short names del feed real son del tipo `C-01 "B"`. La comilla no
        // abre un campo entrecomillado porque el valor ya tiene contenido: si
        // el parser la interpretara como delimitador, la variante se perdería.
        let tabla = GTFSCSV.parsear(texto: "route_id,route_short_name\n1,C-01 \"B\"\n")
        XCTAssertEqual(tabla.columna("route_short_name"), ["C-01 \"B\""])
    }

    func testColumnaInexistenteDevuelveVacios() {
        let tabla = GTFSCSV.parsear(texto: "a\n1\n2\n")
        XCTAssertEqual(tabla.columna("no_existe"), ["", ""])
    }

    func testNombreParserSeparaLineaYVariante() {
        let (linea, variante) = GTFSNombreParser.lineaYVariante(shortName: "C-01 \"B\"")
        XCTAssertEqual(linea, "C-01")
        XCTAssertEqual(variante, "B")
    }

    func testNombreParserSinVariante() {
        let (linea, variante) = GTFSNombreParser.lineaYVariante(shortName: "M-07")
        XCTAssertEqual(linea, "M-07")
        XCTAssertEqual(variante, "")
    }

    func testRecorridoMarcaRamalCircular() {
        // Origen == destino: el feed lo publica como un recorrido que vuelve.
        let texto = GTFSNombreParser.recorrido(longName: "C-01 \"B\" : Av. Grau → Av. Grau",
                                               shortName: "C-01 \"B\"")
        XCTAssertEqual(texto, "Av. Grau (ramal circular)")
    }

    func testRecorridoNormalNoSeAltera() {
        let texto = GTFSNombreParser.recorrido(longName: "C-01 \"B\" : Av. Grau → Av. Libertad",
                                               shortName: "C-01 \"B\"")
        XCTAssertEqual(texto, "Av. Grau → Av. Libertad")
    }
}

final class PolylineMatchingTests: XCTestCase {

    /// Línea recta de ~1.1 km sobre el paralelo -8.10.
    private let inicio = CLLocationCoordinate2D(latitude: -8.10, longitude: -79.04)
    private let fin    = CLLocationCoordinate2D(latitude: -8.10, longitude: -79.03)
    private var recta: [CLLocationCoordinate2D] { [inicio, fin] }

    func testMatchProyectaSobreLaLinea() {
        // Punto a ~55 m al norte del punto medio.
        let punto = CLLocationCoordinate2D(latitude: -8.0995, longitude: -79.035)
        guard let match = PolylineMatching.match(point: punto, on: recta, thresholdMeters: 100) else {
            return XCTFail("debería proyectar sobre la recta")
        }
        XCTAssertTrue(match.isOnRoute)
        XCTAssertEqual(match.progressFraction, 0.5, accuracy: 0.05)
        XCTAssertLessThan(match.distanceToRoute, 100)
    }

    func testMatchDetectaFueraDeRuta() {
        let punto = CLLocationCoordinate2D(latitude: -8.105, longitude: -79.035)
        guard let match = PolylineMatching.match(point: punto, on: recta, thresholdMeters: 20) else {
            return XCTFail("debería proyectar igualmente")
        }
        XCTAssertFalse(match.isOnRoute, "a ~550 m de la recta no puede considerarse en ruta")
        XCTAssertGreaterThan(match.distanceToRoute, 400)
    }

    func testMatchNecesitaAlMenosDosPuntos() {
        XCTAssertNil(PolylineMatching.match(point: inicio, on: [inicio]))
    }

    func testDecimateConservaExtremosYCuenta() {
        let puntos = (0..<100).map {
            CLLocationCoordinate2D(latitude: -8.10, longitude: -79.04 + Double($0) * 0.0001)
        }
        let reducidos = PolylineMatching.decimate(puntos, maxPoints: 10)
        XCTAssertEqual(reducidos.count, 10)
        XCTAssertEqual(reducidos.first!.longitude, puntos.first!.longitude, accuracy: 1e-9)
        XCTAssertEqual(reducidos.last!.longitude, puntos.last!.longitude, accuracy: 1e-9)
    }

    func testDecimateNoAmpliaListasCortas() {
        let puntos = [inicio, fin]
        XCTAssertEqual(PolylineMatching.decimate(puntos, maxPoints: 10).count, 2)
    }

    func testLongitudTotalDeLaRecta() {
        // 0.01° de longitud a latitud -8.10 ≈ 1.10 km.
        let metros = PolylineMatching.totalLengthMeters(recta)
        XCTAssertEqual(metros, 1100, accuracy: 80)
    }

    func testRecalculoTrasTresMuestrasFueraDeRuta() {
        XCTAssertTrue(PolylineMatching.shouldRecalculate(lastMatch: nil, consecutiveOffRouteCount: 0),
                      "sin match previo hay que recalcular")
        let match = PolylineMatching.match(point: inicio, on: recta, thresholdMeters: 20)
        XCTAssertFalse(PolylineMatching.shouldRecalculate(lastMatch: match, consecutiveOffRouteCount: 2,
                                                          thresholdCount: 3),
                       "dos muestras fuera no bastan: el ruido de GPS no debe provocar recálculo")
        XCTAssertTrue(PolylineMatching.shouldRecalculate(lastMatch: match, consecutiveOffRouteCount: 3,
                                                         thresholdCount: 3))
    }
}

final class TransitItineraryTests: XCTestCase {

    /// Ruta sintética recta de 11 puntos (~1.1 km) con tres paraderos.
    private func rutaSintetica() -> RutaGTFS {
        let shape = (0...10).map {
            CLLocationCoordinate2D(latitude: -8.10, longitude: -79.04 + Double($0) * 0.001)
        }
        let paraderos = [
            ParaderoGTFS(id: "p0", nombre: "Inicio", lat: shape[0].latitude, lon: shape[0].longitude),
            ParaderoGTFS(id: "p1", nombre: "Medio", lat: shape[5].latitude, lon: shape[5].longitude),
            ParaderoGTFS(id: "p2", nombre: "Fin", lat: shape[10].latitude, lon: shape[10].longitude)
        ]
        return RutaGTFS(id: "R1", linea: "C-01", variante: "B",
                        recorrido: "Inicio → Fin", empresa: "Agencia de prueba",
                        colorHex: "00CC00", color: .green,
                        shape: shape, paraderos: paraderos,
                        duracionMin: 10, headwayMin: 5, precio: 2.5,
                        distanciaKm: 1.1, distanciaUTPMetros: 100)
    }

    func testEncuentraLineaDirectaEntreExtremos() {
        let ruta = rutaSintetica()
        let candidatos = TransitItinerary.candidates(in: [ruta],
                                                     origin: ruta.shape.first!,
                                                     destination: ruta.shape.last!,
                                                     radius: 300)
        guard let plan = candidatos.first else {
            return XCTFail("debería encontrar la línea directa")
        }
        XCTAssertEqual(plan.board.id, "p0")
        XCTAssertEqual(plan.alight.id, "p2")
        XCTAssertGreaterThan(plan.busMeters, 50, "un tramo en bus de menos de 50 m no es un viaje")
        XCTAssertEqual(plan.coordinates.count,
                       plan.walkToBoard.count + plan.bus.count + plan.walkToDestination.count)
    }

    func testRespetaElSentidoDelRecorrido() {
        // Destino en el paradero inicial y origen en el final: no hay viaje
        // posible, porque el feed describe un solo sentido.
        let ruta = rutaSintetica()
        let candidatos = TransitItinerary.candidates(in: [ruta],
                                                     origin: ruta.shape.last!,
                                                     destination: ruta.shape.first!,
                                                     radius: 300)
        XCTAssertTrue(candidatos.isEmpty, "no debe invertirse el sentido del recorrido")
    }

    func testSinParaderosCercaNoHayCandidatos() {
        // Origen y destino LEJOS de todos los paraderos: el radio es la
        // caminata máxima admitida hasta un paradero, así que sin paraderos
        // dentro del radio no hay subida posible.
        let ruta = rutaSintetica()
        let lejos = CLLocationCoordinate2D(latitude: -8.20, longitude: -79.20)
        let candidatos = TransitItinerary.candidates(in: [ruta],
                                                     origin: lejos,
                                                     destination: lejos,
                                                     radius: 300)
        XCTAssertTrue(candidatos.isEmpty)
    }

    func testSubirSobreElParaderoValeConRadioMinimo() {
        // Documenta la semántica real del radio: mide la caminata hasta el
        // paradero, no el trayecto. Si el usuario está parado SOBRE el
        // paradero de subida y su destino cae sobre otro paradero de la misma
        // línea, el viaje es válido aunque el radio sea diminuto.
        let ruta = rutaSintetica()
        let candidatos = TransitItinerary.candidates(in: [ruta],
                                                     origin: ruta.shape.first!,
                                                     destination: ruta.shape.last!,
                                                     radius: 1)
        XCTAssertEqual(candidatos.first?.board.id, "p0")
        XCTAssertEqual(candidatos.first?.alight.id, "p2")
    }

    func testRutaSinGeometriaSeIgnora() {
        let ruta = RutaGTFS(id: "R0", linea: "X", variante: "", recorrido: "—",
                            empresa: "—", colorHex: "000000", color: .black,
                            shape: [], paraderos: [],
                            duracionMin: 0, headwayMin: 0, precio: 0,
                            distanciaKm: 0, distanciaUTPMetros: .infinity)
        XCTAssertTrue(TransitItinerary.candidates(in: [ruta], origin: inicioCualquiera,
                                                  destination: inicioCualquiera, radius: 500).isEmpty)
    }

    private func line(_ id: String, _ points: [CLLocationCoordinate2D], headway: Int = 6,
                      duration: Int = 10) -> RutaGTFS {
        RutaGTFS(id: id, linea: id, variante: "", recorrido: id, empresa: "Test",
                 colorHex: "00CC00", color: .green, shape: points,
                 paraderos: points.enumerated().map {
                     ParaderoGTFS(id: "\(id)-\($0.offset)", nombre: "\(id)-\($0.offset)",
                                  lat: $0.element.latitude, lon: $0.element.longitude)
                 }, duracionMin: duration, headwayMin: headway, precio: 2,
                 distanciaKm: PolylineMatching.totalLengthMeters(points) / 1000, distanciaUTPMetros: 0)
    }
    private var transferNetwork: (RutaGTFS, RutaGTFS) {
        let start = CLLocationCoordinate2D(latitude: -8.10, longitude: -79.04)
        let exit = CLLocationCoordinate2D(latitude: -8.10, longitude: -79.03)
        let enter = CLLocationCoordinate2D(latitude: -8.099, longitude: -79.03)
        let end = CLLocationCoordinate2D(latitude: -8.09, longitude: -79.03)
        return (line("A", [start, exit]), line("B", [enter, end]))
    }

    func testEncuentraDosMicrosSinLineaDirecta() throws {
        let (a, b) = transferNetwork
        let plans = TransitItinerary.candidates(in: [a, b], origin: a.shape[0], destination: b.shape[1], radius: 50)
        let plan = try XCTUnwrap(plans.first)
        let transfer = try XCTUnwrap(plan.transfer)
        XCTAssertEqual(plan.route.id, "A")
        XCTAssertEqual(transfer.route.id, "B")
        XCTAssertEqual(plan.firstAlight.id, "A-1")
        XCTAssertEqual(transfer.board.id, "B-0")
        XCTAssertEqual(plan.alight.id, "B-1")
        XCTAssertGreaterThan(plan.transferWalkMeters, 100)
        XCTAssertLessThan(plan.transferWalkMeters, 120)
        XCTAssertEqual(plan.busMeters, plan.firstBusMeters + transfer.busMeters, accuracy: 0.001)
        XCTAssertEqual(plan.coordinates.count, plan.walkToBoard.count + plan.bus.count + transfer.walk.count
                       + transfer.bus.count + plan.walkToDestination.count)
        XCTAssertEqual(plan.remainingSeconds(after: 0), plan.totalSeconds, accuracy: 0.001)
        XCTAssertEqual(plan.remainingSeconds(after: 100_000), 0)
        XCTAssertEqual(plan.transferWaitSeconds, 300)
    }

    func testTransbordoNoInvierteSegundoMicro() {
        let (a, b) = transferNetwork
        let reversed = line("B", b.shape.reversed())
        XCTAssertTrue(TransitItinerary.candidates(in: [a, reversed], origin: a.shape[0],
                                                 destination: b.shape[1], radius: 50).isEmpty)
    }

    func testTransbordoNoInviertePrimerMicro() {
        let (a, b) = transferNetwork
        let reversed = line("A", a.shape.reversed())
        XCTAssertTrue(TransitItinerary.candidates(in: [reversed, b], origin: a.shape[0],
                                                 destination: b.shape[1], radius: 50).isEmpty)
    }

    func testRechazaConexionDemasiadoLejana() {
        let (a, b) = transferNetwork
        let far = line("B", [CLLocationCoordinate2D(latitude: -8.095, longitude: -79.03), b.shape[1]])
        XCTAssertTrue(TransitItinerary.candidates(in: [a, far], origin: a.shape[0],
                                                 destination: b.shape[1], radius: 50).isEmpty)
    }

    func testNoProponeCambiarAlMismoRecorrido() {
        let a = rutaSintetica()
        let plans = TransitItinerary.candidates(in: [a], origin: a.shape[0], destination: a.shape.last!, radius: 50)
        XCTAssertFalse(plans.isEmpty)
        XCTAssertTrue(plans.allSatisfy { $0.transfer == nil })
    }

    func testPrefiereDirectoCuandoLosTiemposSonParecidos() throws {
        let (a, b) = transferNetwork
        let direct = line("Direct", [a.shape[0], a.shape[1], b.shape[0], b.shape[1]])
        let plans = TransitItinerary.candidates(in: [a, b, direct], origin: a.shape[0], destination: b.shape[1], radius: 50)
        XCTAssertNil(try XCTUnwrap(plans.first).transfer)
        XCTAssertTrue(plans.contains { $0.route.id == "A" && $0.transfer?.route.id == "B" })
    }

    func testPrefiereTransbordoAnteUnDesvioDirectoLargo() throws {
        let (a, b) = transferNetwork
        let direct = line("Detour", [a.shape[0], CLLocationCoordinate2D(latitude: -8.30, longitude: -79.20), b.shape[1]])
        let plans = TransitItinerary.candidates(in: [a, b, direct], origin: a.shape[0], destination: b.shape[1], radius: 50)
        XCTAssertNotNil(try XCTUnwrap(plans.first).transfer)
    }

    func testRechazaCaminataRealDeConexionSuperiorAlLimite() throws {
        let (a, b) = transferNetwork
        var plan = try XCTUnwrap(TransitItinerary.candidates(in: [a, b], origin: a.shape[0],
                                                           destination: b.shape[1], radius: 50).first)
        plan.transfer?.walk = [a.shape[1], CLLocationCoordinate2D(latitude: -8.11, longitude: -79.03), b.shape[0]]
        XCTAssertFalse(plan.walkingWithinTransferLimit)
    }

    func testPlanificaConElFeedIncluido() async throws {
        let routes = await GTFSRepository.shared.rutas()
        let route = try XCTUnwrap(routes.first { $0.paraderos.count > 3 })
        let start = Date()
        let plans = await TransitPlanner.shared.candidates(in: routes, origin: route.paraderos.first!.coordinate,
                                                           destination: route.paraderos.last!.coordinate, radius: 800)
        XCTAssertFalse(plans.isEmpty)
        XCTAssertTrue(plans.allSatisfy { $0.walkingWithinTransferLimit && $0.busMeters > 50 })
        XCTAssertLessThan(Date().timeIntervalSince(start), 10, "La búsqueda local no debe tardar decenas de segundos")
        print("[TransitPlanner] \(routes.count) rutas: \(plans.count) candidatos en \(Date().timeIntervalSince(start)) s")
    }

    @MainActor
    func testRendimientoRadio1600() async throws {
        let routes = await GTFSRepository.shared.rutas()
        let route = try XCTUnwrap(routes.first { $0.paraderos.count > 3 })
        let planner = TransitPlanner()
        for iteration in 0..<2 {
            let start = Date()
            let plans = await planner.candidates(in: routes,
                origin: route.paraderos.first!.coordinate, destination: route.paraderos.last!.coordinate, radius: 1600)
            let elapsed = Date().timeIntervalSince(start)
            XCTAssertLessThan(elapsed, 8, "La consulta local de 1600 m no debe volver al barrido lento")
            XCTAssertFalse(plans.isEmpty)
            let signatures = plans.prefix(4).map {
                "\($0.route.id):\($0.board.id):\($0.firstAlight.id):\($0.transfer?.route.id ?? "-"):\($0.transfer?.board.id ?? "-"):\($0.alight.id) ETA=\($0.totalSeconds)"
            }
            XCTContext.runActivity(named: "BENCH1600 pass=\(iteration) seconds=\(elapsed) count=\(plans.count)") { activity in
                let attachment = XCTAttachment(string: signatures.joined(separator: "\n"))
                attachment.lifetime = .keepAlways
                activity.add(attachment)
            }
        }
    }

    func testCacheInvalidaGeometriaModificadaConMismoID() async throws {
        let planner = TransitPlanner()
        let route = rutaSintetica()
        let original = await planner.candidates(in: [route], origin: route.shape.first!,
                                                destination: route.shape.last!, radius: 300)
        XCTAssertFalse(original.isEmpty)
        let changed = RutaGTFS(id: route.id, linea: route.linea, variante: route.variante,
            recorrido: route.recorrido, empresa: route.empresa, colorHex: route.colorHex, color: route.color,
            shape: route.shape.map { CLLocationCoordinate2D(latitude: $0.latitude + 0.1, longitude: $0.longitude) },
            paraderos: route.paraderos, duracionMin: route.duracionMin, headwayMin: route.headwayMin,
            precio: route.precio, distanciaKm: route.distanciaKm, distanciaUTPMetros: route.distanciaUTPMetros)
        let invalid = await planner.candidates(in: [changed], origin: route.shape.first!,
                                               destination: route.shape.last!, radius: 300)
        XCTAssertTrue(invalid.isEmpty, "No reutilizar paraderos proyectados sobre un shape anterior")
    }

    func testOrdenOptimizadoCoincideConEnumeracionDirecta() throws {
        let route = line("Oracle", rutaSintetica().shape)
        let origin = CLLocationCoordinate2D(latitude: -8.1003, longitude: -79.0401)
        let destination = CLLocationCoordinate2D(latitude: -8.0997, longitude: -79.0299)
        let radius = 500.0
        var reference: [TransitItinerary] = []
        for board in route.paraderos.indices {
            for alight in route.paraderos.indices where alight > board {
                let plan = TransitItinerary(route: route, board: route.paraderos[board], alight: route.paraderos[alight],
                    walkToBoard: [origin, route.shape[board]], bus: Array(route.shape[board...alight]),
                    walkToDestination: [route.shape[alight], destination])
                if plan.walkToBoardMeters <= radius && plan.walkToDestinationMeters <= radius && plan.busMeters > 50 {
                    reference.append(plan)
                }
            }
        }
        reference.sort { $0.totalSeconds < $1.totalSeconds }
        let optimized = TransitItinerary.candidates(in: [route], origin: origin, destination: destination, radius: radius)
        XCTAssertEqual(optimized.count, min(32, reference.count))
        for (actual, expected) in zip(optimized, reference) {
            XCTAssertEqual(actual.board.id, expected.board.id)
            XCTAssertEqual(actual.alight.id, expected.alight.id)
            XCTAssertEqual(actual.totalSeconds, expected.totalSeconds, accuracy: 0.001)
        }
    }

    func testCaminatasSeConsultanEnParaleloYRespaldoSeIdentifica() async throws {
        let (a, b) = transferNetwork
        let plan = try XCTUnwrap(TransitItinerary.candidates(in: [a, b], origin: a.shape[0],
                                                           destination: b.shape[1], radius: 50).first)
        let probe = DirectionsProbe()
        let service = RouteCalculationService(loader: { request in try await probe.load(request, fail: false) })
        let resolved = await plan.withWalkingDirections(using: service)
        let concurrency = await probe.maximumConcurrent
        XCTAssertEqual(concurrency, 3, "Las tres caminatas del mismo viaje no deben esperarse en serie")
        XCTAssertFalse(resolved.walkingApproximate)
        let failing = RouteCalculationService(loader: { _ in throw RouteCalculationError.timedOut })
        let approximate = await plan.withWalkingDirections(using: failing)
        XCTAssertTrue(approximate.walkingApproximate)
        XCTAssertEqual(approximate.route.id, plan.route.id)
        XCTAssertEqual(approximate.transfer?.route.id, plan.transfer?.route.id)
    }

    func testCacheDeCaminataRespetaExtremosModoYCancelacion() async throws {
        let probe = DirectionsProbe()
        let service = RouteCalculationService(loader: { request in try await probe.load(request, fail: false) })
        let points = rutaSintetica().shape
        _ = try await service.calculateRoute(from: points[0], to: points[5], transportType: .walking)
        _ = try await service.calculateRoute(from: points[0], to: points[5], transportType: .walking)
        let firstCount = await probe.calls
        XCTAssertEqual(firstCount, 1)
        _ = try await service.calculateRoute(from: points[0], to: points[6], transportType: .walking)
        _ = try await service.calculateRoute(from: points[0], to: points[5], transportType: .automobile)
        let secondCount = await probe.calls
        XCTAssertEqual(secondCount, 3)
        let pending = Task { try await service.calculateRoute(from: points[1], to: points[8], transportType: .walking) }
        try await Task.sleep(for: .milliseconds(10))
        pending.cancel()
        do {
            _ = try await pending.value
            XCTFail("La cancelación debe llegar a la petición de caminata")
        } catch is CancellationError {} catch { XCTFail("Cancelación inesperada: \(error)") }
        let cancelled = await probe.cancelled
        XCTAssertEqual(cancelled, 1)
    }

    func testTransbordoOptimizadoCoincideConBusquedaExhaustiva() throws {
        let a = line("A", [-79.06, -79.05, -79.04, -79.03].map { CLLocationCoordinate2D(latitude: -8.1, longitude: $0) })
        let b = line("B", [-8.1, -8.098, -8.096, -8.092, -8.085].map { CLLocationCoordinate2D(latitude: $0, longitude: -79.029) })
        let origin = a.shape.first!, destination = b.shape.last!, radius = 1400.0
        var reference: [TransitItinerary] = []
        for board in a.paraderos.indices {
            for exit in a.paraderos.indices where exit > board {
                for enter in b.paraderos.indices {
                    for alight in b.paraderos.indices where alight > enter {
                        var plan = TransitItinerary(route: a, board: a.paraderos[board], alight: a.paraderos[exit],
                            walkToBoard: [origin, a.shape[board]], bus: Array(a.shape[board...exit]),
                            walkToDestination: [b.shape[alight], destination])
                        let bus = Array(b.shape[enter...alight])
                        plan.transfer = TransitTransfer(route: b, board: b.paraderos[enter], alight: b.paraderos[alight],
                            walk: [a.shape[exit], b.shape[enter]], bus: bus, busDibujo: bus,
                            busMeters: PolylineMatching.totalLengthMeters(bus),
                            busSpeed: min(14, max(3, b.distanciaKm * 1000 / Double(b.duracionMin * 60))))
                        if plan.walkToBoardMeters <= radius && plan.walkToDestinationMeters <= radius && plan.walkingWithinTransferLimit {
                            reference.append(plan)
                        }
                    }
                }
            }
        }
        let expected = try XCTUnwrap(reference.min { $0.totalSeconds < $1.totalSeconds })
        let actual = try XCTUnwrap(TransitItinerary.candidates(in: [a, b], origin: origin,
                                                              destination: destination, radius: radius).first)
        XCTAssertEqual(actual.board.id, expected.board.id)
        XCTAssertEqual(actual.firstAlight.id, expected.firstAlight.id)
        XCTAssertEqual(actual.transfer?.board.id, expected.transfer?.board.id)
        XCTAssertEqual(actual.alight.id, expected.alight.id)
        XCTAssertEqual(actual.totalSeconds, expected.totalSeconds, accuracy: 0.01)
    }

    @MainActor
    func testPlazoDeDirectionsCancelaYDescartaRespuestaTardia() async throws {
        var callback: PendingDirections.Completion?
        var cancellations = 0
        let pending = PendingDirections(start: { callback = $0 }, cancel: { cancellations += 1 })
        let start = Date()
        do {
            _ = try await pending.run(timeout: 0.02)
            XCTFail("No debe esperar indefinidamente una respuesta que no llega")
        } catch {
            XCTAssertEqual(error as? RouteCalculationError, .timedOut)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        XCTAssertEqual(cancellations, 1)
        callback?(.failure(RouteCalculationError.noRoutesAvailable))
        await Task.yield()
        XCTAssertEqual(cancellations, 1, "El callback tardío no debe finalizar dos veces")
    }

    @MainActor
    func testCancelarDirectionsNoEsperaElTimeout() async throws {
        let started = expectation(description: "request started")
        var cancellations = 0
        let pending = PendingDirections(start: { _ in started.fulfill() }, cancel: { cancellations += 1 })
        let task = Task { try await pending.run(timeout: 10) }
        await fulfillment(of: [started], timeout: 1)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Se esperaba cancelación")
        } catch is CancellationError {} catch { XCTFail("Error inesperado: \(error)") }
        XCTAssertEqual(cancellations, 1)
    }

    func testCacheDeCaminatasExpiraYNoGuardaFallos() async throws {
        let clock = DirectionsTestClock()
        let probe = DirectionsProbe()
        let service = RouteCalculationService(loader: { request in try await probe.load(request, fail: false) },
                                              now: { clock.date() })
        let points = rutaSintetica().shape
        _ = try await service.calculateRoute(from: points[0], to: points[5], transportType: .walking)
        clock.advance(301)
        _ = try await service.calculateRoute(from: points[0], to: points[5], transportType: .walking)
        let calls = await probe.calls
        XCTAssertEqual(calls, 2)
        let failedProbe = DirectionsProbe()
        let failing = RouteCalculationService(loader: { request in try await failedProbe.load(request, fail: true) })
        for _ in 0..<2 {
            do {
                _ = try await failing.calculateRoute(from: points[0], to: points[5], transportType: .walking)
                XCTFail("Se esperaba fallo")
            } catch { XCTAssertEqual(error as? RouteCalculationError, .noRoutesAvailable) }
        }
        let failures = await failedProbe.calls
        XCTAssertEqual(failures, 2)
    }

    func testAlternativasIncluyenZ1EntreUTPYHospitalFlorenciaDeMora() async throws {
        let catalog = try await GTFSRepository.shared.cargarCatalogo()
        let planner = TransitPlanner()
        let hospital = CLLocationCoordinate2D(latitude: -8.07962, longitude: -79.02429)
        let options = await planner.options(in: catalog, origin: GTFSRepository.coordenadaUTP,
                                            destination: hospital, radius: 1600)
        let z1 = try XCTUnwrap(options.alternatives.first {
            $0.route.id == "17434307" && $0.transfer == nil
        })
        XCTAssertEqual(z1.route.letraTransporte, "Z1")
        XCTAssertLessThan(z1.walkToBoardMeters, 150)
        XCTAssertLessThan(z1.walkToDestinationMeters, 200)
        XCTAssertGreaterThan(z1.busMeters, 50)
        XCTAssertEqual(Set(options.alternatives.map(\.optionID)).count, options.alternatives.count)

        let variants = await planner.candidates(for: z1.routeIDs, in: catalog,
            origin: GTFSRepository.coordenadaUTP, destination: hospital, radius: 1600)
        XCTAssertFalse(variants.isEmpty)
        XCTAssertTrue(variants.allSatisfy { $0.routeIDs == z1.routeIDs })
    }

    func testAlternativasNoSePierdenEntreVariantesDeLaMismaLinea() async throws {
        let points = (0...40).map {
            CLLocationCoordinate2D(latitude: -8.1, longitude: -79.04 + Double($0) * 0.001)
        }
        let fast = line("fast", points)
        let slow = RutaGTFS(id: "slow", linea: "slow", variante: "", recorrido: "slow", empresa: "Test",
            colorHex: "00CC00", color: .green, shape: points, paraderos: fast.paraderos,
            duracionMin: 100, headwayMin: 6, precio: 2, distanciaKm: fast.distanciaKm, distanciaUTPMetros: 0)
        let catalog = GTFSRouteCatalog(routes: [fast, slow])
        let options = await TransitPlanner().options(in: catalog, origin: points.first!,
            destination: points.last!, radius: 1600)
        XCTAssertEqual(options.candidates.count, 32)
        XCTAssertTrue(options.candidates.allSatisfy { $0.route.id == fast.id && $0.transfer == nil })
        let direct = options.alternatives.filter { $0.transfer == nil }
        XCTAssertEqual(Set(direct.map { $0.route.id }), Set(["fast", "slow"]))
    }

    func testElegirTransbordoConservaLaCombinacionYElOrdenDeLineas() async {
        let (a, b) = transferNetwork
        let catalog = GTFSRouteCatalog(routes: [a, b])
        let planner = TransitPlanner()
        let plans = await planner.candidates(for: [a.id, b.id], in: catalog,
            origin: a.shape[0], destination: b.shape[1], radius: 50)
        XCTAssertFalse(plans.isEmpty)
        XCTAssertTrue(plans.allSatisfy { $0.route.id == a.id && $0.transfer?.route.id == b.id })
        let reversed = await planner.candidates(for: [b.id, a.id], in: catalog,
            origin: a.shape[0], destination: b.shape[1], radius: 50)
        XCTAssertTrue(reversed.isEmpty)
    }

    func testUnaOpcionGanadoraAgrupaLasTresCategoriasSinRellenarElCarrusel() async throws {
        let route = rutaSintetica()
        let options = await TransitPlanner().options(in: GTFSRouteCatalog(routes: [route]),
            origin: route.shape.first!, destination: route.shape.last!, radius: 1)
        let only = try XCTUnwrap(options.highlights.first)
        XCTAssertEqual(options.highlights.count, 1)
        XCTAssertEqual(only.categories, [.recommended, .fastest, .closestBoarding])
        XCTAssertEqual(only.plan.estimatedJourneySeconds - only.plan.totalSeconds, 150, accuracy: 0.01)
    }

    func testMasCercanaPriorizaLaSubidaAunqueSeCamineMasDespuesDeBajar() async throws {
        let origin = CLLocationCoordinate2D(latitude: -8.1, longitude: -79.04)
        let destination = CLLocationCoordinate2D(latitude: -8.1, longitude: -79.02)
        let near = line("near", [origin, CLLocationCoordinate2D(latitude: -8.097, longitude: -79.02)])
        let lessWalking = line("lessWalking", [CLLocationCoordinate2D(latitude: -8.099, longitude: -79.04), destination])
        let options = await TransitPlanner().options(in: GTFSRouteCatalog(routes: [near, lessWalking]),
            origin: origin, destination: destination, radius: 400)
        let closest = try XCTUnwrap(options.highlights.first { $0.categories.contains(.closestBoarding) })
        XCTAssertEqual(closest.plan.route.id, "near")
        XCTAssertEqual(closest.plan.walkToBoardMeters, 0, accuracy: 0.01)
        XCTAssertGreaterThan(closest.plan.walkToDestinationMeters, 300)
        XCTAssertTrue(closest.categories.contains(.recommended))
        XCTAssertLessThanOrEqual(options.highlights.count, 3)
    }

    func testRecomiendaLaSubidaCercanaAunqueLaMasRapidaExijaCaminar1200Metros() async throws {
        let origin = CLLocationCoordinate2D(latitude: -8.1, longitude: -79.04)
        let destination = CLLocationCoordinate2D(latitude: -8.08, longitude: -79.04)
        let near = line("near", [origin,
            CLLocationCoordinate2D(latitude: -8.13, longitude: -79.07), destination], duration: 40)
        let fast = line("fast", [CLLocationCoordinate2D(latitude: -8.1, longitude: -79.029),
                                destination], headway: 0, duration: 1)
        let options = await TransitPlanner().options(in: GTFSRouteCatalog(routes: [near, fast]),
            origin: origin, destination: destination, radius: 1600)
        let recommended = try XCTUnwrap(options.highlights.first { $0.categories.contains(.recommended) })
        let fastest = try XCTUnwrap(options.highlights.first { $0.categories.contains(.fastest) })
        XCTAssertEqual(recommended.plan.route.id, "near")
        XCTAssertEqual(recommended.plan.walkToBoardMeters, 0, accuracy: 0.01)
        XCTAssertTrue(recommended.categories.contains(.closestBoarding))
        XCTAssertEqual(options.highlights.first?.plan.optionID, recommended.plan.optionID)
        XCTAssertEqual(fastest.plan.route.id, "fast")
        XCTAssertGreaterThan(fastest.plan.walkToBoardMeters, 1100)
        XCTAssertLessThan(fastest.plan.walkToBoardMeters, 1300)
        XCTAssertLessThan(fastest.plan.estimatedJourneySeconds, recommended.plan.estimatedJourneySeconds)
        XCTAssertEqual(options.highlights.count, 2, "No duplicar Recomendada y Más cercana")
    }

    func testMasRapidaIncluyeLaEsperaDelPrimerMicro() async throws {
        let points = rutaSintetica().shape
        let infrequent = line("infrequent", points, headway: 40, duration: 1)
        let frequent = line("frequent", points, headway: 2)
        let options = await TransitPlanner().options(in: GTFSRouteCatalog(routes: [infrequent, frequent]),
            origin: points.first!, destination: points.last!, radius: 1)
        let fastest = try XCTUnwrap(options.highlights.first { $0.categories.contains(.fastest) })
        XCTAssertEqual(fastest.plan.route.id, "frequent")
    }

    func testUnDirectoCortoEvitaTransbordosEnTodasLasCategoriasYEnElRespaldo() async throws {
        let (first, second) = transferNetwork
        let a = line("A", first.shape, headway: 2, duration: 2)
        let b = line("B", second.shape, headway: 2, duration: 2)
        let direct = line("direct", [a.shape[0],
            CLLocationCoordinate2D(latitude: -8.12, longitude: -79.05), b.shape[1]], headway: 2)
        let options = await TransitPlanner().options(in: GTFSRouteCatalog(routes: [a, b, direct]),
            origin: a.shape[0], destination: b.shape[1], radius: 50)
        let recommended = try XCTUnwrap(options.highlights.first { $0.categories.contains(.recommended) })
        let fastest = try XCTUnwrap(options.highlights.first { $0.categories.contains(.fastest) })
        XCTAssertEqual(recommended.plan.route.id, "direct")
        XCTAssertNil(recommended.plan.transfer)
        XCTAssertNil(fastest.plan.transfer)
        XCTAssertTrue(options.highlights.allSatisfy { $0.plan.transfer == nil })
        XCTAssertTrue(options.alternatives.allSatisfy { $0.transfer == nil })
        XCTAssertTrue(options.candidates.allSatisfy { $0.transfer == nil },
                      "Un fallo de Directions no debe reintroducir el transbordo descartado")
    }

    func testNoOfreceUnMicroDePocosMetrosParaSubirDespuesALaB() async throws {
        let origin = CLLocationCoordinate2D(latitude: -8.1, longitude: -79.04)
        let connection = CLLocationCoordinate2D(latitude: -8.1, longitude: -79.039)
        let destination = CLLocationCoordinate2D(latitude: -8.08, longitude: -79.039)
        let feeder = line("feeder", [origin, connection], headway: 0, duration: 1)
        let b = line("B", [connection, destination], headway: 2)
        let options = await TransitPlanner().options(in: GTFSRouteCatalog(routes: [feeder, b]),
            origin: origin, destination: destination, radius: 200)
        let recommended = try XCTUnwrap(options.highlights.first { $0.categories.contains(.recommended) })
        XCTAssertEqual(recommended.plan.route.id, "B")
        XCTAssertNil(recommended.plan.transfer)
        XCTAssertTrue(options.alternatives.allSatisfy { $0.transfer == nil })
        XCTAssertTrue(options.candidates.allSatisfy { $0.transfer == nil })
    }

    func testConservaTransbordosConTramosUtilesCuandoNoExisteDirecto() async throws {
        let (a, b) = transferNetwork
        let options = await TransitPlanner().options(in: GTFSRouteCatalog(routes: [a, b]),
            origin: a.shape[0], destination: b.shape[1], radius: 50)
        let recommended = try XCTUnwrap(options.highlights.first { $0.categories.contains(.recommended) })
        let transfer = try XCTUnwrap(recommended.plan.transfer)
        XCTAssertGreaterThan(recommended.plan.firstBusMeters, TransitItinerary.minimumTransferRideMeters)
        XCTAssertGreaterThan(transfer.busMeters, TransitItinerary.minimumTransferRideMeters)
    }

    func testSoloOfreceTransbordoFrenteAUnDirectoLargoConAhorroImportante() async throws {
        let (a, b) = transferNetwork
        let detour = line("detour", [a.shape[0],
            CLLocationCoordinate2D(latitude: -8.4, longitude: -79.4), b.shape[1]])
        let options = await TransitPlanner().options(in: GTFSRouteCatalog(routes: [a, b, detour]),
            origin: a.shape[0], destination: b.shape[1], radius: 50)
        let recommended = try XCTUnwrap(options.highlights.first { $0.categories.contains(.recommended) })
        let direct = try XCTUnwrap(options.alternatives.first { $0.route.id == "detour" && $0.transfer == nil })
        XCTAssertNotNil(recommended.plan.transfer)
        XCTAssertGreaterThan(direct.estimatedJourneySeconds, 45 * 60)
        XCTAssertGreaterThanOrEqual(direct.estimatedJourneySeconds - recommended.plan.estimatedJourneySeconds,
                                    max(15 * 60, direct.estimatedJourneySeconds * 0.25))
    }

    func testUnaLineaConOtraSubidaConservaLaOpcionCercana() async throws {
        let origin = CLLocationCoordinate2D(latitude: -8.1, longitude: -79.04)
        let destination = CLLocationCoordinate2D(latitude: -8.1, longitude: -79.02)
        let route = line("loop", [origin,
            CLLocationCoordinate2D(latitude: -8.2, longitude: -79.04),
            CLLocationCoordinate2D(latitude: -8.1, longitude: -79.035), destination])
        let options = await TransitPlanner().options(in: GTFSRouteCatalog(routes: [route]),
            origin: origin, destination: destination, radius: 600)
        let closest = try XCTUnwrap(options.highlights.first { $0.categories.contains(.closestBoarding) })
        let fastest = try XCTUnwrap(options.highlights.first { $0.categories.contains(.fastest) })
        XCTAssertEqual(closest.plan.board.id, "loop-0")
        XCTAssertEqual(fastest.plan.board.id, "loop-2")
        XCTAssertNotEqual(closest.plan.optionID, fastest.plan.optionID)
        XCTAssertEqual(closest.plan.routeIDs, fastest.plan.routeIDs)
        XCTAssertEqual(Set(options.highlights.map { $0.plan.optionID }).count, options.highlights.count)
        XCTAssertTrue(closest.categories.contains(.recommended))
        XCTAssertFalse(fastest.categories.contains(.recommended),
                       "Ahorrar tiempo no debe sustituir la recomendación de subida cercana")
    }

    @MainActor
    func testElegirLaSubidaCercanaNoLaSustituyePorLaMasRapidaDeLaMismaLinea() async throws {
        let origin = CLLocationCoordinate2D(latitude: -8.1, longitude: -79.04)
        let destination = CLLocationCoordinate2D(latitude: -8.1, longitude: -79.02)
        let route = line("loop", [origin,
            CLLocationCoordinate2D(latitude: -8.2, longitude: -79.04),
            CLLocationCoordinate2D(latitude: -8.1, longitude: -79.035), destination])
        let vm = MapaViewModel(locationService: MapaGPSPrueba(),
            routeService: RouteCalculationService(loader: { request in
                let points = [request.source!.placemark.coordinate, request.destination!.placemark.coordinate]
                return CalculatedRoute(polyline: MKPolyline(coordinates: points, count: points.count),
                    expectedTravelTime: 1, distance: PolylineMatching.totalLengthMeters(points), steps: [])
            }), repositorioGTFS: MapaGTFSPrueba(feed: [route]), crearProveedorReal: { nil })
        defer { vm.detener() }
        vm.userRealCoordinate = origin
        vm.calcularRutaHacia(destination)
        for _ in 0..<400 where vm.calculandoItinerario { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(vm.calculandoItinerario)
        let closest = try XCTUnwrap(vm.rutasDestacadas.first { $0.categories.contains(.closestBoarding) }?.plan)
        XCTAssertEqual(vm.itinerario?.board.id, "loop-0")
        let fastest = try XCTUnwrap(vm.rutasDestacadas.first { $0.categories.contains(.fastest) }?.plan)
        vm.seleccionarAlternativa(fastest)
        for _ in 0..<400 where vm.calculandoItinerario { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(vm.calculandoItinerario)
        XCTAssertEqual(vm.itinerario?.board.id, "loop-2")
        vm.seleccionarAlternativa(closest)
        for _ in 0..<400 where vm.calculandoItinerario { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(vm.calculandoItinerario)
        XCTAssertEqual(vm.itinerario?.board.id, "loop-0")
        XCTAssertEqual(vm.itinerario?.optionID, closest.optionID)
        XCTAssertLessThanOrEqual(vm.opcionesResumen.count, 3)
    }

    func testMasCercanaConTransbordoConservaUnaSubidaQueElTiempoDescartaria() async throws {
        let origin = CLLocationCoordinate2D(latitude: -8.1, longitude: -79.04)
        let exit = CLLocationCoordinate2D(latitude: -8.1, longitude: -79.02)
        let end = CLLocationCoordinate2D(latitude: -8.08, longitude: -79.02)
        let a = line("A", [origin, CLLocationCoordinate2D(latitude: -8.2, longitude: -79.04),
            CLLocationCoordinate2D(latitude: -8.1, longitude: -79.035), exit])
        let b = line("B", [exit, end])
        let options = await TransitPlanner().options(in: GTFSRouteCatalog(routes: [a, b]),
            origin: origin, destination: end, radius: 600)
        let closest = try XCTUnwrap(options.highlights.first { $0.categories.contains(.closestBoarding) })
        let fastest = try XCTUnwrap(options.highlights.first { $0.categories.contains(.fastest) })
        XCTAssertEqual(closest.plan.routeIDs, ["A", "B"])
        XCTAssertEqual(closest.plan.board.id, "A-0")
        XCTAssertEqual(fastest.plan.board.id, "A-2")
        XCTAssertLessThanOrEqual(options.highlights.count, 3)
    }

    private var inicioCualquiera: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: -8.10, longitude: -79.04)
    }
}

@MainActor
final class MapaCarruselRutasTests: XCTestCase {
    private func ruta(_ id: String, offset: Double) -> RutaGTFS {
        let points = [0.0, 0.005, 0.01].map {
            CLLocationCoordinate2D(latitude: -8.1 + offset, longitude: -79.04 + $0)
        }
        return RutaGTFS(id: id, linea: id, variante: id, recorrido: id, empresa: "Test",
            colorHex: "00CC00", color: .green, shape: points,
            paraderos: points.enumerated().map {
                ParaderoGTFS(id: "\(id)-\($0.offset)", nombre: "\(id)-\($0.offset)",
                             lat: $0.element.latitude, lon: $0.element.longitude)
            }, duracionMin: 10, headwayMin: 6, precio: 2.5, distanciaKm: 1.1, distanciaUTPMetros: 0)
    }

    private func esperar(_ condicion: () -> Bool) async throws {
        for _ in 0..<400 {
            if condicion() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("No terminó la selección de ruta")
        throw CancellationError()
    }

    private func preparar(loader: @escaping RouteCalculationService.Loader) async throws -> MapaViewModel {
        let routes = [ruta("A", offset: 0), ruta("B", offset: 0.0002), ruta("C", offset: 0.0004)]
        let vm = MapaViewModel(locationService: MapaGPSPrueba(),
            routeService: RouteCalculationService(loader: loader),
            repositorioGTFS: MapaGTFSPrueba(feed: routes), crearProveedorReal: { nil })
        vm.userRealCoordinate = routes[0].shape[0]
        vm.calcularRutaHacia(routes[0].shape.last!)
        try await esperar { !vm.calculandoItinerario }
        XCTAssertEqual(vm.itinerario?.route.id, "A")
        return vm
    }

    func testVolverALaTarjetaActualCancelaLaSeleccionPendienteSinConsultarCaminatas() async throws {
        let probe = DirectionsProbe()
        let vm = try await preparar { try await probe.load($0, fail: false) }
        defer { vm.detener() }
        let actual = try XCTUnwrap(vm.itinerario)
        let otra = try XCTUnwrap(vm.alternativasItinerario.first { $0.routeIDs == ["B"] })
        let callsBefore = await probe.calls
        let focusBefore = vm.itinerarioFocusTick
        vm.seleccionarAlternativa(otra, diferir: true)
        XCTAssertTrue(vm.calculandoItinerario)
        XCTAssertFalse(vm.buscandoItinerarioInicial, "La guía debe seguir visible durante el cambio")
        vm.seleccionarAlternativa(actual, diferir: true)
        try await Task.sleep(for: .milliseconds(350))
        let callsAfter = await probe.calls
        XCTAssertEqual(callsBefore, callsAfter)
        XCTAssertFalse(vm.calculandoItinerario)
        XCTAssertNil(vm.seleccionandoAlternativa)
        XCTAssertEqual(vm.itinerario?.routeIDs, actual.routeIDs)
        XCTAssertEqual(vm.itinerarioFocusTick, focusBefore)
    }

    func testElCarruselEsperaLaPrimeraRutaComprobada() async throws {
        let route = ruta("A", offset: 0)
        let probe = DirectionsProbe()
        let vm = MapaViewModel(locationService: MapaGPSPrueba(),
            routeService: RouteCalculationService(loader: { request in
                try await Task.sleep(for: .milliseconds(100))
                return try await probe.load(request, fail: false)
            }), repositorioGTFS: MapaGTFSPrueba(feed: [route]), crearProveedorReal: { nil })
        defer { vm.detener() }
        vm.userRealCoordinate = route.shape[0]
        vm.calcularRutaHacia(route.shape.last!)
        try await esperar { !vm.rutasDestacadas.isEmpty }
        XCTAssertTrue(vm.calculandoItinerario)
        XCTAssertNil(vm.itinerario)
        XCTAssertTrue(vm.opcionesResumen.isEmpty,
                      "Publicar las opciones antes de instalar la ruta puede cancelar la búsqueda inicial")
        try await esperar { !vm.calculandoItinerario }
        XCTAssertFalse(vm.opcionesResumen.isEmpty)
    }

    func testSiFallaLaSubidaRecomendadaSeReintentaPorCercania() async throws {
        let routes = [ruta("A", offset: 0), ruta("B", offset: 0.0002), ruta("C", offset: 0.0004)]
        let vm = MapaViewModel(locationService: MapaGPSPrueba(),
            routeService: RouteCalculationService(loader: { request in
                let a = request.source!.placemark.coordinate, b = request.destination!.placemark.coordinate
                let fromA = abs(a.latitude + 8.1) < 0.000001 && abs(b.latitude + 8.1) < 0.000001
                let points = fromA ? [a, CLLocationCoordinate2D(latitude: -8.05, longitude: -79.035), b] : [a, b]
                return CalculatedRoute(polyline: MKPolyline(coordinates: points, count: points.count),
                    expectedTravelTime: 1, distance: PolylineMatching.totalLengthMeters(points), steps: [])
            }), repositorioGTFS: MapaGTFSPrueba(feed: routes), crearProveedorReal: { nil })
        defer { vm.detener() }
        vm.userRealCoordinate = routes[0].shape[0]
        vm.calcularRutaHacia(routes[0].shape.last!)
        try await esperar { !vm.calculandoItinerario }
        XCTAssertEqual(vm.itinerario?.route.id, "B")
        let installed = try XCTUnwrap(vm.itinerario)
        XCTAssertTrue(vm.categorias(de: installed).contains(.recommended))
        XCTAssertTrue(vm.categorias(de: installed).contains(.closestBoarding))
        XCTAssertEqual(vm.opcionesResumen.first?.optionID, installed.optionID)
    }

    func testPasarRapidoPorVariasTarjetasInstalaSoloLaUltimaLinea() async throws {
        let probe = DirectionsProbe()
        let vm = try await preparar { try await probe.load($0, fail: false) }
        defer { vm.detener() }
        let b = try XCTUnwrap(vm.alternativasItinerario.first { $0.routeIDs == ["B"] })
        let c = try XCTUnwrap(vm.alternativasItinerario.first { $0.routeIDs == ["C"] })
        let callsBefore = await probe.calls
        let focusBefore = vm.itinerarioFocusTick
        vm.seleccionarAlternativa(b, diferir: true)
        vm.seleccionarAlternativa(c, diferir: true)
        XCTAssertEqual(vm.seleccionandoAlternativa, c.optionID)
        try await esperar { !vm.calculandoItinerario }
        let callsAfter = await probe.calls
        XCTAssertEqual(vm.itinerario?.routeIDs, c.routeIDs)
        XCTAssertTrue(vm.opcionesResumen.contains { $0.optionID == c.optionID },
                      "Una elección de la lista debe seguir visible en el resumen")
        XCTAssertLessThanOrEqual(vm.opcionesResumen.count, 3)
        XCTAssertEqual(vm.itinerarioFocusTick, focusBefore + 1)
        XCTAssertEqual(callsAfter - callsBefore, 2, "Solo se consultan las dos caminatas de C")
    }

    func testUnaCaminataFueraDelLimiteConservaElPlanYElMapaAnteriores() async throws {
        let vm = try await preparar { request in
            let a = request.source!.placemark.coordinate, b = request.destination!.placemark.coordinate
            let detour = abs(a.latitude + 8.1) > 0.0003 || abs(b.latitude + 8.1) > 0.0003
            let points = detour
                ? [a, CLLocationCoordinate2D(latitude: -8.05, longitude: -79.035), b] : [a, b]
            return CalculatedRoute(polyline: MKPolyline(coordinates: points, count: points.count),
                expectedTravelTime: 1, distance: PolylineMatching.totalLengthMeters(points), steps: [])
        }
        defer { vm.detener() }
        let actual = try XCTUnwrap(vm.itinerario)
        let c = try XCTUnwrap(vm.alternativasItinerario.first { $0.routeIDs == ["C"] })
        let originalPolyline = vm.routePolyline
        vm.seleccionarAlternativa(c)
        try await esperar { !vm.calculandoItinerario }
        XCTAssertEqual(vm.itinerario?.routeIDs, actual.routeIDs)
        XCTAssertTrue(vm.routePolyline === originalPolyline)
        XCTAssertNotNil(vm.mensajeAlternativa)
        XCTAssertNil(vm.seleccionandoAlternativa)
    }
}

final class CuponNegocioTests: XCTestCase {

    private func cupon(vence: String?) -> CuponNegocio {
        CuponNegocio(codigo: "RUTA-TEST",
                     detalle: TextoBilingue(es: "2x1", en: "2x1"),
                     condiciones: TextoBilingue(es: "Mostrar en el local", en: "Show in store"),
                     vence: vence)
    }

    func testSinVencimientoEstaVigente() {
        XCTAssertTrue(cupon(vence: nil).vigente)
    }

    func testFechaPasadaNoEstaVigente() {
        XCTAssertFalse(cupon(vence: "2020-01-01").vigente)
    }

    func testFechaFuturaEstaVigente() {
        XCTAssertTrue(cupon(vence: "2099-12-31").vigente)
    }

    func testFechaInvalidaNoSeInterpretaComoVencida() {
        // Un formato inesperado no debe retirar el cupón: `fechaVencimiento`
        // devuelve nil y sin fecha límite el cupón sigue vigente.
        let c = cupon(vence: "no-es-una-fecha")
        XCTAssertNil(c.fechaVencimiento)
        XCTAssertTrue(c.vigente)
    }
}

final class ParaderosIluminadosTests: XCTestCase {

    private func ruta(_ id: String, stops: [ParaderoGTFS]) -> RutaGTFS {
        RutaGTFS(id: id, linea: "C-01", variante: "", recorrido: "—", empresa: "—",
                 colorHex: "00CC00", color: .green,
                 shape: stops.map(\.coordinate), paraderos: stops,
                 duracionMin: 10, headwayMin: 5, precio: 2.5,
                 distanciaKm: 1, distanciaUTPMetros: 100)
    }

    func testSeleccionNoDuplicaParaderos() {
        let stops = [
            ParaderoGTFS(id: "s1", nombre: "A", lat: -8.10, lon: -79.04),
            ParaderoGTFS(id: "s2", nombre: "B", lat: -8.11, lon: -79.05),
            ParaderoGTFS(id: "s3", nombre: "C", lat: -8.12, lon: -79.06)
        ]
        // Dos rutas que comparten los MISMOS paraderos: la deduplicación por
        // coordenada debe dejar tres, no seis.
        let seleccion = ParaderosIluminados.seleccionar([ruta("R1", stops: stops),
                                                         ruta("R2", stops: stops)],
                                                        cantidad: 24)
        XCTAssertEqual(seleccion.count, 3)
        let claves = Set(seleccion.map { "\(Int(($0.lat * 1e6).rounded())):\(Int(($0.lon * 1e6).rounded()))" })
        XCTAssertEqual(claves.count, seleccion.count, "no puede haber dos paraderos en el mismo punto")
    }

    func testSeleccionRespetaElTope() {
        let stops = (0..<20).map {
            ParaderoGTFS(id: "s\($0)", nombre: "P\($0)",
                         lat: -8.10 - Double($0) * 0.001, lon: -79.04)
        }
        XCTAssertLessThanOrEqual(ParaderosIluminados.seleccionar([ruta("R1", stops: stops)],
                                                                 cantidad: 8).count, 8)
    }

    func testFeedVacioDevuelveVacio() {
        XCTAssertTrue(ParaderosIluminados.seleccionar([], cantidad: 24).isEmpty)
    }

    func testCantidadCeroDevuelveVacio() {
        let stops = [ParaderoGTFS(id: "s1", nombre: "A", lat: -8.10, lon: -79.04)]
        XCTAssertTrue(ParaderosIluminados.seleccionar([ruta("R1", stops: stops)], cantidad: 0).isEmpty)
    }
}

/// Regla de orden de los tiles de Seguridad.
///
/// Es la razón de haber extraído `SeguridadLugaresModel`: mientras la regla
/// vivía dentro de la vista no había forma de comprobarla sin levantarla.
/// Estas pruebas tocan `UserDefaults` porque `LugaresStore` es el almacén real
/// del proyecto; se limpian las tres llaves antes y después de cada una.
@MainActor
final class SeguridadLugaresModelTests: XCTestCase {

    private let llaves = [LugaresStore.key, LugaresStore.respaldoKey,
                          "seguridad.tiles.v1", "seguridad.tiles.orden.v1"]

    override func setUp() {
        super.setUp()
        limpiar()
    }

    override func tearDown() {
        limpiar()
        super.tearDown()
    }

    /// Borra las llaves **y** la caché en memoria de `LugaresStore`. Sin lo
    /// segundo, cada prueba vería la lista que dejó la anterior: el almacén
    /// decodifica una sola vez por proceso.
    private func limpiar() {
        LugaresStore.invalidarCache()
        llaves.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    private func lugar(_ nombre: String, fijo: Bool = false) -> LugarGuardado {
        LugarGuardado(nombre: nombre, direccion: "—",
                      categoria: fijo ? .universidad : .otro, esFijo: fijo)
    }

    func testParaderoGuardadoConservaIdentidadAlRecargar() throws {
        let saved = LugarGuardado(nombre: "Paradero de prueba", direccion: "Trujillo",
                                 categoria: .otro, lat: -8.1, lon: -79.03, paraderoID: "stop-test")
        LugaresStore.guardar([LugaresStore.lugarUTP(), saved])
        LugaresStore.invalidarCache()
        let restored = try XCTUnwrap(LugaresStore.cargar().first { $0.id == saved.id })
        XCTAssertEqual(restored.paraderoID, "stop-test")
        let model = SeguridadLugaresModel()
        model.cargar()
        model.eliminar(restored)
        LugaresStore.invalidarCache()
        XCTAssertFalse(LugaresStore.cargar().contains { $0.id == saved.id })
    }

    func testParaderoAnteriorSinIdentificadorSigueSiendoLegible() throws {
        let saved = LugarGuardado(nombre: "Paradero anterior", direccion: "Trujillo",
                                 categoria: .otro, lat: -8.1, lon: -79.03)
        var body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as? [String: Any])
        body.removeValue(forKey: "paraderoID")
        let restored = try JSONDecoder().decode(LugarGuardado.self, from: JSONSerialization.data(withJSONObject: body))
        XCTAssertEqual(restored.nombre, saved.nombre)
        XCTAssertNil(restored.paraderoID)
        let stop = ParaderoGTFS(id: "legacy-stop", nombre: "Paradero anterior", lat: -8.1, lon: -79.03)
        XCTAssertTrue(restored.corresponde(al: stop))
    }

    func testElFijoSiempreVaPrimero() {
        // El fijo se guarda al FINAL a propósito: el modelo debe subirlo.
        let utp = lugar("UTP", fijo: true)
        LugaresStore.guardar([lugar("Plaza"), utp])

        let modelo = SeguridadLugaresModel()
        modelo.cargar()

        XCTAssertEqual(modelo.tilesActuales.first?.nombre, "UTP")
    }

    func testSinSeleccionPreviaSeEligenDosNoFijos() {
        LugaresStore.guardar([lugar("UTP", fijo: true),
                              lugar("A"), lugar("B"), lugar("C")])

        let modelo = SeguridadLugaresModel()
        modelo.cargar()

        XCTAssertEqual(modelo.tilesActuales.map(\.nombre), ["UTP", "A", "B"])
    }

    func testLaSeleccionExplicitaSeRespeta() {
        let b = lugar("B"), c = lugar("C")
        LugaresStore.guardar([lugar("UTP", fijo: true), lugar("A"), b, c])

        let modelo = SeguridadLugaresModel()
        modelo.cargar()
        modelo.reconstruirTiles(seleccion: [b.id, c.id])

        XCTAssertEqual(modelo.tilesActuales.map(\.nombre), ["UTP", "B", "C"])
    }

    func testLaSeleccionSobreviveAUnaRecarga() {
        let b = lugar("B"), c = lugar("C")
        LugaresStore.guardar([lugar("UTP", fijo: true), lugar("A"), b, c])

        let primero = SeguridadLugaresModel()
        primero.cargar()
        primero.reconstruirTiles(seleccion: [b.id, c.id])

        // Un modelo nuevo (equivale a volver a entrar a la pantalla) debe
        // reconstruir la misma selección desde lo persistido.
        let segundo = SeguridadLugaresModel()
        segundo.cargar()

        XCTAssertEqual(segundo.tilesActuales.map(\.nombre), ["UTP", "B", "C"])
    }

    func testEliminarSacaElLugarDeLosTilesYDeGuardados() {
        let a = lugar("A")
        LugaresStore.guardar([lugar("UTP", fijo: true), a])

        let modelo = SeguridadLugaresModel()
        modelo.cargar()
        XCTAssertTrue(modelo.tilesActuales.contains { $0.id == a.id })

        modelo.eliminar(a)

        XCTAssertFalse(modelo.tilesActuales.contains { $0.id == a.id })
        XCTAssertFalse(modelo.lugares.contains { $0.id == a.id })
        XCTAssertFalse(LugaresStore.cargar().contains { $0.id == a.id })
    }
}

final class RejillaEspacialTests: XCTestCase {

    /// Nube determinista de puntos alrededor de Trujillo.
    private func nube() -> [CLLocationCoordinate2D] {
        (0..<400).map { i in
            CLLocationCoordinate2D(latitude: -8.10 + Double(i % 20) * 0.001,
                                   longitude: -79.04 + Double(i / 20) * 0.001)
        }
    }

    private func clave(_ c: CLLocationCoordinate2D) -> String { "\(c.latitude),\(c.longitude)" }

    func testDevuelveLoMismoQueElBarridoLineal() {
        let puntos = nube()
        let radio = 150.0
        let rejilla = RejillaEspacial(puntos, radioMetros: radio, coordenada: { $0 })

        for consulta in puntos.prefix(40) {
            let porRejilla = Set(rejilla.cerca(de: consulta, radioMetros: radio).map(clave))
            let porFuerzaBruta = Set(puntos.filter {
                PolylineMatching.distanceMeters($0, consulta) <= radio
            }.map(clave))
            XCTAssertEqual(porRejilla, porFuerzaBruta,
                           "la rejilla y el barrido difieren en \(consulta)")
        }
    }

    func testSinVecinosDevuelveVacio() {
        let rejilla = RejillaEspacial([CLLocationCoordinate2D(latitude: -8.10, longitude: -79.04)],
                                      radioMetros: 100, coordenada: { $0 })
        let lejos = CLLocationCoordinate2D(latitude: -8.20, longitude: -79.20)
        XCTAssertTrue(rejilla.cerca(de: lejos, radioMetros: 100).isEmpty)
    }
}

/// La rejilla cambia CÓMO se busca, no QUÉ se encuentra.
///
/// Es la verificación que el informe pedía para este cambio: se compara el
/// resultado nuevo contra la lógica original escrita a mano, sobre el feed
/// real completo.
@MainActor
final class LineasPorParaderoTests: XCTestCase {

    func testLaRejillaDaElMismoResultadoQueElBarridoLineal() async {
        let feed = await GTFSRepository.shared.rutas()
        XCTAssertFalse(feed.isEmpty, "el feed embebido debe cargar")

        let visibles = ParaderosIluminados.seleccionar(feed)
        XCTAssertFalse(visibles.isEmpty)
        let porRejilla = ParaderosIluminadosView.lineasQueSirven(visibles, en: feed)

        for paradero in visibles {
            // Referencia: el criterio original, sin rejilla.
            let esperado = feed.filter { ruta in
                ruta.paraderos.contains {
                    $0.id == paradero.id
                        || PolylineMatching.distanceMeters($0.coordinate, paradero.coordinate) < 20
                }
            }.map(\.id)

            XCTAssertEqual(porRejilla[paradero.id]?.map(\.id), esperado,
                           "difiere en el paradero \(paradero.nombre)")
        }
    }
}

private actor DirectionsProbe {
    var calls = 0
    var active = 0
    var maximumConcurrent = 0
    var cancelled = 0
    func load(_ request: MKDirections.Request, fail: Bool) async throws -> CalculatedRoute {
        calls += 1
        active += 1
        maximumConcurrent = max(maximumConcurrent, active)
        defer { active -= 1 }
        do { try await Task.sleep(for: .milliseconds(100)) }
        catch { cancelled += 1; throw error }
        if fail { throw RouteCalculationError.noRoutesAvailable }
        let points = [request.source!.placemark.coordinate, request.destination!.placemark.coordinate]
        return CalculatedRoute(polyline: MKPolyline(coordinates: points, count: 2),
                               expectedTravelTime: 1, distance: PolylineMatching.totalLengthMeters(points), steps: [])
    }
}

private final class DirectionsTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date()
    func date() -> Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ seconds: TimeInterval) { lock.lock(); defer { lock.unlock() }; value.addTimeInterval(seconds) }
}

// MARK: - Recuperación de lugares sin pérdida de datos (E01)

@MainActor
final class LugaresStoreRecuperacionTests: XCTestCase {
    private var dominio: String!
    private var defaults: UserDefaults!
    private var almacen: AlmacenLugares!
    private let versionKey = "persistencia.esquema.version"

    override func setUp() {
        super.setUp()
        dominio = "RutaUTPTests.LugaresRecuperacion.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: dominio)!
        defaults.removePersistentDomain(forName: dominio)
        almacen = AlmacenLugares(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: dominio)
        almacen = nil
        defaults = nil
        dominio = nil
        super.tearDown()
    }

    private func lugar(_ nombre: String, fijo: Bool = false) -> LugarGuardado {
        LugarGuardado(nombre: nombre, direccion: "Dirección de prueba",
                      categoria: fijo ? .universidad : .otro,
                      lat: -8.1, lon: -79.03, esFijo: fijo,
                      paraderoID: fijo ? nil : "paradero-test")
    }

    func testPrimeraInstalacionConservaSemillasYSusIdentidades() throws {
        let inicial = almacen.cargar()
        XCTAssertEqual(inicial.map(\.nombre), ["UTP", "Plaza de Armas"])
        XCTAssertTrue(inicial[0].esFijo)
        XCTAssertFalse(almacen.datosLocalesInvalidos)
        XCTAssertNil(defaults.object(forKey: LugaresStore.respaldoKey))
        let reiniciado = AlmacenLugares(defaults: defaults)
        XCTAssertEqual(reiniciado.cargar(), inicial)
    }

    func testListaVaciaValidaNoSeConfundeConInstalacionNueva() {
        let original = Data("[]".utf8)
        defaults.set(original, forKey: LugaresStore.key)
        let cargados = almacen.cargar()
        XCTAssertEqual(cargados.map(\.nombre), ["UTP"])
        XCTAssertTrue(cargados[0].esFijo)
        XCTAssertFalse(almacen.datosLocalesInvalidos)
        XCTAssertEqual(defaults.data(forKey: LugaresStore.respaldoKey), original)
    }

    func testJSONTruncadoCategoriaDesconocidaYTiposInvalidosConservanOriginal() throws {
        let valido = try JSONEncoder().encode([lugar("Anterior")])
        let objeto = try XCTUnwrap(JSONSerialization.jsonObject(with: valido) as? [[String: Any]])
        var categoriaNueva = objeto
        categoriaNueva[0]["categoria"] = "CategoriaDeOtraVersion"
        var tipoIncompatible = objeto
        tipoIncompatible[0]["lat"] = "no-es-un-numero"
        let casos = [Data("[{\"id\":".utf8),
                     try JSONSerialization.data(withJSONObject: categoriaNueva),
                     try JSONSerialization.data(withJSONObject: tipoIncompatible)]
        for original in casos {
            defaults.set(original, forKey: LugaresStore.key)
            almacen.invalidarCache()
            XCTAssertTrue(almacen.cargar().isEmpty)
            XCTAssertTrue(almacen.datosLocalesInvalidos)
            XCTAssertFalse(almacen.guardar([lugar("Nuevo")]))
            XCTAssertFalse(almacen.eliminar(lugar("Anterior")))
            let reiniciado = AlmacenLugares(defaults: defaults)
            XCTAssertTrue(reiniciado.cargar().isEmpty)
            XCTAssertFalse(reiniciado.guardar([lugar("Tras reiniciar")]))
            XCTAssertEqual(defaults.data(forKey: LugaresStore.key), original)
            XCTAssertNil(defaults.object(forKey: LugaresStore.respaldoKey))
        }
    }

    func testTipoDeAlmacenamientoIncompatibleTampocoSeSobrescribe() {
        defaults.set("dato de otra versión", forKey: LugaresStore.key)
        XCTAssertTrue(almacen.cargar().isEmpty)
        XCTAssertTrue(almacen.datosLocalesInvalidos)
        XCTAssertFalse(almacen.guardar([lugar("Nuevo")]))
        XCTAssertEqual(defaults.string(forKey: LugaresStore.key), "dato de otra versión")
    }

    func testGuardarSinLeerPrimeroTambienDetectaDatosInvalidos() {
        let original = Data("ilegible".utf8)
        defaults.set(original, forKey: LugaresStore.key)
        XCTAssertFalse(almacen.guardar([lugar("Nuevo")]))
        XCTAssertEqual(defaults.data(forKey: LugaresStore.key), original)
        XCTAssertTrue(almacen.datosLocalesInvalidos)
    }

    func testFalloDeLecturaNoReemplazaRespaldoAnterior() throws {
        let respaldo = try JSONEncoder().encode([lugar("UTP", fijo: true), lugar("Anterior")])
        let original = Data("ilegible".utf8)
        defaults.set(respaldo, forKey: LugaresStore.respaldoKey)
        defaults.set(original, forKey: LugaresStore.key)
        _ = almacen.cargar()
        XCTAssertFalse(almacen.guardar([lugar("Nuevo")]))
        XCTAssertEqual(defaults.data(forKey: LugaresStore.key), original)
        XCTAssertEqual(defaults.data(forKey: LugaresStore.respaldoKey), respaldo)
    }

    func testMigracionLegadaPreservaUUIDParaderoReferenciasYOriginal() throws {
        let campus = lugar("UTP")
        let paradero = lugar("Paradero anterior")
        var objetos = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode([paradero, campus])) as? [[String: Any]])
        objetos[0].removeValue(forKey: "esFijo")
        objetos[1].removeValue(forKey: "esFijo")
        objetos[1]["campoDeOtraVersion"] = "se conserva en el respaldo"
        let original = try JSONSerialization.data(withJSONObject: objetos)
        let seleccion = try JSONEncoder().encode([paradero.id])
        defaults.set(original, forKey: LugaresStore.key)
        defaults.set(seleccion, forKey: "seguridad.tiles.v1")
        defaults.set(seleccion, forKey: "seguridad.tiles.orden.v1")

        XCTAssertEqual(Persistencia.migrarSiHaceFalta(almacen: almacen), 1)
        let migrados = almacen.cargar()
        XCTAssertEqual(migrados.map(\.id), [campus.id, paradero.id])
        XCTAssertTrue(migrados[0].esFijo)
        XCTAssertEqual(migrados[1].paraderoID, paradero.paraderoID)
        XCTAssertEqual(defaults.data(forKey: LugaresStore.respaldoKey), original)
        XCTAssertEqual(defaults.data(forKey: "seguridad.tiles.v1"), seleccion)
        XCTAssertEqual(defaults.data(forKey: "seguridad.tiles.orden.v1"), seleccion)
        let normalizados = defaults.data(forKey: LugaresStore.key)
        let reiniciado = AlmacenLugares(defaults: defaults)
        XCTAssertEqual(reiniciado.cargar(), migrados)
        XCTAssertEqual(Persistencia.migrarSiHaceFalta(almacen: reiniciado), 1)
        XCTAssertEqual(defaults.data(forKey: LugaresStore.key), normalizados)
        XCTAssertEqual(defaults.data(forKey: LugaresStore.respaldoKey), original)
    }

    func testLecturaValidaSinNormalizacionNoReescribeCamposDesconocidos() throws {
        var objetos = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode([lugar("UTP", fijo: true)])) as? [[String: Any]])
        objetos[0]["campoDeOtraVersion"] = "original intacto"
        let original = try JSONSerialization.data(withJSONObject: objetos)
        defaults.set(original, forKey: LugaresStore.key)
        XCTAssertEqual(almacen.cargar().count, 1)
        XCTAssertFalse(almacen.datosLocalesInvalidos)
        XCTAssertEqual(defaults.data(forKey: LugaresStore.key), original)
        XCTAssertNil(defaults.object(forKey: LugaresStore.respaldoKey))
    }

    func testMigracionFallidaNoSellaVersionNiModificaOtrasLlaves() throws {
        let original = Data("ilegible".utf8)
        let referencias = try JSONEncoder().encode([UUID()])
        defaults.set(original, forKey: LugaresStore.key)
        for key in ["seguridad.tiles.v1", "seguridad.tiles.orden.v1", "lineas.guardadas.v1"] {
            defaults.set(referencias, forKey: key)
        }
        XCTAssertEqual(Persistencia.migrarSiHaceFalta(almacen: almacen), 0)
        XCTAssertNil(defaults.object(forKey: versionKey))
        XCTAssertEqual(defaults.data(forKey: LugaresStore.key), original)
        for key in ["seguridad.tiles.v1", "seguridad.tiles.orden.v1", "lineas.guardadas.v1"] {
            XCTAssertEqual(defaults.data(forKey: key), referencias)
        }
    }

    func testTrasRepararDatosSePuedeReintentarLecturaYMigracion() throws {
        defaults.set(Data("ilegible".utf8), forKey: LugaresStore.key)
        XCTAssertEqual(Persistencia.migrarSiHaceFalta(almacen: almacen), 0)
        let anterior = lugar("UTP")
        defaults.set(try JSONEncoder().encode([anterior]), forKey: LugaresStore.key)
        almacen.invalidarCache()
        XCTAssertEqual(Persistencia.migrarSiHaceFalta(almacen: almacen), 1)
        XCTAssertEqual(almacen.cargar().map(\.id), [anterior.id])
        XCTAssertFalse(almacen.datosLocalesInvalidos)
        XCTAssertTrue(almacen.guardar(almacen.cargar() + [lugar("Nuevo")]))
    }

    func testEsquemaYaSelladoNoPermiteSobrescribirDatosInvalidos() {
        let original = Data("ilegible".utf8)
        defaults.set(1, forKey: versionKey)
        defaults.set(original, forKey: LugaresStore.key)
        XCTAssertEqual(Persistencia.migrarSiHaceFalta(almacen: almacen), 1)
        XCTAssertFalse(almacen.guardar([lugar("Nuevo")]))
        XCTAssertEqual(defaults.data(forKey: LugaresStore.key), original)
    }

    func testGuardadoNoPublicaCambiosSiLaLecturaEsInvalida() {
        let original = Data("ilegible".utf8)
        defaults.set(original, forKey: LugaresStore.key)
        let modelo = GuardadoViewModel(almacen: almacen)
        modelo.cargar()
        XCTAssertTrue(modelo.datosLugaresInvalidos)
        XCTAssertFalse(modelo.añadirLugar(lugar("Nuevo")))
        XCTAssertFalse(modelo.eliminarLugar(lugar("Anterior")))
        modelo.reintentarLecturaLugares()
        XCTAssertTrue(modelo.lugares.isEmpty)
        XCTAssertTrue(modelo.datosLugaresInvalidos)
        XCTAssertEqual(defaults.data(forKey: LugaresStore.key), original)
    }

    func testSeguridadConservaTilesYOrdenCuandoFallaLaLectura() throws {
        let anterior = lugar("Anterior")
        XCTAssertTrue(almacen.guardar([lugar("UTP", fijo: true), anterior]))
        let seleccion = try JSONEncoder().encode([anterior.id])
        defaults.set(seleccion, forKey: "seguridad.tiles.v1")
        defaults.set(seleccion, forKey: "seguridad.tiles.orden.v1")
        let modelo = SeguridadLugaresModel(almacen: almacen)
        modelo.cargar()
        let original = Data("ilegible".utf8)
        defaults.set(original, forKey: LugaresStore.key)
        almacen.invalidarCache()
        XCTAssertFalse(modelo.eliminar(anterior))
        modelo.reconstruirTiles(seleccion: [])
        modelo.persistirOrden()
        XCTAssertTrue(modelo.datosLugaresInvalidos)
        XCTAssertTrue(modelo.tilesActuales.isEmpty)
        XCTAssertEqual(defaults.data(forKey: LugaresStore.key), original)
        XCTAssertEqual(defaults.data(forKey: "seguridad.tiles.v1"), seleccion)
        XCTAssertEqual(defaults.data(forKey: "seguridad.tiles.orden.v1"), seleccion)
    }

    func testSeleccionUOrdenIlegiblesBloqueanMutacionesYConservanOriginales() throws {
        let anterior = lugar("Anterior")
        XCTAssertTrue(almacen.guardar([lugar("UTP", fijo: true), anterior]))
        let lista = try JSONEncoder().encode([anterior.id])
        let originalLugares = defaults.data(forKey: LugaresStore.key)
        for clave in ["seguridad.tiles.v1", "seguridad.tiles.orden.v1"] {
            defaults.set(lista, forKey: "seguridad.tiles.v1")
            defaults.set(lista, forKey: "seguridad.tiles.orden.v1")
            let modelo = SeguridadLugaresModel(almacen: almacen)
            modelo.cargar()
            // También debe proteger una pantalla que cargó antes del daño.
            defaults.set("formato incompatible", forKey: clave)
            XCTAssertFalse(modelo.reconstruirTiles(seleccion: []))
            XCTAssertFalse(modelo.persistirOrden())
            XCTAssertFalse(modelo.eliminar(anterior))
            modelo.alternarEdicion()
            XCTAssertTrue(modelo.datosTilesInvalidos)
            XCTAssertFalse(modelo.modoEdicion)
            XCTAssertEqual(defaults.string(forKey: clave), "formato incompatible")
            XCTAssertEqual(defaults.data(forKey: LugaresStore.key), originalLugares)
        }
    }

    func testIDsRepetidosEnTilesSeConservanSinGenerarAccesosDuplicados() throws {
        let anterior = lugar("Anterior")
        XCTAssertTrue(almacen.guardar([lugar("UTP", fijo: true), anterior]))
        let original = try JSONEncoder().encode([anterior.id, anterior.id])
        defaults.set(original, forKey: "seguridad.tiles.v1")
        let modelo = SeguridadLugaresModel(almacen: almacen)
        modelo.cargar()
        XCTAssertTrue(modelo.datosTilesInvalidos)
        XCTAssertTrue(modelo.tilesActuales.isEmpty)
        XCTAssertEqual(defaults.data(forKey: "seguridad.tiles.v1"), original)
    }

    func testGuardadoConservaLugaresAñadidosDesdeOtraPantalla() {
        let campus = lugar("UTP", fijo: true)
        let primero = lugar("Primero")
        let externo = lugar("Otra pantalla")
        let nuevo = lugar("Nuevo")
        XCTAssertTrue(almacen.guardar([campus, primero]))
        let modelo = GuardadoViewModel(almacen: almacen)
        modelo.cargar()
        XCTAssertTrue(almacen.guardar([campus, primero, externo]))
        XCTAssertTrue(modelo.añadirLugar(nuevo))
        XCTAssertTrue(modelo.lugares.contains { $0.id == externo.id })
        XCTAssertEqual(modelo.lugares.first?.id, campus.id)
        XCTAssertTrue(modelo.eliminarLugar(primero))
        XCTAssertEqual(Set(almacen.cargar().map(\.id)), [campus.id, externo.id, nuevo.id])
    }

    func testCambioIlegiblePosteriorALaCacheBloqueaGuardarYEliminar() throws {
        let inicial = [lugar("UTP", fijo: true), lugar("Anterior")]
        let originales: [Any] = [Data("ilegible".utf8), "formato incompatible"]
        for original in originales {
            defaults.set(try JSONEncoder().encode(inicial), forKey: LugaresStore.key)
            XCTAssertEqual(almacen.cargar(), inicial)
            defaults.set(original, forKey: LugaresStore.key)
            // No se invalida manualmente: la protección debe ser automática.
            XCTAssertFalse(almacen.guardar(inicial + [lugar("Nuevo")]))
            XCTAssertFalse(almacen.eliminar(inicial[1]))
            XCTAssertTrue(almacen.datosLocalesInvalidos)
            XCTAssertTrue(almacen.cargar().isEmpty)
            XCTAssertTrue((defaults.object(forKey: LugaresStore.key) as! NSObject).isEqual(original))
            XCTAssertNil(defaults.object(forKey: LugaresStore.respaldoKey))
        }
    }

    func testOtraInstanciaActualizaLaListaCacheadaSinInvalidacionManual() {
        let inicial = [lugar("UTP", fijo: true), lugar("Anterior")]
        XCTAssertTrue(almacen.guardar(inicial))
        let otra = AlmacenLugares(defaults: defaults)
        let nuevo = lugar("Desde otra instancia")
        XCTAssertTrue(otra.guardar(inicial + [nuevo]))
        XCTAssertEqual(almacen.cargar(), inicial + [nuevo])
        XCTAssertTrue(almacen.eliminar(inicial[1]))
        XCTAssertEqual(otra.cargar(), [inicial[0], nuevo])
    }

    func testIDsRepetidosYCoordenadasInvalidasConservanElOriginal() throws {
        let campus = lugar("UTP", fijo: true)
        let anterior = lugar("Anterior")
        var fueraDeRango = anterior
        fueraDeRango.lat = 91
        var incompleto = anterior
        incompleto.lon = nil
        for lista in [[campus, anterior, anterior], [campus, fueraDeRango], [campus, incompleto]] {
            let original = try JSONEncoder().encode(lista)
            defaults.set(original, forKey: LugaresStore.key)
            XCTAssertTrue(almacen.cargar().isEmpty)
            XCTAssertTrue(almacen.datosLocalesInvalidos)
            XCTAssertFalse(almacen.guardar([campus]))
            XCTAssertEqual(defaults.data(forKey: LugaresStore.key), original)
            XCTAssertNil(defaults.object(forKey: LugaresStore.respaldoKey))
        }
    }

    func testLugarAnteriorSinCoordenadasSigueSiendoLegible() throws {
        var anterior = lugar("Sin coordenadas")
        anterior.lat = nil
        anterior.lon = nil
        let lista = [lugar("UTP", fijo: true), anterior]
        let original = try JSONEncoder().encode(lista)
        defaults.set(original, forKey: LugaresStore.key)
        XCTAssertEqual(almacen.cargar(), lista)
        XCTAssertFalse(almacen.datosLocalesInvalidos)
        XCTAssertEqual(defaults.data(forKey: LugaresStore.key), original)
    }

    func testErrorDeCodificacionNoCambiaDiscoNiCache() {
        let inicial = [lugar("UTP", fijo: true), lugar("Anterior")]
        XCTAssertTrue(almacen.guardar(inicial))
        let original = defaults.data(forKey: LugaresStore.key)
        var invalido = lugar("Invalido")
        invalido.lat = .nan
        XCTAssertFalse(almacen.guardar(inicial + [invalido]))
        XCTAssertEqual(almacen.cargar(), inicial)
        XCTAssertEqual(defaults.data(forKey: LugaresStore.key), original)
        XCTAssertFalse(almacen.datosLocalesInvalidos)
    }
}

// MARK: - Referencias de tarjetas: persistencia aislada, sin llavero real

@MainActor
final class TarjetasStoreRecuperacionTests: XCTestCase {
    private final class LlaveroMemoria: ReferenciasTarjetasPersistiendo {
        var data: Data?
        var fallarLectura = false
        var fallarEscritura = false
        var escrituras = 0

        func leer() throws -> Data? {
            if fallarLectura { throw CocoaError(.fileReadNoPermission) }
            return data
        }

        func guardar(_ data: Data) throws {
            if fallarEscritura { throw CocoaError(.fileWriteNoPermission) }
            escrituras += 1
            self.data = data
        }
    }

    private func tarjeta(_ nombre: String) -> TarjetaGuardada {
        TarjetaGuardada(nombre: nombre, red: "Visa", ultimos4: "1234")
    }

    func testLecturaFallidaPosteriorALaCargaBloqueaTodasLasMutaciones() throws {
        let llave = LlaveroMemoria()
        let anterior = tarjeta("Anterior")
        let original = try JSONEncoder().encode([anterior])
        llave.data = original
        let store = TarjetasStore(persistencia: llave)
        llave.fallarLectura = true
        XCTAssertFalse(store.cargar())
        XCTAssertFalse(store.agregar(tarjeta("Nuevo")))
        XCTAssertFalse(store.hacerPrincipal(anterior))
        XCTAssertFalse(store.eliminar(anterior))
        XCTAssertTrue(store.lecturaFallida)
        XCTAssertEqual(llave.data, original)
        XCTAssertEqual(llave.escrituras, 0)
        llave.fallarLectura = false
        XCTAssertTrue(store.cargar())
        XCTAssertFalse(store.lecturaFallida)
        XCTAssertNil(store.error)
        XCTAssertEqual(store.tarjetas, [anterior])
    }

    func testDatosIlegiblesRepetidosOIncompletosNoSeSobrescriben() throws {
        let llave = LlaveroMemoria()
        let anterior = tarjeta("Anterior")
        var incompleta = anterior
        incompleta.ultimos4 = "12"
        let store = TarjetasStore(persistencia: llave)
        for original in [Data("ilegible".utf8),
                         try JSONEncoder().encode([anterior, anterior]),
                         try JSONEncoder().encode([incompleta])] {
            llave.data = original
            XCTAssertFalse(store.agregar(tarjeta("Nuevo")))
            XCTAssertTrue(store.lecturaFallida)
            XCTAssertEqual(llave.data, original)
            XCTAssertEqual(llave.escrituras, 0)
        }
    }

    func testAusenciaPosteriorALaCargaNoResucitaReferenciasEliminadas() throws {
        let llave = LlaveroMemoria()
        let anterior = tarjeta("Anterior")
        llave.data = try JSONEncoder().encode([anterior])
        let store = TarjetasStore(persistencia: llave)
        llave.data = nil
        XCTAssertFalse(store.hacerPrincipal(anterior))
        XCTAssertTrue(store.tarjetas.isEmpty)
        XCTAssertNil(llave.data)
        XCTAssertEqual(llave.escrituras, 0)
        let nueva = tarjeta("Nueva")
        XCTAssertTrue(store.agregar(nueva))
        XCTAssertEqual(store.tarjetas, [nueva])
        XCTAssertEqual(try JSONDecoder().decode([TarjetaGuardada].self, from: XCTUnwrap(llave.data)), [nueva])
    }

    func testDosAlmacenesConservanCambiosDeLaOtraInstancia() throws {
        let llave = LlaveroMemoria()
        let anterior = tarjeta("Anterior")
        llave.data = try JSONEncoder().encode([anterior])
        let primero = TarjetasStore(persistencia: llave)
        let segundo = TarjetasStore(persistencia: llave)
        let nueva = tarjeta("Desde otra pantalla")
        XCTAssertTrue(primero.agregar(nueva))
        XCTAssertTrue(segundo.eliminar(anterior))
        XCTAssertEqual(segundo.tarjetas, [nueva])
        XCTAssertTrue(primero.cargar())
        XCTAssertEqual(primero.tarjetas, [nueva])
    }

    func testElegirPrincipalUsaLaReferenciaVigenteEnLugarDeSuCopiaAnterior() throws {
        let llave = LlaveroMemoria()
        let anterior = tarjeta("Anterior")
        let otra = tarjeta("Otra")
        llave.data = try JSONEncoder().encode([otra, anterior])
        let store = TarjetasStore(persistencia: llave)
        var actualizada = anterior
        actualizada.nombre = "Nombre actualizado"
        llave.data = try JSONEncoder().encode([otra, actualizada])
        XCTAssertTrue(store.hacerPrincipal(anterior))
        XCTAssertEqual(store.tarjetas, [actualizada, otra])
        XCTAssertEqual(try JSONDecoder().decode([TarjetaGuardada].self, from: XCTUnwrap(llave.data)), [actualizada, otra])
    }

    func testFalloDeEscrituraNoPublicaNiPersisteUnCambioExitoso() throws {
        let llave = LlaveroMemoria()
        let anterior = tarjeta("Anterior")
        let original = try JSONEncoder().encode([anterior])
        llave.data = original
        let store = TarjetasStore(persistencia: llave)
        llave.fallarEscritura = true
        XCTAssertFalse(store.agregar(tarjeta("Nuevo")))
        XCTAssertEqual(store.tarjetas, [anterior])
        XCTAssertEqual(llave.data, original)
        XCTAssertEqual(llave.escrituras, 0)
        XCTAssertNotNil(store.error)
    }
}

// MARK: - Destinos y fuentes de flota del mapa (E02)

@MainActor
final class MapaFuenteFlotaTests: XCTestCase {
    private let campus = GTFSRepository.coordenadaUTP

    private func ruta(_ id: String = "ruta-test") -> RutaGTFS {
        let shape = (0...20).map {
            CLLocationCoordinate2D(latitude: campus.latitude,
                                   longitude: campus.longitude - 0.02 + Double($0) * 0.002)
        }
        return RutaGTFS(id: id, linea: "T", variante: "A", recorrido: "Inicio → Fin",
                        empresa: "Prueba", colorHex: "00CC00", color: .green,
                        shape: shape, paraderos: [], duracionMin: 10, headwayMin: 5,
                        precio: 2, distanciaKm: 4.4, distanciaUTPMetros: 0)
    }

    private func posicion(_ id: String = "bus-test") -> VehiclePosition {
        VehiclePosition(id: id, linea: "T", routeId: "ruta-test",
                        lat: campus.latitude, lon: campus.longitude - 0.015,
                        heading: 90, speed: 10)
    }

    private func modelo(_ repositorio: MapaGTFSPrueba,
                        proveedor: @escaping () -> VehicleTrackingProviding? = { nil }) -> MapaViewModel {
        MapaViewModel(locationService: MapaGPSPrueba(), repositorioGTFS: repositorio,
                      crearProveedorReal: proveedor)
    }

    private func esperar(_ descripcion: String,
                         condicion: () async -> Bool) async {
        for _ in 0..<400 {
            if await condicion() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("No se completó: \(descripcion)")
    }

    private func cederATareasCanceladas() async {
        for _ in 0..<20 { await Task.yield() }
    }

    func testChipLugarYLimpiarMantienenPosicionesRealesYRecalculanETA() async throws {
        let ruta = ruta()
        let posicion = posicion()
        let repositorio = MapaGTFSPrueba(feed: [ruta])
        let proveedor = MapaVehiculosPrueba(posiciones: [posicion])
        let vm = modelo(repositorio, proveedor: { proveedor })
        defer { vm.detener() }
        vm.iniciarSimulacionBuses()
        await esperar("primer snapshot") { vm.busesAnimados.count == 1 }

        let destino = CLLocationCoordinate2D(latitude: campus.latitude, longitude: campus.longitude + 0.01)
        vm.seleccionar(destino: DestinoChip(id: 900, label: "Destino de prueba", icon: "mappin",
                                          lat: destino.latitude, lon: destino.longitude))
        await cederATareasCanceladas()
        XCTAssertEqual(vm.busesAnimados.first?.minutosLlegada,
                       VehicleETAEstimator.minutes(position: posicion, route: ruta, target: destino))
        XCTAssertEqual(vm.busesAnimados.first?.id, "real-bus-test")
        XCTAssertTrue(vm.hayPosicionesRealesRecientes)

        let cercano = CLLocationCoordinate2D(latitude: campus.latitude, longitude: campus.longitude - 0.014)
        vm.seleccionarLugar(titulo: "Lugar", coordenada: cercano)
        await cederATareasCanceladas()
        XCTAssertEqual(vm.busesAnimados.first?.minutosLlegada, 1)
        vm.limpiar()
        await cederATareasCanceladas()
        XCTAssertEqual(vm.busesAnimados.first?.minutosLlegada,
                       VehicleETAEstimator.minutes(position: posicion, route: ruta, target: campus))
        let bus = try XCTUnwrap(vm.busesAnimados.first)
        XCTAssertEqual(bus.fuente, .real)
        XCTAssertEqual(bus.lat, posicion.lat)
        XCTAssertEqual(bus.lon, posicion.lon)
        XCTAssertTrue(bus.rutaCoordenadas.isEmpty)
        XCTAssertEqual(proveedor.inicios, 1)
        XCTAssertEqual(proveedor.paradas, 0)
        let consultas = await repositorio.consultasCercanas
        XCTAssertFalse(consultas.isEmpty, "El catálogo filtra el panel sin generar vehículos")
        XCTAssertTrue(vm.busesAnimados.allSatisfy { $0.fuente == .real })

        proveedor.emitir([self.posicion("siguiente")])
        await esperar("suscripción sigue activa") { vm.busesAnimados.first?.id == "real-siguiente" }
    }

    func testSnapshotRealVacioSigueEsperandoDatosAlCambiarDestino() async {
        let repositorio = MapaGTFSPrueba(feed: [ruta()])
        let proveedor = MapaVehiculosPrueba(posiciones: [])
        let vm = modelo(repositorio, proveedor: { proveedor })
        defer { vm.detener() }
        vm.iniciarSimulacionBuses()
        await esperar("snapshot vacío y catálogo") { !vm.cargandoLineas && !vm.esperandoPosicionesReales }
        vm.seleccionar(destino: DestinoChip(id: 901, label: "Chip", icon: "mappin",
                                          lat: campus.latitude, lon: campus.longitude + 0.01))
        vm.seleccionarLugar(titulo: "Lugar", coordenada: campus)
        vm.limpiar()
        await esperar("catálogo del campus") { !vm.cargandoLineas }
        XCTAssertEqual(vm.fuenteFlota, .real)
        XCTAssertTrue(vm.busesAnimados.isEmpty)
        XCTAssertFalse(vm.hayPosicionesRealesRecientes)
        XCTAssertEqual(proveedor.inicios, 1)
        XCTAssertEqual(proveedor.paradas, 0)
        let consultas = await repositorio.consultasCercanas
        XCTAssertFalse(consultas.isEmpty)
        XCTAssertEqual(vm.cantidadLineasDelPanel, 0)
    }

    func testDestinoElegidoDuranteCargaRealSeUsaEnElPrimerSnapshot() async {
        let ruta = ruta()
        let posicion = posicion()
        let repositorio = MapaGTFSPrueba(feed: [ruta], bloquearCatalogo: true)
        let proveedor = MapaVehiculosPrueba(posiciones: [posicion])
        var conectado = false
        let vm = modelo(repositorio, proveedor: { conectado ? proveedor : nil })
        defer { vm.detener() }
        vm.iniciarSimulacionBuses()
        await esperar("demo antes de conectar") { vm.busesAnimados.first?.fuente == .simulated }
        conectado = true
        vm.iniciarSimulacionBuses()
        XCTAssertTrue(vm.busesAnimados.isEmpty, "La demo se retira antes del primer snapshot real")
        await esperar("catálogo pendiente") { await repositorio.numeroCatalogos == 1 }
        let destino = CLLocationCoordinate2D(latitude: campus.latitude, longitude: campus.longitude + 0.01)
        vm.seleccionarLugar(titulo: "Destino", coordenada: destino)
        XCTAssertTrue(vm.busesAnimados.isEmpty)
        XCTAssertFalse(vm.hayPosicionesRealesRecientes)
        XCTAssertTrue(vm.esperandoPosicionesReales)
        await repositorio.resolverCatalogo(0)
        await esperar("snapshot con destino actual") { !vm.busesAnimados.isEmpty }
        XCTAssertEqual(vm.busesAnimados.first?.minutosLlegada,
                       VehicleETAEstimator.minutes(position: posicion, route: ruta, target: destino))
    }

    func testConsultaDemoTardiaNoPisaSnapshotReal() async {
        let repositorio = MapaGTFSPrueba(feed: [ruta()], bloquearCercanas: true)
        let proveedor = MapaVehiculosPrueba(posiciones: [posicion()])
        let vm = modelo(repositorio, proveedor: { proveedor })
        defer { vm.detener() }
        // Una selección puede consultar GTFS antes de iniciar el canal real.
        vm.recargarLineas(cercaDe: campus)
        await esperar("consulta demo pendiente") { await repositorio.consultasCercanas.count == 1 }
        vm.iniciarSimulacionBuses()
        await esperar("canal real") { vm.busesAnimados.first?.id == "real-bus-test" }
        await esperar("filtro real pendiente") { await repositorio.consultasCercanas.count == 2 }
        await repositorio.resolverCercanas(0, feed: [ruta("demo-tardia")])
        await cederATareasCanceladas()
        XCTAssertEqual(vm.busesAnimados.map(\.id), ["real-bus-test"])
        XCTAssertTrue(vm.busesAnimados.allSatisfy { $0.fuente == .real })
        XCTAssertTrue(vm.hayPosicionesRealesRecientes)
        XCTAssertTrue(vm.cargandoLineas, "La consulta demo no termina la carga del filtro real")
        await repositorio.resolverCercanas(1, feed: [ruta()])
        await esperar("filtro real resuelto") { !vm.cargandoLineas }
        XCTAssertEqual(vm.busesDelPanel.map(\.id), ["real-bus-test"])
    }

    func testVolverAlMismoDestinoNoAceptaUnaConsultaAnterior() async {
        let repositorio = MapaGTFSPrueba(feed: [], bloquearCercanas: true)
        let vm = modelo(repositorio)
        defer { vm.detener() }
        let otro = CLLocationCoordinate2D(latitude: campus.latitude, longitude: campus.longitude + 0.01)
        vm.recargarLineas(cercaDe: campus)
        await esperar("consulta A") { await repositorio.consultasCercanas.count == 1 }
        vm.recargarLineas(cercaDe: otro)
        await esperar("consulta B") { await repositorio.consultasCercanas.count == 2 }
        vm.recargarLineas(cercaDe: campus)
        await esperar("consulta A nueva") { await repositorio.consultasCercanas.count == 3 }
        await repositorio.resolverCercanas(2, feed: [ruta("vigente")])
        await esperar("resultado vigente") { !vm.cargandoLineas }
        await repositorio.resolverCercanas(0, feed: [ruta("anterior-A")])
        await repositorio.resolverCercanas(1, feed: [ruta("anterior-B")])
        await cederATareasCanceladas()
        XCTAssertEqual(vm.busesAnimados.map(\.id), ["simulated-vigente"])
    }

    func testDetenerDescartaConsultaPendienteYPermiteRecargarElMismoPunto() async {
        let repositorio = MapaGTFSPrueba(feed: [], bloquearCercanas: true)
        let vm = modelo(repositorio)
        defer { vm.detener() }
        vm.recargarLineas(cercaDe: campus)
        await esperar("consulta pendiente") { await repositorio.consultasCercanas.count == 1 }
        vm.detener()
        await repositorio.resolverCercanas(0, feed: [ruta("cancelada")])
        await cederATareasCanceladas()
        XCTAssertTrue(vm.busesAnimados.isEmpty)
        XCTAssertFalse(vm.cargandoLineas)
        vm.recargarLineas(cercaDe: campus)
        await esperar("consulta al regresar") { await repositorio.consultasCercanas.count == 2 }
        await repositorio.resolverCercanas(1, feed: [ruta("regreso")])
        await esperar("flota al regresar") { !vm.cargandoLineas }
        XCTAssertEqual(vm.busesAnimados.map(\.id), ["simulated-regreso"])
    }

    func testCatalogoDeSesionRealCanceladaNoReiniciaElProveedorAnterior() async {
        let repositorio = MapaGTFSPrueba(feed: [ruta()], bloquearCatalogo: true)
        let anterior = MapaVehiculosPrueba(posiciones: [posicion("anterior")])
        let actual = MapaVehiculosPrueba(posiciones: [posicion("actual")])
        var proveedores = [anterior, actual]
        let vm = modelo(repositorio, proveedor: { proveedores.removeFirst() })
        defer { vm.detener() }
        vm.iniciarSimulacionBuses()
        await esperar("catálogo anterior") { await repositorio.numeroCatalogos == 1 }
        vm.detener()
        vm.iniciarSimulacionBuses()
        await esperar("catálogo actual") { await repositorio.numeroCatalogos == 2 }
        await repositorio.resolverCatalogo(1)
        await esperar("sesión actual") { vm.busesAnimados.first?.id == "real-actual" }
        await repositorio.resolverCatalogo(0)
        await cederATareasCanceladas()
        XCTAssertEqual(anterior.inicios, 0)
        XCTAssertEqual(anterior.paradas, 1)
        XCTAssertEqual(actual.inicios, 1)
        XCTAssertEqual(vm.busesAnimados.map(\.id), ["real-actual"])
    }

    func testVolverDeRealADemoNoConservaVehiculosRealesNiSuIndicador() async {
        let repositorio = MapaGTFSPrueba(feed: [ruta()])
        let proveedor = MapaVehiculosPrueba(posiciones: [posicion()])
        var disponible = true
        let vm = modelo(repositorio, proveedor: { disponible ? proveedor : nil })
        defer { vm.detener() }
        vm.iniciarSimulacionBuses()
        await esperar("snapshot real") { vm.hayPosicionesRealesRecientes }
        vm.detener()
        disponible = false
        vm.iniciarSimulacionBuses()
        await esperar("flota demo") { !vm.busesAnimados.isEmpty && !vm.cargandoLineas }
        proveedor.emitir([posicion("tardia")])
        await cederATareasCanceladas()
        XCTAssertEqual(vm.fuenteFlota, .simulated)
        XCTAssertEqual(vm.busesAnimados.map(\.id), ["simulated-ruta-test"])
        XCTAssertTrue(vm.busesAnimados.allSatisfy { $0.fuente == .simulated })
        XCTAssertFalse(vm.hayPosicionesRealesRecientes)
        XCTAssertEqual(proveedor.paradas, 1)
    }

    func testDemoSinBrokerSigueAnimandoLaFlota() async throws {
        let repositorio = MapaGTFSPrueba(feed: [ruta()])
        let vm = modelo(repositorio)
        defer { vm.detener() }
        vm.iniciarSimulacionBuses()
        await esperar("flota simulada") { !vm.cargandoLineas }
        let inicial = try XCTUnwrap(vm.busesAnimados.first)
        await esperar("movimiento simulado") { vm.busesAnimados.first != inicial }
        XCTAssertEqual(vm.busesAnimados.first?.id, inicial.id)
        XCTAssertEqual(vm.busesAnimados.first?.fuente, .simulated)
        XCTAssertFalse(vm.hayPosicionesRealesRecientes)
    }

    func testDemoConservaAmpliacionDeRadioYCargaUnicaPorAncla() async {
        let repositorio = MapaGTFSPrueba(feed: [], bloquearCercanas: true)
        let vm = modelo(repositorio)
        defer { vm.detener() }
        vm.recargarLineas(cercaDe: nil)
        await esperar("radio inicial") { await repositorio.consultasCercanas.count == 1 }
        await repositorio.resolverCercanas(0, feed: [])
        await esperar("radio ampliado") { await repositorio.consultasCercanas.count == 2 }
        await repositorio.resolverCercanas(1, feed: [ruta()])
        await esperar("resultado ampliado") { !vm.cargandoLineas }
        vm.recargarLineas(cercaDe: nil)
        let consultas = await repositorio.consultasCercanas
        XCTAssertEqual(consultas.map(\.radio), [400, 800])
        XCTAssertEqual(vm.busesAnimados.map(\.id), ["simulated-ruta-test"])
    }

    func testCambioDeAnclaActualizaPopupRealSinMoverElVehiculo() async throws {
        let repositorio = MapaGTFSPrueba(feed: [ruta()])
        let proveedor = MapaVehiculosPrueba(posiciones: [posicion()])
        let vm = modelo(repositorio, proveedor: { proveedor })
        defer { vm.detener() }
        vm.iniciarSimulacionBuses()
        await esperar("snapshot") { !vm.busesAnimados.isEmpty }
        let anterior = try XCTUnwrap(vm.busesAnimados.first)
        vm.busSeleccionado = anterior
        vm.recargarLineas(cercaDe: CLLocationCoordinate2D(latitude: campus.latitude,
                                                         longitude: campus.longitude - 0.014))
        XCTAssertEqual(vm.busSeleccionado?.id, anterior.id)
        XCTAssertEqual(vm.busSeleccionado?.minutosLlegada, 1)
        XCTAssertNotEqual(vm.busSeleccionado?.minutosLlegada, anterior.minutosLlegada)
        XCTAssertEqual(vm.busSeleccionado?.coordinate.latitude, anterior.lat)
        XCTAssertEqual(vm.busSeleccionado?.coordinate.longitude, anterior.lon)
    }
}

/// Las continuaciones ignoran deliberadamente la cancelación para demostrar
/// que el consumidor rechaza resultados tardíos por su propia cuenta.
private actor MapaGTFSPrueba: RutasGTFSProviding {
    struct Consulta { let punto: CLLocationCoordinate2D; let radio: Double }
    private let feed: [RutaGTFS]
    private let feedCercano: [RutaGTFS]
    private let bloquearCercanas: Bool
    private let bloquearCatalogo: Bool
    private var pendientesCercanas: [Int: CheckedContinuation<[RutaGTFS], Never>] = [:]
    private var pendientesCatalogo: [Int: CheckedContinuation<[RutaGTFS], Never>] = [:]
    private(set) var consultasCercanas: [Consulta] = []
    private(set) var numeroCatalogos = 0

    init(feed: [RutaGTFS], rutasCercanas: [RutaGTFS]? = nil,
         bloquearCercanas: Bool = false, bloquearCatalogo: Bool = false) {
        self.feed = feed
        self.feedCercano = rutasCercanas ?? feed
        self.bloquearCercanas = bloquearCercanas
        self.bloquearCatalogo = bloquearCatalogo
    }

    func rutas() async -> [RutaGTFS] {
        let indice = numeroCatalogos
        numeroCatalogos += 1
        guard bloquearCatalogo else { return feed }
        return await withCheckedContinuation { pendientesCatalogo[indice] = $0 }
    }

    func rutasQuePasanPor(_ punto: CLLocationCoordinate2D, radioMetros: Double) async -> [RutaGTFS] {
        let indice = consultasCercanas.count
        consultasCercanas.append(Consulta(punto: punto, radio: radioMetros))
        guard bloquearCercanas else { return feedCercano }
        return await withCheckedContinuation { pendientesCercanas[indice] = $0 }
    }

    func resolverCercanas(_ indice: Int, feed: [RutaGTFS]) {
        pendientesCercanas.removeValue(forKey: indice)?.resume(returning: feed)
    }

    func resolverCatalogo(_ indice: Int) {
        pendientesCatalogo.removeValue(forKey: indice)?.resume(returning: feed)
    }
}

private final class MapaVehiculosPrueba: VehicleTrackingProviding {
    let source: VehicleTrackingSource = .real
    private(set) var currentPositions: [VehiclePosition]
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
    func emitir(_ posiciones: [VehiclePosition]) {
        currentPositions = posiciones
        continuacion.yield(posiciones)
    }
}

private final class MapaGPSPrueba: LocationServiceProtocol {
    let authorizationStatus: CLAuthorizationStatus = .denied
    var authorizationPublisher: AnyPublisher<CLAuthorizationStatus, Never> {
        Just(authorizationStatus).eraseToAnyPublisher()
    }
    func currentLocation() -> AsyncStream<CLLocation> { AsyncStream { $0.finish() } }
    func requestPermission() async -> CLAuthorizationStatus { authorizationStatus }
    func startUpdating() { }
    func stopUpdating() { }
}

// MARK: - Líneas y vehículos del panel por destino (E03)

@MainActor
final class MapaPanelLineasTests: XCTestCase {
    private let campus = GTFSRepository.coordenadaUTP

    private func ruta(_ id: String = "cercana", variante: String = "A", conShape: Bool = true) -> RutaGTFS {
        let lat = campus.latitude + (id == "lejana" ? 0.05 : 0)
        let shape = conShape ? (0...20).map {
            CLLocationCoordinate2D(latitude: lat, longitude: campus.longitude - 0.02 + Double($0) * 0.002)
        } : []
        return RutaGTFS(id: id, linea: "T", variante: variante, recorrido: "Inicio → Fin",
                        empresa: "Prueba", colorHex: "00CC00", color: .green,
                        shape: shape, paraderos: [], duracionMin: 10, headwayMin: 5,
                        precio: 2, distanciaKm: 4.4, distanciaUTPMetros: id == "lejana" ? 5500 : 0)
    }

    private func posicion(_ id: String, ruta: String = "cercana", velocidad: Double = 10,
                          rumbo: Double = 90) -> VehiclePosition {
        VehiclePosition(id: id, linea: "T", routeId: ruta,
                        lat: campus.latitude + (ruta == "lejana" ? 0.05 : 0),
                        lon: campus.longitude - 0.015, heading: rumbo, speed: velocidad)
    }

    private func modelo(_ repositorio: MapaGTFSPrueba, proveedor: MapaVehiculosPrueba? = nil) -> MapaViewModel {
        MapaViewModel(locationService: MapaGPSPrueba(), repositorioGTFS: repositorio,
                      crearProveedorReal: { proveedor })
    }

    private func esperar(_ descripcion: String, condicion: () async -> Bool) async {
        for _ in 0..<400 {
            if await condicion() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("No se completó: \(descripcion)")
    }

    private func cederATareasCanceladas() async {
        for _ in 0..<20 { await Task.yield() }
    }

    func testDosVehiculosDeUnaRutaCuentanUnaLineaYElSnapshotActualizaElPanel() async {
        let cercanas = [ruta(), ruta("sin-vehiculos")]
        let repositorio = MapaGTFSPrueba(feed: cercanas)
        let proveedor = MapaVehiculosPrueba(posiciones: [posicion("uno"), posicion("dos")])
        let vm = modelo(repositorio, proveedor: proveedor)
        defer { vm.detener() }
        vm.iniciarSimulacionBuses()
        await esperar("panel") { !vm.cargandoLineas && !vm.esperandoPosicionesReales }
        XCTAssertEqual(vm.busesDelPanel.count, 2)
        XCTAssertEqual(vm.cantidadLineasDelPanel, 1)
        XCTAssertEqual(vm.rutasCercanas.count, 2, "Una ruta sin vehículos no cuenta como observada")
        XCTAssertEqual(vm.textoEstadoLineas, L.t("1 línea cerca del campus", "1 line near campus"))
        proveedor.emitir([])
        await esperar("caducidad de vehículos") { vm.busesAnimados.isEmpty }
        XCTAssertEqual(vm.cantidadLineasDelPanel, 0)
        XCTAssertEqual(vm.rutasCercanas.count, 2)
        XCTAssertEqual(vm.textoEstadoLineas,
                       L.t("Aún no hay buses confirmados para estas líneas", "There are no confirmed buses for these lines yet"))
        XCTAssertFalse(vm.hayPosicionesRealesRecientes)
    }

    func testRamalesConIgualNombreDeLineaSeDistinguenPorRouteID() async {
        let repositorio = MapaGTFSPrueba(feed: [ruta("ida", variante: "A"), ruta("vuelta", variante: "B")])
        let proveedor = MapaVehiculosPrueba(posiciones: [posicion("uno", ruta: "ida"), posicion("dos", ruta: "vuelta")])
        let vm = modelo(repositorio, proveedor: proveedor)
        defer { vm.detener() }
        vm.seleccionarLugar(titulo: "Destino", coordenada: campus)
        vm.iniciarSimulacionBuses()
        await esperar("dos ramales") { !vm.cargandoLineas && !vm.esperandoPosicionesReales }
        XCTAssertEqual(vm.cantidadLineasDelPanel, 2)
        XCTAssertEqual(Set(vm.busesDelPanel.map(\.variante)), ["A", "B"])
        XCTAssertEqual(vm.textoEstadoLineas,
                       String(format: L.t("%d líneas pasan por %@", "%d lines pass by %@"), 2, "Destino"))
    }

    func testRutasLejanasYDesconocidasSiguenEnMapaPeroNoEnElPanel() async throws {
        let repositorio = MapaGTFSPrueba(feed: [ruta(), ruta("lejana")], rutasCercanas: [ruta()])
        let proveedor = MapaVehiculosPrueba(posiciones: [posicion("cerca"), posicion("lejos", ruta: "lejana"),
                                                        posicion("sin-catalogo", ruta: "desconocida"), posicion("sin-id", ruta: "")])
        let vm = modelo(repositorio, proveedor: proveedor)
        defer { vm.detener() }
        vm.iniciarSimulacionBuses()
        await esperar("flota y filtro") { !vm.cargandoLineas && !vm.esperandoPosicionesReales }
        XCTAssertEqual(vm.busesAnimados.count, 4)
        XCTAssertEqual(vm.busesDelPanel.map(\.id), ["real-cerca"])
        XCTAssertEqual(vm.cantidadLineasDelPanel, 1)
        XCTAssertTrue(vm.hayPosicionesRealesRecientes)
        vm.busSeleccionado = try XCTUnwrap(vm.busesAnimados.first { $0.id == "real-lejos" })
        vm.recargarLineas(cercaDe: CLLocationCoordinate2D(latitude: campus.latitude, longitude: campus.longitude + 0.01))
        await esperar("nuevo filtro") { !vm.cargandoLineas }
        XCTAssertEqual(vm.busSeleccionado?.id, "real-lejos", "Salir del panel no elimina el popup global")
        XCTAssertEqual(vm.busesAnimados.count, 4)
        XCTAssertEqual(vm.busesDelPanel.map(\.id), ["real-cerca"])
        XCTAssertEqual(proveedor.inicios, 1)
        XCTAssertEqual(proveedor.paradas, 0)
    }

    func testETAausenteNoExcluyeUnBusDeUnaRutaCercana() async {
        let repositorio = MapaGTFSPrueba(feed: [ruta()])
        let proveedor = MapaVehiculosPrueba(posiciones: [posicion("detenido", velocidad: 0),
                                                        posicion("alejandose", rumbo: 270), posicion("sin-rumbo", rumbo: -1)])
        let vm = modelo(repositorio, proveedor: proveedor)
        defer { vm.detener() }
        vm.iniciarSimulacionBuses()
        await esperar("buses sin ETA") { !vm.cargandoLineas && !vm.esperandoPosicionesReales }
        XCTAssertEqual(vm.busesDelPanel.count, 3)
        XCTAssertTrue(vm.busesDelPanel.allSatisfy { $0.minutosLlegada == nil && $0.fuente == .real })
        XCTAssertEqual(vm.cantidadLineasDelPanel, 1)
    }

    func testRutasSinVehiculosConfirmadosNoSePresentanComoAusenciaDeLineas() async {
        let repositorio = MapaGTFSPrueba(feed: [ruta(), ruta("lejana")], rutasCercanas: [ruta()])
        let proveedor = MapaVehiculosPrueba(posiciones: [posicion("lejos", ruta: "lejana")])
        let vm = modelo(repositorio, proveedor: proveedor)
        defer { vm.detener() }
        vm.iniciarSimulacionBuses()
        await esperar("solo posiciones globales") { !vm.cargandoLineas && !vm.esperandoPosicionesReales }
        XCTAssertTrue(vm.busesDelPanel.isEmpty)
        XCTAssertFalse(vm.rutasCercanas.isEmpty)
        XCTAssertEqual(vm.cantidadLineasDelPanel, 0)
        XCTAssertEqual(vm.mensajePanelSinBuses,
                       L.t("Aún no hay buses confirmados para estas líneas", "There are no confirmed buses for these lines yet"))
        XCTAssertTrue(vm.hayPosicionesRealesRecientes)
    }

    func testCatalogoSinRutasCercanasNoAtribuyeLaFlotaGlobalAlDestino() async {
        let repositorio = MapaGTFSPrueba(feed: [ruta("lejana")], rutasCercanas: [])
        let proveedor = MapaVehiculosPrueba(posiciones: [posicion("lejos", ruta: "lejana")])
        let vm = modelo(repositorio, proveedor: proveedor)
        defer { vm.detener() }
        vm.iniciarSimulacionBuses()
        await esperar("consulta vacía y flota real") { !vm.cargandoLineas && !vm.esperandoPosicionesReales }
        XCTAssertEqual(vm.busesAnimados.count, 1)
        XCTAssertTrue(vm.busesDelPanel.isEmpty)
        XCTAssertEqual(vm.textoEstadoLineas,
                       L.t("No encontramos líneas cerca de este punto", "No lines were found near this point"))
        let consultas = await repositorio.consultasCercanas
        XCTAssertEqual(consultas.map(\.radio), [400, 800])
    }

    func testSnapshotNoTerminaPrematuramenteLaConsultaCercana() async {
        let repositorio = MapaGTFSPrueba(feed: [ruta()], bloquearCercanas: true)
        let proveedor = MapaVehiculosPrueba(posiciones: [posicion("uno")])
        let vm = modelo(repositorio, proveedor: proveedor)
        defer { vm.detener() }
        vm.iniciarSimulacionBuses()
        await esperar("snapshot mientras consulta") { !vm.esperandoPosicionesReales && vm.busesAnimados.count == 1 }
        await esperar("consulta pendiente") { await repositorio.consultasCercanas.count == 1 }
        XCTAssertTrue(vm.cargandoLineas)
        XCTAssertTrue(vm.busesDelPanel.isEmpty)
        XCTAssertEqual(vm.textoEstadoLineas, L.t("Buscando líneas…", "Finding lines…"))
        await repositorio.resolverCercanas(0, feed: [ruta()])
        await esperar("consulta resuelta") { !vm.cargandoLineas }
        XCTAssertEqual(vm.busesDelPanel.map(\.id), ["real-uno"])
    }

    func testCambiarAnclaRetiraFiltroAnteriorYConservaSnapshotNuevoYPopup() async throws {
        let repositorio = MapaGTFSPrueba(feed: [ruta(), ruta("lejana")], bloquearCercanas: true)
        let proveedor = MapaVehiculosPrueba(posiciones: [posicion("cerca"), posicion("lejos", ruta: "lejana")])
        let vm = modelo(repositorio, proveedor: proveedor)
        defer { vm.detener() }
        vm.iniciarSimulacionBuses()
        await esperar("consulta inicial") { await repositorio.consultasCercanas.count == 1 }
        await repositorio.resolverCercanas(0, feed: [ruta()])
        await esperar("panel inicial") { !vm.cargandoLineas && !vm.esperandoPosicionesReales }
        vm.busSeleccionado = try XCTUnwrap(vm.busesAnimados.first { $0.id == "real-cerca" })
        vm.recargarLineas(cercaDe: CLLocationCoordinate2D(latitude: campus.latitude + 0.05, longitude: campus.longitude))
        await esperar("consulta nueva") { await repositorio.consultasCercanas.count == 2 }
        XCTAssertTrue(vm.rutasCercanas.isEmpty)
        XCTAssertTrue(vm.busesDelPanel.isEmpty)
        XCTAssertEqual(vm.busesAnimados.count, 2)
        var actualizado = posicion("cerca")
        actualizado.lon += 0.001
        proveedor.emitir([actualizado, posicion("lejos", ruta: "lejana")])
        await esperar("snapshot actualizado") { vm.busSeleccionado?.lon == actualizado.lon }
        XCTAssertTrue(vm.cargandoLineas)
        await repositorio.resolverCercanas(1, feed: [ruta("lejana")])
        await esperar("filtro nuevo") { !vm.cargandoLineas }
        XCTAssertEqual(vm.busesDelPanel.map(\.id), ["real-lejos"])
        XCTAssertEqual(vm.busSeleccionado?.id, "real-cerca")
        XCTAssertEqual(vm.busSeleccionado?.lon, actualizado.lon)
        XCTAssertEqual(vm.busesAnimados.count, 2)
        XCTAssertEqual(proveedor.inicios, 1)
        XCTAssertEqual(proveedor.paradas, 0)
    }

    func testFiltroRealTardioNoPisaElAnclaVigenteNiLaFlota() async {
        let repositorio = MapaGTFSPrueba(feed: [ruta(), ruta("lejana")], bloquearCercanas: true)
        let proveedor = MapaVehiculosPrueba(posiciones: [posicion("cerca"), posicion("lejos", ruta: "lejana")])
        let vm = modelo(repositorio, proveedor: proveedor)
        defer { vm.detener() }
        vm.iniciarSimulacionBuses()
        await esperar("consulta A") { await repositorio.consultasCercanas.count == 1 }
        vm.recargarLineas(cercaDe: CLLocationCoordinate2D(latitude: campus.latitude + 0.05, longitude: campus.longitude))
        await esperar("consulta B") { await repositorio.consultasCercanas.count == 2 }
        vm.recargarLineas(cercaDe: campus)
        await esperar("consulta A vigente") { await repositorio.consultasCercanas.count == 3 }
        await repositorio.resolverCercanas(2, feed: [ruta()])
        await esperar("panel vigente") { !vm.cargandoLineas && !vm.esperandoPosicionesReales }
        let flota = vm.busesAnimados
        await repositorio.resolverCercanas(0, feed: [ruta("lejana")])
        await repositorio.resolverCercanas(1, feed: [ruta("lejana")])
        await cederATareasCanceladas()
        XCTAssertEqual(vm.busesAnimados, flota)
        XCTAssertEqual(vm.busesDelPanel.map(\.id), ["real-cerca"])
        XCTAssertEqual(vm.rutasCercanas.map(\.id), ["cercana"])
    }

    func testFiltroDeSesionCanceladaNoAfectaElPanelAlRegresar() async {
        let repositorio = MapaGTFSPrueba(feed: [ruta(), ruta("lejana")], bloquearCercanas: true)
        let anterior = MapaVehiculosPrueba(posiciones: [posicion("anterior", ruta: "lejana")])
        let actual = MapaVehiculosPrueba(posiciones: [posicion("actual")])
        var proveedores = [anterior, actual]
        let vm = MapaViewModel(locationService: MapaGPSPrueba(), repositorioGTFS: repositorio,
                               crearProveedorReal: { proveedores.removeFirst() })
        defer { vm.detener() }
        vm.iniciarSimulacionBuses()
        await esperar("consulta anterior") { await repositorio.consultasCercanas.count == 1 }
        vm.detener()
        vm.iniciarSimulacionBuses()
        await esperar("consulta actual") { await repositorio.consultasCercanas.count == 2 }
        await esperar("flota actual") { vm.busesAnimados.first?.id == "real-actual" }
        await repositorio.resolverCercanas(0, feed: [ruta("lejana")])
        await cederATareasCanceladas()
        XCTAssertTrue(vm.cargandoLineas)
        XCTAssertTrue(vm.rutasCercanas.isEmpty)
        await repositorio.resolverCercanas(1, feed: [ruta()])
        await esperar("panel actual") { !vm.cargandoLineas }
        XCTAssertEqual(vm.busesDelPanel.map(\.id), ["real-actual"])
    }

    func testDemoNoDuplicaRutasNiIncluyeIdentidadesOGeometriasAusentes() async {
        let repositorio = MapaGTFSPrueba(feed: [ruta(), ruta(), ruta(""), ruta("sin-shape", conShape: false)])
        let vm = modelo(repositorio)
        defer { vm.detener() }
        vm.iniciarSimulacionBuses()
        await esperar("demo") { !vm.cargandoLineas }
        XCTAssertEqual(vm.rutasCercanas.map(\.id), ["cercana"])
        XCTAssertEqual(vm.cantidadLineasDelPanel, 1)
        XCTAssertEqual(vm.busesDelPanel.map(\.id), ["simulated-cercana"])
        XCTAssertEqual(vm.textoEstadoLineas, L.t("1 línea cerca del campus", "1 line near campus"))
    }

    func testDemoSinRutasCercanasTerminaLaBusquedaYExplicaElResultado() async {
        let repositorio = MapaGTFSPrueba(feed: [])
        let vm = modelo(repositorio)
        defer { vm.detener() }
        vm.iniciarSimulacionBuses()
        await esperar("búsqueda terminada") { !vm.cargandoLineas }
        XCTAssertTrue(vm.busesDelPanel.isEmpty)
        XCTAssertEqual(vm.textoEstadoLineas,
                       L.t("No encontramos líneas cerca de este punto", "No lines were found near this point"))
        let consultas = await repositorio.consultasCercanas
        XCTAssertEqual(consultas.map(\.radio), [400, 800])
    }
}


/// Suites aisladas y escritor simulado: no usan preferencias ni documentos reales.
@MainActor
final class RecuperacionPreferenciasTests: XCTestCase {
    private let archivoSimulado = URL(fileURLWithPath: "/tmp/respaldo-simulado.plist")

    private func conPreferencias(_ comprobar: (UserDefaults) throws -> Void) throws {
        let dominio = "RutaUTPTests.Recuperacion.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: dominio))
        defer { defaults.removePersistentDomain(forName: dominio) }
        try comprobar(defaults)
    }

    private func valores(_ copia: Data?) throws -> [String: Any] {
        let raiz = try XCTUnwrap(try PropertyListSerialization.propertyList(
            from: XCTUnwrap(copia), options: [], format: nil) as? [String: Any])
        XCTAssertEqual(raiz["version"] as? Int, 1)
        return try XCTUnwrap(raiz["valores"] as? [String: Any])
    }

    func testRespaldoConservaTiposBytesYClavesAusentes() throws {
        try conPreferencias { defaults in
            let original = Data([0, 255, 1, 2])
            defaults.set(original, forKey: "datos")
            defaults.set(["texto", "anterior"], forKey: "lista")
            defaults.set("conservar", forKey: "otra")
            var copia: Data?
            let archivo = try RecuperacionPreferencias.reiniciar(
                claves: ["datos", "lista", "ausente"], valoresNuevos: ["datos": Data("[]".utf8)],
                nombre: "prueba", defaults: defaults) { copia = $0; return self.archivoSimulado }
            XCTAssertEqual(archivo, archivoSimulado)
            let originales = try valores(copia)
            XCTAssertEqual(originales["datos"] as? Data, original)
            XCTAssertEqual(originales["lista"] as? [String], ["texto", "anterior"])
            XCTAssertNil(originales["ausente"])
            let raiz = try XCTUnwrap(try PropertyListSerialization.propertyList(
                from: XCTUnwrap(copia), options: [], format: nil) as? [String: Any])
            XCTAssertEqual(raiz["claves"] as? [String], ["datos", "lista", "ausente"])
            XCTAssertEqual(defaults.data(forKey: "datos"), Data("[]".utf8))
            XCTAssertNil(defaults.object(forKey: "lista"))
            XCTAssertNil(defaults.object(forKey: "ausente"))
            XCTAssertEqual(defaults.string(forKey: "otra"), "conservar")
        }
    }

    func testFalloDeRespaldoNoModificaNingunaClave() throws {
        try conPreferencias { defaults in
            let datos = Data("ilegible".utf8)
            defaults.set(datos, forKey: "datos")
            defaults.set("original", forKey: "orden")
            XCTAssertThrowsError(try RecuperacionPreferencias.reiniciar(
                claves: ["datos", "orden"], valoresNuevos: [:], nombre: "prueba", defaults: defaults) { _ in
                    throw CocoaError(.fileWriteOutOfSpace)
                })
            XCTAssertEqual(defaults.data(forKey: "datos"), datos)
            XCTAssertEqual(defaults.string(forKey: "orden"), "original")
        }
    }

    func testCambioDuranteRespaldoImpideReinicioDeAmbasClaves() throws {
        try conPreferencias { defaults in
            let original = Data("ilegible".utf8)
            defaults.set(original, forKey: "datos")
            var copia: Data?
            XCTAssertThrowsError(try RecuperacionPreferencias.reiniciar(
                claves: ["datos", "antesAusente"], valoresNuevos: [:], nombre: "prueba", defaults: defaults) {
                    copia = $0
                    defaults.set("nuevo", forKey: "antesAusente")
                    return self.archivoSimulado
                }) { error in
                    XCTAssertTrue(error is RecuperacionPreferencias.Fallo)
                }
            XCTAssertEqual(try valores(copia)["datos"] as? Data, original)
            XCTAssertEqual(defaults.data(forKey: "datos"), original)
            XCTAssertEqual(defaults.string(forKey: "antesAusente"), "nuevo")
        }
    }

    func testCuponesIlegiblesSeRespaldanAntesDeReiniciar() throws {
        try conPreferencias { defaults in
            let clave = "negocios.cupones.guardados"
            let original = Data("formato desconocido".utf8)
            defaults.set(original, forKey: clave)
            let servicio = NegociosService(defaults: defaults)
            XCTAssertTrue(servicio.datosCuponesInvalidos)
            var copia: Data?
            XCTAssertNotNil(try servicio.respaldarYReiniciarCupones { copia = $0; return self.archivoSimulado })
            XCTAssertEqual(try valores(copia)[clave] as? Data, original)
            XCTAssertEqual(defaults.stringArray(forKey: clave), [])
            XCTAssertFalse(servicio.datosCuponesInvalidos)
        }
    }

    func testFalloDeRespaldoDeCuponesConservaOriginal() throws {
        try conPreferencias { defaults in
            let clave = "negocios.cupones.guardados"
            defaults.set(123, forKey: clave)
            let servicio = NegociosService(defaults: defaults)
            XCTAssertThrowsError(try servicio.respaldarYReiniciarCupones { _ in
                throw CocoaError(.fileWriteOutOfSpace)
            })
            XCTAssertEqual(defaults.integer(forKey: clave), 123)
            XCTAssertTrue(servicio.datosCuponesInvalidos)
        }
    }

    func testCuponesValidosOReparadosNoSeReinician() throws {
        try conPreferencias { defaults in
            let clave = "negocios.cupones.guardados"
            defaults.set("ilegible", forKey: clave)
            let servicio = NegociosService(defaults: defaults)
            XCTAssertTrue(servicio.datosCuponesInvalidos)
            // Una reparación mientras se confirmaba no debe vaciar una lista válida.
            defaults.set(["negocio-anterior", "fuera-del-catalogo"], forKey: clave)
            XCTAssertNil(try servicio.respaldarYReiniciarCupones { _ in
                XCTFail("No corresponde crear un respaldo de una lista válida")
                return self.archivoSimulado
            })
            XCTAssertEqual(defaults.stringArray(forKey: clave), ["negocio-anterior", "fuera-del-catalogo"])
        }
    }

    func testRestablecerAccesosRespaldaAmbasClavesYConservaLugares() throws {
        try conPreferencias { defaults in
            let almacen = AlmacenLugares(defaults: defaults)
            let lugares = almacen.cargar()
            let datosLugares = defaults.data(forKey: LugaresStore.key)
            let seleccion = "formato desconocido"
            let orden = try JSONEncoder().encode([try XCTUnwrap(lugares.last?.id)])
            defaults.set(seleccion, forKey: "seguridad.tiles.v1")
            defaults.set(orden, forKey: "seguridad.tiles.orden.v1")
            let modelo = SeguridadLugaresModel(almacen: almacen)
            modelo.cargar()
            XCTAssertTrue(modelo.datosTilesInvalidos)
            var copia: Data?
            XCTAssertNotNil(try modelo.respaldarYReiniciarTiles { copia = $0; return self.archivoSimulado })
            let originales = try valores(copia)
            XCTAssertEqual(originales["seguridad.tiles.v1"] as? String, seleccion)
            XCTAssertEqual(originales["seguridad.tiles.orden.v1"] as? Data, orden)
            XCTAssertNil(defaults.object(forKey: "seguridad.tiles.v1"))
            XCTAssertNil(defaults.object(forKey: "seguridad.tiles.orden.v1"))
            XCTAssertEqual(defaults.data(forKey: LugaresStore.key), datosLugares)
            XCTAssertEqual(modelo.tilesActuales.map(\.id), lugares.map(\.id))
            XCTAssertFalse(modelo.datosTilesInvalidos)
            XCTAssertFalse(modelo.modoEdicion)
            XCTAssertNil(modelo.arrastrando)
        }
    }

    func testFalloDeRespaldoDeAccesosConservaSeleccionYOrden() throws {
        try conPreferencias { defaults in
            let almacen = AlmacenLugares(defaults: defaults)
            let modelo = SeguridadLugaresModel(almacen: almacen)
            let original = Data("ilegible".utf8)
            defaults.set(original, forKey: "seguridad.tiles.orden.v1")
            let seleccion = try JSONEncoder().encode([UUID]())
            defaults.set(seleccion, forKey: "seguridad.tiles.v1")
            modelo.cargar()
            XCTAssertThrowsError(try modelo.respaldarYReiniciarTiles { _ in
                throw CocoaError(.fileWriteOutOfSpace)
            })
            XCTAssertEqual(defaults.data(forKey: "seguridad.tiles.orden.v1"), original)
            XCTAssertEqual(defaults.data(forKey: "seguridad.tiles.v1"), seleccion)
            XCTAssertTrue(modelo.datosTilesInvalidos)
        }
    }

    func testAccesosValidosNoSeRestablecen() throws {
        try conPreferencias { defaults in
            let almacen = AlmacenLugares(defaults: defaults)
            let id = try XCTUnwrap(almacen.cargar().last?.id)
            let orden = try JSONEncoder().encode([id])
            defaults.set(orden, forKey: "seguridad.tiles.v1")
            defaults.set(orden, forKey: "seguridad.tiles.orden.v1")
            let modelo = SeguridadLugaresModel(almacen: almacen)
            modelo.cargar()
            XCTAssertNil(try modelo.respaldarYReiniciarTiles { _ in
                XCTFail("Los accesos válidos no se restablecen")
                return self.archivoSimulado
            })
            XCTAssertEqual(defaults.data(forKey: "seguridad.tiles.v1"), orden)
            XCTAssertEqual(defaults.data(forKey: "seguridad.tiles.orden.v1"), orden)
        }
    }
}


@MainActor
final class PreferenciasSimplesTests: XCTestCase {
    private func conPreferencias(_ comprobar: (UserDefaults) throws -> Void) throws {
        let suite = "RutaUTPTests.PreferenciasSimples.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try comprobar(defaults)
    }

    func testBooleanosRealesSeDistinguenDeAusenciaStringsYNumeros() throws {
        try conPreferencias { defaults in
            let clave = "preferencia"
            XCTAssertNil(PreferenciasApp.boolGuardado(para: clave, defaults: defaults))
            let incompatibles: [Any] = [NSNumber(value: 1), NSNumber(value: 0), NSNumber(value: 2), "YES", "false", Data([1])]
            for original in incompatibles {
                defaults.set(original, forKey: clave)
                XCTAssertNil(PreferenciasApp.boolGuardado(para: clave, defaults: defaults))
                XCTAssertTrue(try XCTUnwrap(original as? NSObject).isEqual(defaults.object(forKey: clave)))
            }
            for valor in [true, false] {
                defaults.set(valor, forKey: clave)
                XCTAssertEqual(PreferenciasApp.boolGuardado(para: clave, defaults: defaults), valor)
            }
        }
    }

    func testConfirmarTematicaDeRespaldoReparaClaveSinEscrituraInicial() throws {
        try conPreferencias { defaults in
            defaults.set("empresa-futura", forKey: TematicaEmpresaStore.llave)
            let store = TematicaEmpresaStore(defaults: defaults)
            XCTAssertEqual(store.seleccion, .utp)
            XCTAssertEqual(defaults.string(forKey: TematicaEmpresaStore.llave), "empresa-futura")
            store.seleccionar(.utp)
            XCTAssertEqual(defaults.string(forKey: TematicaEmpresaStore.llave), "utp")
            store.seleccionar(.interbank)
            XCTAssertEqual(TematicaEmpresaStore(defaults: defaults).seleccion, .interbank)
        }
    }

    func testIdiomaDesconocidoSeConservaHastaUnaEleccionValida() throws {
        try conPreferencias { defaults in
            defaults.set("fr", forKey: "idioma.app")
            let store = IdiomaManager(defaults: defaults, argumentos: [])
            XCTAssertEqual(store.codigo, "es")
            XCTAssertEqual(defaults.string(forKey: "idioma.app"), "fr")
            store.seleccionar(codigo: "desconocido")
            XCTAssertEqual(defaults.string(forKey: "idioma.app"), "fr")
            store.seleccionar(codigo: "es")
            XCTAssertEqual(defaults.string(forKey: "idioma.app"), "es")
            store.alternar()
            XCTAssertEqual(store.codigo, "en")
            XCTAssertTrue(IdiomaManager(defaults: defaults, argumentos: []).esIngles)
        }
    }

    func testIdiomaSigueRegistrandoCambiosConObservation() throws {
        try conPreferencias { defaults in
            let store = IdiomaManager(defaults: defaults, argumentos: [])
            let cambio = expectation(description: "Cambio observado del idioma")
            withObservationTracking { _ = store.esIngles } onChange: { cambio.fulfill() }
            store.alternar()
            XCTAssertEqual(store.codigo, "en")
            XCTAssertEqual(defaults.string(forKey: "idioma.app"), "en")
            // El callback de Observation se entrega sin esperar otro render.
            wait(for: [cambio], timeout: 1)
        }
    }

    func testReferenciaIncompatibleNoSustituyeSedeEmpresarial() throws {
        try conPreferencias { defaults in
            let id = "interbank-centro-gamarra"
            defaults.set(id, forKey: SedeTrabajoStore.llave)
            defaults.set("YES", forKey: SedeTrabajoStore.llaveReferenciaUTP)
            let store = SedeTrabajoStore(defaults: defaults)
            XCTAssertFalse(store.utpComoReferencia)
            XCTAssertEqual(store.sede?.id, id)
            XCTAssertEqual(defaults.string(forKey: SedeTrabajoStore.llaveReferenciaUTP), "YES")
            store.seleccionar(id: id)
            XCTAssertEqual(PreferenciasApp.boolGuardado(para: SedeTrabajoStore.llaveReferenciaUTP, defaults: defaults), false)
            defaults.set(true, forKey: SedeTrabajoStore.llaveReferenciaUTP)
            let campus = SedeTrabajoStore(defaults: defaults)
            XCTAssertTrue(campus.utpComoReferencia)
            XCTAssertEqual(campus.sede?.id, CatalogoSedesTrabajo.campusUTP.id)
        }
    }

    func testVisibilidadNoCoerceNumerosYConservaEleccionPorEmpresa() throws {
        try conPreferencias { defaults in
            let clave = "perfil.carnet.foto.interbank.visible.v1"
            defaults.set(2, forKey: clave)
            let store = PreferenciasVisualesPerfilStore(defaults: defaults)
            XCTAssertFalse(store.visible(.foto, empresa: .interbank))
            XCTAssertTrue(store.visible(.foto, empresa: .utp))
            XCTAssertEqual(defaults.integer(forKey: clave), 2)
            store.establecer(true, carnet: .foto, empresa: .interbank)
            XCTAssertEqual(PreferenciasApp.boolGuardado(para: clave, defaults: defaults), true)
            let nuevo = PreferenciasVisualesPerfilStore(defaults: defaults)
            XCTAssertTrue(nuevo.visible(.foto, empresa: .interbank))
            XCTAssertFalse(nuevo.visible(.foto, empresa: .bembos))
        }
    }
}

/// Solo directorios temporales aislados; no lee documentos ni preferencias reales.
final class ListadoRespaldosTests: XCTestCase {
    private func carpetaTemporal() throws -> URL {
        let carpeta = FileManager.default.temporaryDirectory
            .appendingPathComponent("RutaUTPTests.Respaldos.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        return carpeta
    }

    func testDirectorioAusenteDevuelveVacioSinCrearlo() async throws {
        let raiz = try carpetaTemporal()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let ausente = raiz.appendingPathComponent("no-creado", isDirectory: true)
        let copias = try await RecuperacionPreferencias.listar(directorio: ausente)
        XCTAssertTrue(copias.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ausente.path))
    }

    func testListadoConservaCopiasAntiguasActualesEIlegiblesYExcluyeEnlaces() async throws {
        let carpeta = try carpetaTemporal()
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let originales: [String: Data] = [
            "a-lineas.plist": try PropertyListSerialization.data(fromPropertyList: [
                "clave": "lineas.guardadas.v1", "valor": Data([255]), "fecha": Date()
            ], format: .binary, options: 0),
            "b-cupones.plist": try PropertyListSerialization.data(fromPropertyList: [
                "version": 1, "claves": ["negocios.cupones.guardados"],
                "valores": ["negocios.cupones.guardados": "ilegible"], "fecha": Date()
            ], format: .binary, options: 0),
            "c-danado.plist": Data([0, 255, 1])
        ]
        let fecha = Date(timeIntervalSince1970: 1_000)
        for (nombre, data) in originales {
            let url = carpeta.appendingPathComponent(nombre)
            try data.write(to: url)
            try FileManager.default.setAttributes([.modificationDate: fecha], ofItemAtPath: url.path)
        }
        try Data("conservar".utf8).write(to: carpeta.appendingPathComponent("otro.txt"))
        try FileManager.default.createDirectory(at: carpeta.appendingPathComponent("carpeta.plist"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: carpeta.appendingPathComponent("enlace.plist"),
                                                   withDestinationURL: carpeta.appendingPathComponent("a-lineas.plist"))
        let copias = try await RecuperacionPreferencias.listar(directorio: carpeta)
        XCTAssertEqual(copias.map { $0.url.lastPathComponent }, originales.keys.sorted())
        for copia in copias {
            let original = try XCTUnwrap(originales[copia.url.lastPathComponent])
            XCTAssertEqual(try Data(contentsOf: copia.url), original)
            XCTAssertEqual(copia.bytes, original.count)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: carpeta.appendingPathComponent("otro.txt").path))
    }

    func testCadaListadoReleeDiscoYOrdenaPorFecha() async throws {
        let carpeta = try carpetaTemporal()
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let anterior = carpeta.appendingPathComponent("anterior.plist")
        try Data([1]).write(to: anterior)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)],
                                              ofItemAtPath: anterior.path)
        let primero = try await RecuperacionPreferencias.listar(directorio: carpeta)
        XCTAssertEqual(primero.map(\.url), [anterior])
        let nuevo = carpeta.appendingPathComponent("nuevo.plist")
        try Data([2]).write(to: nuevo)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000)],
                                              ofItemAtPath: nuevo.path)
        let segundo = try await RecuperacionPreferencias.listar(directorio: carpeta)
        XCTAssertEqual(segundo.map(\.url), [nuevo, anterior])
        try FileManager.default.removeItem(at: anterior)
        let tercero = try await RecuperacionPreferencias.listar(directorio: carpeta)
        XCTAssertEqual(tercero.map(\.url), [nuevo])
    }

    func testFalloDeLecturaNoSePresentaComoListadoVacio() async throws {
        let carpeta = try carpetaTemporal()
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let archivo = carpeta.appendingPathComponent("no-es-directorio")
        let original = Data([0, 1, 2])
        try original.write(to: archivo)
        do {
            _ = try await RecuperacionPreferencias.listar(directorio: archivo)
            XCTFail("Un archivo no puede leerse como directorio de respaldos")
        } catch {
            XCTAssertEqual(try Data(contentsOf: archivo), original)
        }
    }
}
