import Combine

/// Conserva la creación diferida de StateObject y una instancia por contexto de pantalla.
/// La UI observa las propiedades del modelo; este contenedor no reenvía cambios.
@MainActor
final class ScreenModelStore<Model: AnyObject>: ObservableObject {
    // Combine consulta este requisito sin aislamiento. La referencia es
    // constante; send y la sustitución del modelo ocurren en MainActor.
    nonisolated(unsafe) let objectWillChange = ObservableObjectPublisher()
    private(set) var model: Model

    init(_ model: Model) {
        self.model = model
    }

    /// Sustituye explícitamente un contexto completo; no reenvía ticks del modelo.
    func reemplazar(_ nuevo: Model) {
        objectWillChange.send()
        model = nuevo
    }
}
