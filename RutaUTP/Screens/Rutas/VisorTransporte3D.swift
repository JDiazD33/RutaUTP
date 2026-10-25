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
    private var yaw: Float = .pi / 4
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
        // Un mismo encuadre para las tres formas, manteniendo sus proporciones.
        let escala: Float = 2.6 / extensionMayor
        entidad.scale *= escala
        entidad.position -= caja.center * escala
        registrarContornos(entidad)
        guard !contornos.isEmpty else {
            cambioEstado?(.fallo)
            return
        }
        if let identificacion, identificacion.tipoModelo == tipo {
            aplicarPinturaReferencia(a: entidad, colores: identificacion.colores?.colores ?? [], tipo: tipo)
            agregarCarteles(a: entidad, identificacion: identificacion, caja: caja, tipo: tipo)
        }
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

    private func aplicarPinturaReferencia(a entidad: Entity, colores: [ColorTransporteReferencia], tipo: TipoTransporte3D) {
        guard let principal = colores.first else { return }
        for (parte, indices) in carrocerias {
            guard var componente = parte.components[ModelComponent.self] else { continue }
            for indice in indices {
                componente.materials[indice] = SimpleMaterial(color: UIColor(principal.color), roughness: 0.6, isMetallic: false)
            }
            parte.components.set(componente)
        }
        // Franjas esquematicas sobre la carroceria, sin tapar las ruedas o ventanas.
        // No se reproducen graficos, marcas ni una pintura exacta de una unidad.
        for (indice, color) in colores.dropFirst().enumerated() {
            let alto: Float
            let y: Float
            let mitadAncho: Float
            let largo: Float
            let z: Float
            switch tipo {
            case .micro:
                alto = indice == 0 ? 0.16 : 0.07
                y = indice == 0 ? 1.28 : 1.44
                mitadAncho = 1.18
                largo = 6.5
                z = -0.45
            case .combi:
                let paso = Float(0.26) / Float(max(colores.count - 1, 1))
                alto = paso * 0.72
                y = 1.0 + Float(indice) * paso
                mitadAncho = 0.99
                largo = 3.9
                z = -0.45
            case .colectivo:
                let paso = Float(0.20) / Float(max(colores.count - 1, 1))
                alto = paso * 0.70
                y = 0.78 + Float(indice) * paso
                mitadAncho = 0.911
                largo = 4.0
                z = 0
            }
            for lado in [Float(-1), Float(1)] {
                let franja = ModelEntity(mesh: .generateBox(size: [0.025, alto, largo]),
                                         materials: [SimpleMaterial(color: UIColor(color.color), roughness: 0.6, isMetallic: false)])
                franja.position = [lado * mitadAncho, y, z]
                entidad.addChild(franja)
            }
        }
    }

    private func agregarCarteles(a entidad: Entity, identificacion: IdentificacionRuta3D, caja: BoundingBox, tipo: TipoTransporte3D) {
        guard !identificacion.letra.isEmpty else { return }
        let factor: Float
        let posiciones: [(SIMD3<Float>, simd_quatf)]
        switch tipo {
        case .micro:
            factor = 1
            posiciones = [
                ([-0.36, 2.12, caja.max.z - 0.08], simd_quatf(angle: 0, axis: [0, 1, 0])),
                ([0, 2.12, caja.min.z - 0.04], simd_quatf(angle: .pi, axis: [0, 1, 0])),
                ([1.20, 2.12, 1.80], simd_quatf(angle: .pi / 2, axis: [0, 1, 0])),
                ([-1.20, 2.12, 1.80], simd_quatf(angle: -.pi / 2, axis: [0, 1, 0]))
            ]
        case .combi:
            factor = 0.74
            // La inclinacion sigue el parabrisas del recurso combi.usdz.
            posiciones = [
                ([-0.30, 1.82, 2.39], simd_quatf(angle: -atan(Float(0.97 / 0.91)), axis: [1, 0, 0])),
                ([0, 1.75, caja.min.z - 0.025], simd_quatf(angle: .pi, axis: [0, 1, 0])),
                ([1.0, 1.75, -0.85], simd_quatf(angle: .pi / 2, axis: [0, 1, 0])),
                ([-1.0, 1.75, -0.85], simd_quatf(angle: -.pi / 2, axis: [0, 1, 0]))
            ]
        case .colectivo:
            factor = 0.43
            // Carteles pequenos sobre ambos cristales, siguiendo el sedan del USDZ.
            posiciones = [
                ([-0.27, 1.29, 0.79], simd_quatf(angle: -atan(Float(0.673 / 0.481)), axis: [1, 0, 0])),
                ([0, 1.34, -1.13], simd_quatf(angle: .pi, axis: [0, 1, 0])
                    * simd_quatf(angle: -atan(Float(0.740 / 0.495)), axis: [1, 0, 0]))
            ]
        }
        let plantilla = Entity()
        plantilla.name = "CartelDeRuta"
        plantilla.addChild(ModelEntity(mesh: .generateBox(size: [1.32 * factor, 0.91 * factor, 0.025], cornerRadius: 0.008),
                                        materials: [UnlitMaterial(color: .white)]))
        plantilla.addChild(textoCartel(identificacion.codigo, ancho: 1.10 * factor, alto: 0.18 * factor, y: 0.26 * factor))
        let letra = textoCartel(identificacion.letraPrincipal,
                               ancho: (identificacion.distintivoLetra == nil ? 1.15 : 0.75) * factor,
                               alto: 0.47 * factor, y: -0.09 * factor)
        if let distintivo = identificacion.distintivoLetra {
            letra.position.x -= 0.18 * factor
            let marca = textoCartel(distintivo, ancho: 0.32 * factor, alto: 0.18 * factor, y: -0.22 * factor)
            marca.position.x += 0.44 * factor
            plantilla.addChild(marca)
        }
        plantilla.addChild(letra)
        // +Z es el frente del recurso. Las letras forman parte de la escena 3D.
        for (posicion, orientacion) in posiciones {
            let cartel = plantilla.clone(recursive: true)
            cartel.position = posicion
            cartel.orientation = orientacion
            entidad.addChild(cartel)
        }
    }

    private func textoCartel(_ texto: String, ancho: Float, alto: Float, y: Float) -> Entity {
        let malla = MeshResource.generateText(texto, extrusionDepth: 0.008,
                                             font: .systemFont(ofSize: 1, weight: .heavy),
                                             containerFrame: .zero, alignment: .center, lineBreakMode: .byClipping)
        let letras = ModelEntity(mesh: malla, materials: [UnlitMaterial(color: .black)])
        let caja = letras.visualBounds(relativeTo: nil)
        let escala = min(ancho / max(caja.extents.x, 0.001), alto / max(caja.extents.y, 0.001))
        letras.scale = SIMD3(repeating: escala)
        letras.position = [-caja.center.x * escala, y - caja.center.y * escala, 0.025]
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
        yaw = .pi / 4
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
