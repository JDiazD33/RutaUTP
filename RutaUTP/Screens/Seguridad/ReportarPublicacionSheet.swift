//
//  ReportarPublicacionSheet.swift
//  RutaUTP
//
//  Reporte de una publicación de Comunidad: información falsa, derechos de
//  autor o de imagen, ofensas, datos personales o spam.
//
//  Las publicaciones son de demostración y no hay un servidor de moderación:
//  el reporte se conserva en `ComunidadReacciones` durante la sesión, igual
//  que los votos y los comentarios, y la interfaz lo dice expresamente.
//

import SwiftUI

// MARK: - Motivo

enum MotivoReportePublicacion: String, CaseIterable, Identifiable {
    case falsa, derechos, ofensiva, datosPersonales, spam, otro

    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .falsa: return L.t("Información falsa o engañosa", "False or misleading information")
        case .derechos: return L.t("Infringe derechos de autor o de imagen", "Infringes copyright or image rights")
        case .ofensiva: return L.t("Lenguaje ofensivo o acoso", "Offensive language or harassment")
        case .datosPersonales: return L.t("Expone datos personales", "Exposes personal information")
        case .spam: return L.t("Spam o publicidad", "Spam or advertising")
        case .otro: return L.t("Otro motivo", "Another reason")
        }
    }

    var detalle: String {
        switch self {
        case .falsa:
            return L.t("El incidente no ocurrió, ya terminó o la ubicación es incorrecta.",
                       "The incident didn't happen, is over or the location is wrong.")
        case .derechos:
            return L.t("Usa una foto o un texto ajeno sin permiso, o muestra a alguien sin su consentimiento.",
                       "Uses someone else's photo or text without permission, or shows someone without consent.")
        case .ofensiva:
            return L.t("Insulta, amenaza o discrimina a una persona o a un grupo.",
                       "Insults, threatens or discriminates against a person or group.")
        case .datosPersonales:
            return L.t("Muestra placas, teléfonos, direcciones o rostros identificables.",
                       "Shows license plates, phone numbers, addresses or identifiable faces.")
        case .spam:
            return L.t("Promociona productos o repite el mismo mensaje.",
                       "Promotes products or repeats the same message.")
        case .otro:
            return L.t("Cuéntanos qué ocurre en los detalles.", "Tell us what's wrong in the details.")
        }
    }

    var icono: String {
        switch self {
        case .falsa: return "exclamationmark.triangle"
        case .derechos: return "c.circle"
        case .ofensiva: return "hand.raised"
        case .datosPersonales: return "person.crop.circle.badge.exclamationmark"
        case .spam: return "megaphone"
        case .otro: return "ellipsis.bubble"
        }
    }
}

/// Reporte hecho por el usuario sobre una publicación.
struct ReportePublicacion: Equatable {
    let motivo: MotivoReportePublicacion
    let detalle: String
    let fecha: Date
}

// MARK: - Hoja

struct ReportarPublicacionSheet: View {
    let reporte: ReporteComunidad
    /// Recibe el reporte y si la publicación debe ocultarse en el feed.
    var enviar: (ReportePublicacion, Bool) -> Void

    static let limiteDetalle = 300

    @Environment(\.dismiss) private var dismiss
    @State private var motivo: MotivoReportePublicacion?
    @State private var detalle = ""
    @State private var ocultar = true

