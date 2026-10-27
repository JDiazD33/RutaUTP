//
//  EditorAvisosDiariosView.swift
//  RutaUTP
//
//  Editor de la franja y cantidad de los avisos diarios.
//

import SwiftUI

struct EditorAvisosDiariosView: View {
    @Environment(\.dismiss) private var dismiss
    private let servicio = NotificacionesService.shared
    @State private var config: ConfiguracionAvisosDiarios
    @State private var guardando = false
    @State private var error: String?

    init() { _config = State(initialValue: NotificacionesService.shared.avisosDiarios.configuracion) }

    var body: some View {
        NavigationStack {
            Form {
                Picker(L.t("Cantidad por día", "Daily frequency"), selection: $config.cantidad) {
                    ForEach(1...3, id: \.self) { valor in
                        Text(ConfiguracionAvisosDiarios.textoCantidad(valor)).tag(valor)
                    }
                }
                DatePicker(L.t("Desde", "From"), selection: hora(inicio: true), displayedComponents: .hourAndMinute)
                DatePicker(L.t("Hasta", "Until"), selection: hora(inicio: false), displayedComponents: .hourAndMinute)
                Text(L.t("Elige una franja dentro del mismo día. Se respetan pausas y silencios.", "Choose a window within the same day. Pauses and quiet settings apply."))
                    .font(.footnote)
                if let error { Text(L.aviso(error)).foregroundStyle(.appError) }
            }
            .estiloFormularioNotificaciones()
            .navigationTitle(L.t("Avisos del día", "Daily notifications"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L.t("Cancelar", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("Guardar", "Save")) {
                        guardando = true
                        Task {
                            if await servicio.guardarAvisosDiarios(config) { dismiss() }
                            else { error = servicio.errorMensaje }
                            guardando = false
                        }
                    }
                    .disabled(!config.esValida || guardando)
                }
            }
            .disabled(guardando)
        }
    }

    private func hora(inicio: Bool) -> Binding<Date> {
        Binding(
            get: { DiasNotificaciones.fecha(minutos: inicio ? config.inicio : config.fin) },
            set: { fecha in
                if inicio { config.inicio = DiasNotificaciones.minutos(fecha) }
                else { config.fin = DiasNotificaciones.minutos(fecha) }
            }
        )
    }
}
