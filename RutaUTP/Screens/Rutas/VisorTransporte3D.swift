import SwiftUI
import RealityKit
import Combine
import simd

struct VisorTransporte3D: UIViewRepresentable {
    let tipo: TipoTransporte3D
    let variante: VarianteTransporte3D
    let color: UIColor
    let intento: Int
    let orden: OrdenTransporte3D?
    let identificacion: IdentificacionRuta3D?
    @Binding var estado: EstadoTransporte3D

    func makeUIView(context: Context) -> VistaTransporte3D {
        let view = VistaTransporte3D()
        view.cambioEstado = { nuevo in
            Task { @MainActor in estado = nuevo }
        }
        return view
    }

    func updateUIView(_ view: VistaTransporte3D, context: Context) {
        view.actualizar(tipo: tipo, variante: variante, color: color, intento: intento, orden: orden, identificacion: identificacion)
    }

    static func dismantleUIView(_ view: VistaTransporte3D, coordinator: ()) {
        view.cerrar()
    }
}

/// Visor nativo sin sesion AR ni acceso a la camara del telefono.
final class VistaTransporte3D: UIView, UIGestureRecognizerDelegate {
    var cambioEstado: ((EstadoTransporte3D) -> Void)?
    private let render = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
    private let ancla = AnchorEntity(world: .zero)
    private let camara = PerspectiveCamera()
    private var modelo: Entity?
    private var contornos: [(Entity, [Int])] = []
    private var carrocerias: [(Entity, [Int])] = []
    private var identificacion: IdentificacionRuta3D?
    private var carga: Task<Void, Never>?
    private var cargaAnterior: AnyCancellable?
    private var generacion = UUID()
    private var recurso: String?
    private var ultimaOrden: UUID?
    private var colorContorno = UIColor.red
    private var yaw: Float = -.pi / 6
    private var pitch: Float = .pi / 8
    private var distancia: Float = 6
    private var distanciaInicial: Float = 6
    private var objetivo = SIMD3<Float>.zero
    private var radio: Float = 1.5
    private var tamanoAnterior = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        render.environment.background = .color(.white)
        render.renderOptions = [.disableMotionBlur, .disableDepthOfField]
        addSubview(render)
        render.scene.addAnchor(ancla)
        camara.camera.fieldOfViewInDegrees = 36
        camara.camera.near = 0.01
        camara.camera.far = 100
        ancla.addChild(camara)
        let luz = DirectionalLight()
        luz.light.intensity = 2200
        luz.look(at: .zero, from: [3, 5, 4], relativeTo: nil)
        ancla.addChild(luz)
        let relleno = DirectionalLight()
        relleno.light.intensity = 1300
        relleno.look(at: .zero, from: [-4, 3, -2], relativeTo: nil)
        ancla.addChild(relleno)

