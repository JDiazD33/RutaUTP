//
//  EditorRecordatorioView.swift
//  RutaUTP
//
//  Editor del recordatorio de viaje.
//

import SwiftUI

struct EditorRecordatorioView: View {
    @Environment(\.dismiss) private var dismiss
    private let servicio = NotificacionesService.shared
    @State private var destinoID: String
    @State private var hora: Date
    @State private var dias: Set<Int>
    @State private var guardando = false

    init() {
        let actual = NotificacionesService.shared.preferencias.configuracion.recordatorio
        let destinos = NotificacionesService.shared.destinos
        let destino = actual.map { anterior in destinos.contains(where: { $0.id == anterior.destinoID }) ? anterior.destinoID : "" }
        _destinoID = State(initialValue: destino ?? destinos.first?.id ?? "")
        _hora = State(initialValue: DiasNotificaciones.fecha(minutos: actual?.minutoDelDia ?? 8 * 60))
        _dias = State(initialValue: actual?.dias ?? Set(2...6))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if servicio.destinos.isEmpty {
                        Text(L.t("Guarda un lugar con ubicación o elige tu sede en Ajustes.", "Save a place with a location or choose your workplace in Settings."))
                    } else {
                        Picker(L.t("Destino", "Destination"), selection: $destinoID) {
                            Text(L.t("Elige un destino", "Choose a destination")).tag("")
                            ForEach(servicio.destinos) { destino in Text(destino.nombre).tag(destino.id) }
                        }
                    }
                    DatePicker(L.t("Hora de salida", "Departure time"), selection: $hora, displayedComponents: .hourAndMinute)
                }
                Section(L.t("Días de salida", "Departure days")) {
                    SeleccionDiasNotificaciones(seleccionados: dias) { dia in
                        if dias.contains(dia) { dias.remove(dia) } else { dias.insert(dia) }
                    }
                }
                if !servicio.preferencias.activadas {
                    Section {
                        Text(L.t("Se guardará sin avisos mientras las notificaciones estén desactivadas.", "It will be saved without alerts while notifications are off."))
                    }
                }
                if let error = servicio.errorMensaje { Section { Text(L.aviso(error)).foregroundStyle(.appError) } }
            }
            .estiloFormularioNotificaciones()
            .navigationTitle(L.t("Recordatorio de viaje", "Trip reminder"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L.t("Cancelar", "Cancel")) { dismiss() }.disabled(guardando) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("Guardar", "Save")) {
                        guardando = true
                        Task {
                            let recordatorio = RecordatorioViaje(id: UUID(), minutoDelDia: DiasNotificaciones.minutos(hora), dias: dias, destinoID: destinoID)
                            if await servicio.guardarRecordatorio(recordatorio) { dismiss() }
                            guardando = false
                        }
                    }
                    .disabled(guardando || dias.isEmpty || !servicio.destinos.contains(where: { $0.id == destinoID }) || servicio.preferencias.datosInvalidos)
                }
            }
            .interactiveDismissDisabled(guardando)
        }
        .tintePreferencias()
    }
}
