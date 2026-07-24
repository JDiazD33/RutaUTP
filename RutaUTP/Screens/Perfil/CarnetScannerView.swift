//
//  CarnetScannerView.swift
//  RutaUTP
//
//  CORREGIDO V3: Vista de escaneo de carnet universitario con camara real.
//  - AVCaptureSession + AVCaptureVideoPreviewLayer
//  - Overlay oscuro con cutout tipo escaner DNI
//  - Esquinas de escaneo color appPrimary
//  - Boton capturar estilo camara iOS
//  - Manejo de permisos con fallback a Ajustes
//  - Checkmark animado al capturar
//

import SwiftUI
import AVFoundation
import UIKit

// MARK: - Camera Preview (UIKit bridge)
struct CameraPreviewRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> CameraPreviewController {
        CameraPreviewController()
    }
    func updateUIViewController(_ uiViewController: CameraPreviewController, context: Context) {}
}

class CameraPreviewController: UIViewController {
    let session = AVCaptureSession()
    var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.stopRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func setupCamera() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return
        }
        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input) }
        if session.canSetSessionPreset(.high) { session.sessionPreset = .high }
        session.commitConfiguration()

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer
    }
}

// MARK: - Overlay con cutout (even-odd fill)
struct ScannerCutout: Shape {
    let cutout: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addRect(cutout)
        return path
    }
}

// MARK: - Vista principal
struct CarnetScannerView: View {
    @Environment(\.dismiss) private var dismiss
    var onCapture: () -> Void

    @State private var permission: CameraPermission = .notDetermined
    @State private var didCapture: Bool = false
    @State private var showCheckmark: Bool = false

    enum CameraPermission {
        case authorized, denied, notDetermined
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch permission {
            case .authorized:
                scannerContent
            case .denied:
                permissionDeniedView
            case .notDetermined:
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.5)
            }
        }
        .onAppear { checkPermission() }
    }

    // MARK: - Scanner content
    private var scannerContent: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let scanW = min(w * 0.86, 360)
            let scanH = scanW * 0.63 // Proporción óptima para carnet universitario
            let scanRect = CGRect(
                x: (w - scanW) / 2,
                y: (h - scanH) / 2 - 20,
                width: scanW,
                height: scanH
            )

            ZStack {
                // Camara preview
                CameraPreviewRepresentable()
                    .ignoresSafeArea()

                // Overlay oscuro con cutout perfectamente alineado
                ScannerCutout(cutout: scanRect)
                    .fill(Color.black.opacity(0.65), style: FillStyle(eoFill: true))
                    .ignoresSafeArea()

                // Borde del rectangulo encuadrado
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.9), lineWidth: 2)
                    .frame(width: scanW, height: scanH)
                    .position(x: w / 2, y: scanRect.midY)

                // Esquinas tipo escaner alineadas pixel-perfect
                cornerMarkers(scanRect: scanRect)

                // Texto encima del rectangulo
                VStack(spacing: 4) {
                    Text("Encuadra tu carnet UTP aquí")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Alinea los bordes dentro del recuadro")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .position(x: w / 2, y: max(scanRect.minY - 36, 100))

                // Texto debajo del rectangulo
                Text("Asegúrate de que el texto y foto sean legibles")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .position(x: w / 2, y: scanRect.maxY + 32)

                // Checkmark animado
                if showCheckmark {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.4))
                            .frame(width: 96, height: 96)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(Color.appPrimary)
                    }
                    .position(x: w / 2, y: scanRect.midY)
                    .transition(.scale.combined(with: .opacity))
                }

                // UI Overlay (Top Bar + Bottom Button)
                VStack {
                    // Top bar con Cancelar
                    HStack {
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .bold))
                                Text("Cancelar")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(.ultraThinMaterial))
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 20)
                    }
                    .padding(.top, 54)

                    Spacer()

                    // Boton capturar estilo camara
                    Button {
                        handleCapture()
                    } label: {
                        ZStack {
                            Circle()
                                .stroke(Color.white, lineWidth: 4)
                                .frame(width: 76, height: 76)
                            Circle()
                                .fill(Color.white)
                                .frame(width: 64, height: 64)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 48)
                    .disabled(didCapture)
                }
            }
        }
    }

    // MARK: - Permission denied
    private var permissionDeniedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 60))
                .foregroundStyle(.white.opacity(0.5))
            Text("Acceso a la camara denegado")
                .font(.headlineSm)
                .foregroundStyle(.white)
            Text("Necesitamos acceso a la camara para escanear tu carnet universitario.")
                .font(.bodySm)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Abrir Ajustes")
                    .font(.headlineSm)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color.appPrimary))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Corner markers
    private func cornerMarkers(scanRect: CGRect) -> some View {
        let length: CGFloat = 24
        let thickness: CGFloat = 4
        let color = Color.appPrimary

        return ZStack {
            // Top-left
            cornerShape(corner: .topLeft, length: length, thickness: thickness)
                .fill(color)
                .frame(width: length, height: length)
                .position(x: scanRect.minX + length / 2, y: scanRect.minY + length / 2)
            // Top-right
            cornerShape(corner: .topRight, length: length, thickness: thickness)
                .fill(color)
                .frame(width: length, height: length)
                .position(x: scanRect.maxX - length / 2, y: scanRect.minY + length / 2)
            // Bottom-left
            cornerShape(corner: .bottomLeft, length: length, thickness: thickness)
                .fill(color)
                .frame(width: length, height: length)
                .position(x: scanRect.minX + length / 2, y: scanRect.maxY - length / 2)
            // Bottom-right
            cornerShape(corner: .bottomRight, length: length, thickness: thickness)
                .fill(color)
                .frame(width: length, height: length)
                .position(x: scanRect.maxX - length / 2, y: scanRect.maxY - length / 2)
        }
    }

    private enum Corner { case topLeft, topRight, bottomLeft, bottomRight }

    private func cornerShape(corner: Corner, length: CGFloat, thickness: CGFloat) -> some Shape {
        CornerShape(corner: corner, length: length, thickness: thickness)
    }

    private struct CornerShape: Shape {
        let corner: Corner
        let length: CGFloat
        let thickness: CGFloat

        func path(in rect: CGRect) -> Path {
            var path = Path()
            switch corner {
            case .topLeft:
                path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + thickness / 2))
                path.addLine(to: CGPoint(x: rect.minX + thickness / 2, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))
            case .topRight:
                path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX - thickness / 2, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + thickness / 2))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))
            case .bottomLeft:
                path.move(to: CGPoint(x: rect.minX, y: rect.maxY - length))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - thickness / 2))
                path.addLine(to: CGPoint(x: rect.minX + thickness / 2, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX + length, y: rect.maxY))
            case .bottomRight:
                path.move(to: CGPoint(x: rect.maxX - length, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.maxX - thickness / 2, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - thickness / 2))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
            }
            return path
        }
    }

    // MARK: - Permission check
    private func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permission = .authorized
        case .denied, .restricted:
            permission = .denied
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    permission = granted ? .authorized : .denied
                }
            }
        @unknown default:
            permission = .denied
        }
    }

    // MARK: - Capture
    private func handleCapture() {
        guard !didCapture else { return }
        didCapture = true
        withAnimation(.spring(response: 0.4)) {
            showCheckmark = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            onCapture()
            dismiss()
        }
    }
}

#Preview {
    CarnetScannerView(onCapture: {})
}

