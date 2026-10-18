import SwiftUI
import RealityKit
import Combine
import simd

struct VisorTransporte3D: UIViewRepresentable {
    let tipo: TipoTransporte3D
    let color: UIColor
    let intento: Int
    let orden: OrdenTransporte3D?
    @Binding var estado: EstadoTransporte3D

    func makeUIView(context: Context) -> VistaTransporte3D {
        let view = VistaTransporte3D()
        view.cambioEstado = { nuevo in
            Task { @MainActor in estado = nuevo }
        }
        return view
    }

    func updateUIView(_ view: VistaTransporte3D, context: Context) {
        view.actualizar(tipo: tipo, color: color, intento: intento, orden: orden)
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

    func actualizar(tipo: TipoTransporte3D, color: UIColor, intento: Int, orden: OrdenTransporte3D?) {
        if !colorContorno.isEqual(color) {
            colorContorno = color
            colorear()
        }
        let clave = "\(tipo.rawValue)-\(intento)"
        if recurso != clave {
            recurso = clave
            cargar(tipo)
        }
        if let orden, orden.id != ultimaOrden {
            ultimaOrden = orden.id
            ejecutar(orden.accion)
        }
    }

    private func cargar(_ tipo: TipoTransporte3D) {
        carga?.cancel()
        cargaAnterior?.cancel()
        modelo?.removeFromParent()
        modelo = nil
        contornos.removeAll()
        generacion = UUID()
        let solicitud = generacion
        cambioEstado?(.cargando)
        guard let url = Bundle.main.url(forResource: tipo.rawValue, withExtension: "usdz", subdirectory: "Transportes3D") else {
            cambioEstado?(.fallo)
            return
        }
        if #available(iOS 18.0, *) {
            carga = Task { @MainActor [weak self] in
                do {
                    let entidad = try await Entity(contentsOf: url)
                    guard !Task.isCancelled, let self, self.generacion == solicitud else { return }
                    self.presentar(entidad)
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
                    self.presentar(entidad)
                }
        }
    }

    private func presentar(_ entidad: Entity) {
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
        render.scene.anchors.removeAll()
        cambioEstado = nil
    }
}
