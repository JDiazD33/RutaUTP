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
            let scanW = w * 0.85
            let scanH = scanW * 0.54 // Proporcion CR80
            let scanRect = CGRect(
                x: (w - scanW) / 2,
                y: (h - scanH) / 2 - 40,
                width: scanW,
                height: scanH
            )

            ZStack {
                // Camara preview
                CameraPreviewRepresentable()
                    .ignoresSafeArea()

                // Overlay oscuro con cutout
                ScannerCutout(cutout: scanRect)
                    .fill(Color.black.opacity(0.65), style: FillStyle(eoFill: true))
                    .ignoresSafeArea()

                // Borde del rectangulo
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: scanW, height: scanH)
                    .position(x: w / 2, y: scanRect.midY)

                // Esquinas tipo escaner
                cornerMarkers(scanRect: scanRect)

                // Checkmark animado
                if showCheckmark {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.tertiary)
                        .background(Circle().fill(.white).frame(width: 90, height: 90))
                        .position(x: w / 2, y: scanRect.midY)
                        .transition(.scale.combined(with: .opacity))
                }

                // UI overlay
                VStack {
                    // Top bar
                    HStack {
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Text("Cancelar")
                                .font(.bodyMdMedium)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(.ultraThinMaterial))
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 20)
                    }
                    .padding(.top, 16)

                    Spacer().frame(height: scanRect.minY - 20)

                    // Texto encima del rectangulo
                    Text("Encuadra tu carnet aqui")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.bottom, 12)

                    Spacer().frame(height: scanH + 20)

                    // Texto debajo
                    Text("Asegurate que el texto sea legible")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.top, 12)

                    Spacer()

                    // Boton capturar
                    Button {
                        handleCapture()
                    } label: {
                        ZStack {
                            Circle()
                                .stroke(Color.white, lineWidth: 4)
                                .frame(width: 72, height: 72)
                            Circle()
                                .fill(Color.white)
                                .frame(width: 60, height: 60)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 40)
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
        let length: CGFloat = 20
        let thickness: CGFloat = 3
        let color = Color.appPrimary

        return ZStack {
            // Top-left
            cornerShape(corner: .topLeft, length: length, thickness: thickness)
                .fill(color)
                .frame(width: length, height: length)
                .position(x: scanRect.minX, y: scanRect.minY)
            // Top-right
            cornerShape(corner: .topRight, length: length, thickness: thickness)
                .fill(color)
                .frame(width: length, height: length)
                .position(x: scanRect.maxX, y: scanRect.minY)
            // Bottom-left
            cornerShape(corner: .bottomLeft, length: length, thickness: thickness)
                .fill(color)
                .frame(width: length, height: length)
                .position(x: scanRect.minX, y: scanRect.maxY)
            // Bottom-right
            cornerShape(corner: .bottomRight, length: length, thickness: thickness)
                .fill(color)
                .frame(width: length, height: length)
                .position(x: scanRect.maxX, y: scanRect.maxY)
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