        let giro = UIPanGestureRecognizer(target: self, action: #selector(arrastrar(_:)))
        giro.maximumNumberOfTouches = 2
        giro.delegate = self
        render.addGestureRecognizer(giro)
        let zoom = UIPinchGestureRecognizer(target: self, action: #selector(ampliar(_:)))
        zoom.delegate = self
        render.addGestureRecognizer(zoom)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no disponible") }

    override func layoutSubviews() {
        super.layoutSubviews()
        render.frame = bounds
        if bounds.size != tamanoAnterior, bounds.width > 0, bounds.height > 0 {
            tamanoAnterior = bounds.size
            encuadrar()
        }
    }

    func actualizar(tipo: TipoTransporte3D, variante: VarianteTransporte3D, color: UIColor, intento: Int, orden: OrdenTransporte3D?, identificacion: IdentificacionRuta3D?) {
        self.identificacion = identificacion
        if !colorContorno.isEqual(color) {
            colorContorno = color
            colorear()
        }
        let clave = "\(tipo.rawValue)-\(variante.rawValue)-\(intento)-\(identificacion?.claveModelo ?? "galeria")"
        if recurso != clave {
            recurso = clave
            ultimaOrden = orden?.id
            cargar(tipo, variante: variante)
        }
        if let orden, orden.id != ultimaOrden {
            ultimaOrden = orden.id
            ejecutar(orden.accion)
        }
    }

    private func cargar(_ tipo: TipoTransporte3D, variante: VarianteTransporte3D) {
        carga?.cancel()
        cargaAnterior?.cancel()
        modelo?.removeFromParent()
        modelo = nil
        contornos.removeAll()
        carrocerias.removeAll()
        generacion = UUID()
        let solicitud = generacion
        cambioEstado?(.cargando)
        guard let url = Bundle.main.url(forResource: tipo.rawValue, withExtension: "usdz", subdirectory: variante.subdirectorioRecurso) else {
            cambioEstado?(.fallo)
            return
        }
        if #available(iOS 18.0, *) {
            carga = Task { @MainActor [weak self] in
                do {
                    let entidad = try await Entity(contentsOf: url)
                    guard !Task.isCancelled, let self, self.generacion == solicitud else { return }
                    self.presentar(entidad, tipo: tipo, variante: variante)
                } catch {
                    guard !Task.isCancelled, let self, self.generacion == solicitud else { return }
                    self.cambioEstado?(.fallo)
                }
            }
        } else {
            // La version asincrona de Combine mantiene compatibilidad con iOS 17.5.
            cargaAnterior = Entity.loadAsync(contentsOf: url)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] resultado in
                    guard let self, self.generacion == solicitud else { return }
                    if case .failure = resultado { self.cambioEstado?(.fallo) }
                } receiveValue: { [weak self] entidad in
                    guard let self, self.generacion == solicitud else { return }
                    self.presentar(entidad, tipo: tipo, variante: variante)
                }
        }
    }

    private func presentar(_ entidad: Entity, tipo: TipoTransporte3D, variante: VarianteTransporte3D) {
        let caja = entidad.visualBounds(relativeTo: nil)
        let extensionMayor = max(caja.extents.x, caja.extents.y, caja.extents.z)
        guard extensionMayor.isFinite, extensionMayor > 0 else {
            cambioEstado?(.fallo)
            return
        }
        registrarContornos(entidad)
        guard !contornos.isEmpty else {
            cambioEstado?(.fallo)
            return
        }
        if let identificacion, identificacion.tipoModelo == tipo {
            // Los dos juegos de USDZ declaran unidades distintas. Los adornos se
            // anclan al mesh autorado en metros y heredan sus transformaciones.
            guard let carroceria = carrocerias.first?.0 else {
                cambioEstado?(.fallo)
                return
            }
            aplicarPinturaReferencia(a: carroceria, colores: identificacion.colores?.colores ?? [], tipo: tipo, variante: variante)
            agregarCartel(a: carroceria, identificacion: identificacion, tipo: tipo, variante: variante)
        }
        // Un mismo encuadre para las seis formas, manteniendo sus proporciones.
        let escala: Float = 2.6 / extensionMayor
        entidad.scale *= escala
        entidad.position -= caja.center * escala
        modelo = entidad
        ancla.addChild(entidad)
        radio = simd_length(caja.extents * escala) / 2
        colorear()
        restablecer()
        cambioEstado?(.listo)
    }

    private func registrarContornos(_ entidad: Entity) {
        if let componente = entidad.components[ModelComponent.self] {
            let indices = componente.materials.enumerated().compactMap { indice, material -> Int? in
                if entidad.name == "ContornoMarca" { return indice }
                if #available(iOS 18.0, *), material.name == "ContornoMarca" { return indice }
                return nil
            }
            if !indices.isEmpty { contornos.append((entidad, indices)) }
            let indicesCarroceria = componente.materials.enumerated().compactMap { indice, material -> Int? in
                if entidad.name == "Carroceria" { return indice }
                if #available(iOS 18.0, *), material.name == "Carroceria" { return indice }
                return nil
            }
            if !indicesCarroceria.isEmpty { carrocerias.append((entidad, indicesCarroceria)) }
        }
        for hijo in entidad.children { registrarContornos(hijo) }
    }

    private func colorear() {
        for (entidad, indices) in contornos {
            guard var componente = entidad.components[ModelComponent.self] else { continue }
            for indice in indices {
                componente.materials[indice] = UnlitMaterial(color: colorContorno)
            }
            entidad.components.set(componente)
        }
    }

    private func aplicarPinturaReferencia(a entidad: Entity, colores: [ColorTransporteReferencia], tipo: TipoTransporte3D, variante: VarianteTransporte3D) {
        guard let principal = colores.first else { return }
        for (parte, indices) in carrocerias {
            guard var componente = parte.components[ModelComponent.self] else { continue }
            for indice in indices {
                componente.materials[indice] = SimpleMaterial(color: UIColor(principal.color), roughness: 0.6, isMetallic: false)
            }
            parte.components.set(componente)
        }
        // Bandas dentro de la zona recta de cada carroceria, sobre los arcos de
        // rueda y bajo el cristal. El sedan detallado se estrecha hacia el capo:
        // su franja termina antes para seguir apoyada en el costado.
        let mitadAncho: Float
        let largo: Float
        let z: Float
        let banda: ClosedRange<Float>
        switch (variante, tipo) {
        case (.original, .micro):
            mitadAncho = 1.17; largo = 6.5; z = -0.45; banda = 1.20...1.48
        case (.detallado, .micro):
            mitadAncho = 1.17; largo = 6.4; z = -0.50; banda = 1.20...1.48
        case (.original, .combi):
            mitadAncho = 0.98; largo = 3.9; z = -0.45; banda = 0.93...1.19
        case (.detallado, .combi):
            mitadAncho = 0.97; largo = 3.3; z = -0.45; banda = 0.90...1.06
        case (.original, .colectivo):
            mitadAncho = 0.91; largo = 4.0; z = 0; banda = 0.79...0.95
        case (.detallado, .colectivo):
            mitadAncho = 0.90; largo = 2.15; z = -0.425; banda = 0.79...0.88
        }
        let paso = (banda.upperBound - banda.lowerBound) / Float(max(colores.count - 1, 1))
        for (indice, color) in colores.dropFirst().enumerated() {
            for lado in [Float(-1), Float(1)] {
                let franja = ModelEntity(mesh: .generateBox(size: [0.012, paso * 0.80, largo]),
                                         materials: [SimpleMaterial(color: UIColor(color.color), roughness: 0.6, isMetallic: false)])
                franja.name = "FranjaReferencia" + String(indice)
                franja.position = [lado * mitadAncho, banda.lowerBound + (Float(indice) + 0.5) * paso, z]
                entidad.addChild(franja)
            }
        }
    }

    private func agregarCartel(a entidad: Entity, identificacion: IdentificacionRuta3D, tipo: TipoTransporte3D, variante: VarianteTransporte3D) {
        guard !identificacion.letra.isEmpty else { return }
        let posicion: SIMD3<Float>
        let tamano: SIMD2<Float>
        let inclinacion: Float
        // Coordenadas del cristal de cada recurso, en el espacio local de Carroceria.
        // -X es el acompanante: todo el cartel queda bajo y dentro de esa mitad
        // del parabrisas. No hay copias sobre carroceria, conductor o ventanas laterales.
        switch (variante, tipo) {
        case (.original, .micro):
            posicion = [-0.60, 1.801, 4.331]
            tamano = [0.56, 0.34]
            inclinacion = -atan(0.14 / 1.5)
        case (.original, .combi):
            posicion = [-0.48, 1.612, 2.583]
            tamano = [0.44, 0.30]
            inclinacion = -atan(0.97 / 0.91)
        case (.original, .colectivo):
            posicion = [-0.42, 1.200, 0.891]
            tamano = [0.34, 0.24]
            inclinacion = -atan(0.673 / 0.481)
        case (.detallado, .micro):
            posicion = [-0.60, 1.7983, 4.2398]
            tamano = [0.56, 0.34]
            inclinacion = -0.152454
        case (.detallado, .combi):
            posicion = [-0.48, 1.39379, 1.94615]
            tamano = [0.44, 0.30]
            inclinacion = -0.631219
        case (.detallado, .colectivo):
            posicion = [-0.42, 1.09999, 0.77982]
            tamano = [0.34, 0.24]
            inclinacion = -1.057528
        }
        let cartel = Entity()
        cartel.name = "CartelDeRuta"
        cartel.addChild(ModelEntity(mesh: .generateBox(size: [tamano.x, tamano.y, 0.006], cornerRadius: 0.003),
                                    materials: [UnlitMaterial(color: .white)]))
        cartel.addChild(textoCartel(identificacion.codigo, ancho: tamano.x * 0.84,
                                   alto: tamano.y * 0.16, y: tamano.y * 0.31))
        let letra = textoCartel(identificacion.letraPrincipal,
                               ancho: tamano.x * (identificacion.distintivoLetra == nil ? 0.86 : 0.56),
                               alto: tamano.y * 0.54, y: -tamano.y * 0.12)
        if let distintivo = identificacion.distintivoLetra {
            letra.position.x -= tamano.x * 0.15
            let marca = textoCartel(distintivo, ancho: tamano.x * 0.24,
                                    alto: tamano.y * 0.20, y: -tamano.y * 0.29)
            marca.position.x += tamano.x * 0.32
            cartel.addChild(marca)
        }
        cartel.addChild(letra)
        cartel.position = posicion
        cartel.orientation = simd_quatf(angle: inclinacion, axis: [1, 0, 0])
        entidad.addChild(cartel)
    }

    private func textoCartel(_ texto: String, ancho: Float, alto: Float, y: Float) -> Entity {
        let malla = MeshResource.generateText(texto, extrusionDepth: 0.001,
                                             font: .systemFont(ofSize: 1, weight: .heavy),
                                             containerFrame: .zero, alignment: .center, lineBreakMode: .byClipping)
        let letras = ModelEntity(mesh: malla, materials: [UnlitMaterial(color: .black)])
        let caja = letras.visualBounds(relativeTo: nil)
        let escala = min(ancho / max(caja.extents.x, 0.001), alto / max(caja.extents.y, 0.001))
        letras.scale = SIMD3(repeating: escala)
        letras.position = [-caja.center.x * escala, y - caja.center.y * escala, 0.004]
        return letras
    }

    private func encuadrar() {
        let aspecto = Float(max(bounds.width, 1) / max(bounds.height, 1))
        let mitadVertical = Float.pi / 10
        let mitadHorizontal = atan(tan(mitadVertical) * aspecto)
        distanciaInicial = radio / sin(min(mitadVertical, mitadHorizontal)) * 1.1
        distancia = distanciaInicial
        actualizarCamara()
    }

    private func restablecer() {
        // Mostrar de entrada el parabrisas y la esquina del acompanante (-X).
        yaw = -.pi / 6
        pitch = .pi / 8
        objetivo = .zero
        encuadrar()
    }

    private func actualizarCamara() {
        let desplazamiento = SIMD3<Float>(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distancia
        camara.look(at: objetivo, from: objetivo + desplazamiento, relativeTo: nil)
    }

    private func ejecutar(_ accion: AccionTransporte3D) {
        guard modelo != nil else { return }
        switch accion {
        case .izquierda: yaw -= .pi / 9
        case .derecha: yaw += .pi / 9
        case .acercar: aplicarZoom(0.82)
        case .alejar: aplicarZoom(1.22)
        case .restablecer: restablecer()
        case .moverIzquierda: mover(x: -0.15, y: 0)
        case .moverDerecha: mover(x: 0.15, y: 0)
        case .moverArriba: mover(x: 0, y: 0.15)
        case .moverAbajo: mover(x: 0, y: -0.15)
        }
        actualizarCamara()
    }

    private func aplicarZoom(_ factor: Float) {
        distancia = min(max(distancia * factor, radio * 1.25), distanciaInicial * 2.5)
    }

    private func mover(x: Float, y: Float) {
        objetivo += camara.orientation.act(SIMD3<Float>(x, y, 0))
        let limite = radio * 2
        objetivo = simd_clamp(objetivo, SIMD3(repeating: -limite), SIMD3(repeating: limite))
    }

    @objc private func arrastrar(_ gesto: UIPanGestureRecognizer) {
        guard modelo != nil else { return }
        let cambio = gesto.translation(in: render)
        gesto.setTranslation(.zero, in: render)
        if gesto.numberOfTouches >= 2 {
            let unidad = distancia * 2 * tan(Float.pi / 10) / Float(max(bounds.height, 1))
            mover(x: -Float(cambio.x) * unidad, y: Float(cambio.y) * unidad)
        } else {
            yaw -= Float(cambio.x) * 0.009
            pitch = min(max(pitch + Float(cambio.y) * 0.007, -.pi / 12), .pi / 2.3)
        }
        actualizarCamara()
    }

    @objc private func ampliar(_ gesto: UIPinchGestureRecognizer) {
        guard modelo != nil, gesto.scale.isFinite, gesto.scale > 0 else { return }
        aplicarZoom(1 / Float(gesto.scale))
        gesto.scale = 1
        actualizarCamara()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer.view === render && otherGestureRecognizer.view === render
    }

    func cerrar() {
        generacion = UUID()
        carga?.cancel()
        carga = nil
        cargaAnterior?.cancel()
        cargaAnterior = nil
        modelo = nil
        contornos.removeAll()
        carrocerias.removeAll()
        render.scene.anchors.removeAll()
        cambioEstado = nil
    }
}