    private var detalleLimpio: String {
        detalle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// «Otro motivo» necesita una explicación; los demás la aceptan opcional.
    private var puedeEnviar: Bool {
        guard let motivo else { return false }
        return motivo != .otro || !detalleLimpio.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    resumenPublicacion
                }

                Section {
                    Picker(selection: $motivo) {
                        ForEach(MotivoReportePublicacion.allCases) { opcion in
                            filaMotivo(opcion).tag(Optional(opcion))
                        }
                    } label: {
                        Text(L.t("Motivo", "Reason"))
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text(L.t("¿Por qué la reportas?", "Why are you reporting it?"))
                }

                Section {
                    TextField(motivo == .otro
                              ? L.t("Explica el motivo", "Explain the reason")
                              : L.t("Añade detalles (opcional)", "Add details (optional)"),
                              text: $detalle, axis: .vertical)
                        .lineLimit(3...6)
                        .onChange(of: detalle) { _, texto in
                            if texto.count > Self.limiteDetalle {
                                detalle = String(texto.prefix(Self.limiteDetalle))
                            }
                        }
                } header: {
                    Text(L.t("Detalles", "Details"))
                } footer: {
                    Text(L.f("{0} de {1} caracteres", "{0} of {1} characters",
                             ["\(detalle.count)", "\(Self.limiteDetalle)"]))
                }

                Section {
                    Toggle(L.t("Ocultar en mi feed", "Hide from my feed"), isOn: $ocultar)
                } footer: {
                    Text(L.t("El autor no sabrá quién la reportó. En esta versión de prueba el reporte se guarda solo en este iPhone durante la sesión y no se envía a moderación.",
                             "The author won't know who reported it. In this trial version the report is kept only on this iPhone for the session and isn't sent for moderation."))
                }
            }
            .navigationTitle(L.t("Reportar publicación", "Report post"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("Cancelar", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("Enviar", "Send")) {
                        guard let motivo, puedeEnviar else { return }
                        enviar(ReportePublicacion(motivo: motivo, detalle: detalleLimpio, fecha: Date()), ocultar)
                        dismiss()
                    }
                    .disabled(!puedeEnviar)
                    .accessibilityHint(puedeEnviar ? ""
                        : L.t("Elige un motivo para poder enviar", "Choose a reason to send"))
                }
            }
        }
        .tint(Color.appAccent)
        .interactiveDismissDisabled(motivo != nil || !detalleLimpio.isEmpty)
    }

    private var resumenPublicacion: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(reporte.avatarColor).frame(width: 36, height: 36)
                Text(reporte.iniciales)
                    .font(.labelCapsSm)
                    .foregroundStyle(reporte.avatarForeground)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(reporte.nombre).font(.subheadline.weight(.semibold))
                Text(reporte.cuerpoLocalizado)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L.t("Publicación de ", "Post by ") + reporte.nombre)
        .accessibilityValue(reporte.cuerpoLocalizado)
    }

    private func filaMotivo(_ opcion: MotivoReportePublicacion) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(opcion.titulo)
                Text(opcion.detalle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: opcion.icono)
                .foregroundStyle(Color.appAccent)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Flujo compartido por la tarjeta y el detalle

/// Presenta la hoja de reporte y, al enviarlo, la confirmación. Lo comparten
/// la tarjeta del feed (menú contextual y acción de VoiceOver) y el detalle.
struct FlujoReportePublicacion: ViewModifier {
    let reporte: ReporteComunidad
    @ObservedObject var reacciones: ComunidadReacciones
    @Binding var presentado: Bool
    /// Se llama al cerrar la confirmación; recibe si la publicación quedó oculta.
    var alTerminar: (Bool) -> Void = { _ in }

    @State private var enviado: (reporte: ReportePublicacion, oculta: Bool)?
    @State private var mostrarGracias = false

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $presentado, onDismiss: {
                // La alerta se presenta después de cerrar la hoja: dos
                // presentaciones simultáneas sobre la misma vista se pisan.
                if enviado != nil { mostrarGracias = true }
            }) {
                ReportarPublicacionSheet(reporte: reporte) { nuevo, ocultar in
                    reacciones.reportar(reporte, nuevo, ocultar: ocultar)
                    enviado = (nuevo, ocultar)
                }
                .presentationDragIndicator(.visible)
            }
            .alert(L.t("Gracias por reportar", "Thanks for reporting"), isPresented: $mostrarGracias) {
                Button(L.t("Listo", "Done")) {
                    let oculta = enviado?.oculta ?? false
                    enviado = nil
                    alTerminar(oculta)
                }
            } message: {
                if enviado?.oculta == true {
                    Text(L.t("Ocultamos la publicación de tu feed. En esta versión de prueba el reporte no se envía a moderación.",
                             "We hid the post from your feed. In this trial version the report isn't sent for moderation."))
                } else {
                    Text(L.t("Marcamos la publicación como reportada. En esta versión de prueba el reporte no se envía a moderación.",
                             "We marked the post as reported. In this trial version the report isn't sent for moderation."))
                }
            }
    }
}

extension View {
    func flujoReportePublicacion(_ reporte: ReporteComunidad,
                                 reacciones: ComunidadReacciones,
                                 presentado: Binding<Bool>,
                                 alTerminar: @escaping (Bool) -> Void = { _ in }) -> some View {
        modifier(FlujoReportePublicacion(reporte: reporte, reacciones: reacciones,
                                         presentado: presentado, alTerminar: alTerminar))
    }
}
