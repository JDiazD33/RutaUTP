import SwiftUI
import AVFoundation
import UIKit

struct CarnetScannerView: View {
    @Environment(\.dismiss) private var dismiss
    var empresa: TematicaEmpresa = .utp
    var onCapture: () -> Void
    @State private var foto: UIImage?
    @State private var picker: Fuente?
    @State private var guardando = false
    @State private var errorGuardado = false
    @State private var permisoDenegado = false
    @State private var verFoto = false
    @State private var fotoPorEditar: UIImage?
    @State private var editor: FotoParaEncuadrar?
    @State private var selectorCerrado = true

    private enum Fuente: String, Identifiable {
        case camara, galeria
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let foto {
                        Button { verFoto = true } label: {
                            Image(uiImage: foto)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L.t("Ver la foto del carné completa", "View the whole card photo"))
                        Label(L.t("Foto guardada en este dispositivo", "Photo saved on this device"), systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(Color.appAccent)
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "person.text.rectangle")
                                .font(.system(size: 64, weight: .light))
                                .foregroundStyle(Color.appAccent)
                            Text(L.t("Tu carné, siempre a mano", "Your card, always handy"))
                                .font(.title3.bold())
                            Text(L.t("Añade una foto donde se vea completo y el texto sea legible.", "Add a photo showing the entire card with readable text."))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .padding(.horizontal, 16)
                        .background(Color.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 18))
                    }
                    if guardando {
                        ProgressView(L.t("Guardando foto…", "Saving photo…"))
                    }
                    VStack(spacing: 12) {
                        Button(action: abrirCamara) {
                            Label(L.t("Tomar foto", "Take photo"), systemImage: "camera")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.primaryFill)
                        .foregroundStyle(Color.onPrimaryFill)
                        .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                        Button { selectorCerrado = false; picker = .galeria } label: {
                            Label(L.t("Elegir de la galería", "Choose from photo library"), systemImage: "photo.on.rectangle")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        if let foto {
                            Button {
                                editor = FotoParaEncuadrar(image: foto)
                            } label: {
                                Label(L.t("Ajustar encuadre", "Adjust framing"), systemImage: "crop")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .tint(Color.appAccent)
                    .disabled(guardando)
                    Text(empresa == .utp
                        ? L.t("Puedes cambiar la foto cuando quieras. Se conserva al cerrar la app. Guardarla no verifica tu identidad universitaria.", "You can replace the photo anytime. It stays saved after closing the app. Saving it does not verify your university identity.")
                        : L.f("Puedes cambiar la foto cuando quieras. Se conserva al cerrar la app y pertenece a tu carnet de {0}. Guardarla no verifica tu identidad ni tu vínculo laboral.", "You can replace the photo anytime. It stays saved after closing the app and belongs to your {0} card. Saving it does not verify your identity or employment.", ["\(empresa.nombre)"]))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
            }
            .background(Color.appSurface)
            .navigationTitle(CarnetPerfil.foto.titulo(para: empresa))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("Listo", "Done")) { dismiss() }.disabled(guardando)
                }
            }
        }
        .task {
            guard foto == nil else { return }
            let stored = await CarnetImageStore.load(empresa: empresa)
            guard !Task.isCancelled, foto == nil else { return }
            foto = stored
        }
        .fullScreenCover(item: $picker, onDismiss: {
            selectorCerrado = true
            presentarEditor()
        }) { fuente in
            if fuente == .camara {
                ImagePicker(sourceType: .camera, allowsEditing: false, onImagePicked: prepararEdicion)
                    .ignoresSafeArea()
            } else {
                GaleriaPicker(onImagePicked: prepararEdicion).ignoresSafeArea()
            }
        }
        .fullScreenCover(item: $editor) { seleccion in
            EncuadreFotoView(image: seleccion.image) { ajustada in
                editor = nil
                guardar(ajustada)
            }
        }
        .sheet(isPresented: $verFoto) {
            NavigationStack {
                if let foto {
                    VisorFotoCarnet(imagen: foto)
                        .navigationTitle(L.t("Foto del carné", "Card photo"))
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button(L.t("Cerrar", "Close")) { verFoto = false }
                            }
                        }
                }
            }
        }
        .alert(L.t("No se pudo guardar la foto", "Couldn't save photo"), isPresented: $errorGuardado) {
            Button(L.t("Aceptar", "OK"), role: .cancel) {}
        } message: {
            Text(L.t("La foto anterior se conserva. Comprueba el espacio disponible e inténtalo de nuevo.", "Your previous photo is preserved. Check available storage and try again."))
        }
        .alert(L.t("Permiso de cámara", "Camera permission"), isPresented: $permisoDenegado) {
            Button(L.t("Abrir Ajustes", "Open Settings")) {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button(L.t("Cancelar", "Cancel"), role: .cancel) {}
        } message: {
            Text(L.t("Activa el acceso a la cámara o elige una foto de la galería.", "Enable camera access or choose a photo from your library."))
        }
    }

    private func abrirCamara() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: selectorCerrado = false; picker = .camara
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { allowed in
                DispatchQueue.main.async {
                    if allowed { selectorCerrado = false; picker = .camara } else { permisoDenegado = true }
                }
            }
        default: permisoDenegado = true
        }
    }

    private func prepararEdicion(_ image: UIImage) {
        fotoPorEditar = image
        if selectorCerrado { presentarEditor() }
    }

    private func presentarEditor() {
        guard let image = fotoPorEditar else { return }
        fotoPorEditar = nil
        editor = FotoParaEncuadrar(image: image)
    }

    private func guardar(_ image: UIImage) {
        guard !guardando else { return }
        guardando = true
        Task { @MainActor in
            // El guardado normaliza la orientación y escribe el JPEG: trabajo
            // de disco que no debe bloquear la interfaz. Antes se hacía con
            // GCD + Result, mezclado con el async/await del resto del módulo.
            let guardada = await Task.detached(priority: .userInitiated) {
                try? CarnetImageStore.save(image, empresa: empresa)
            }.value

            guardando = false
            if let guardada {
                foto = guardada
                onCapture()
                AppHaptics.success()
            } else {
                errorGuardado = true
            }
        }
    }
}

#Preview {
    CarnetScannerView(onCapture: {})
}
