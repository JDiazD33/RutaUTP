import SwiftUI
import UIKit
import UserNotifications

struct NotificacionesView: View {
    @Environment(\.dismiss) private var dismiss
    private let servicio = NotificacionesService.shared
    private let push = PushRutasService.shared
    @State private var editarRecordatorio = false
    @State private var pausaPersonalizada = false
    @State private var fechaPausa = Date().addingTimeInterval(3600)
    @State private var confirmarEliminar = false
    @State private var editarDiarios = false

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { contexto in
                contenido(ahora: contexto.date)
            }
            .navigationTitle(L.t("Notificaciones", "Notifications"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("Cerrar", "Close")) { dismiss() }
                }
            }
            .task { await servicio.refrescar() }
            .sheet(isPresented: $editarRecordatorio) {
                EditorRecordatorioView()
                    .seguirTemaForzado()
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $pausaPersonalizada) { editorPausa }
            .sheet(isPresented: $editarDiarios) {
                EditorAvisosDiariosView().seguirTemaForzado().presentationDetents([.large])
            }
            .confirmationDialog(L.t("Eliminar recordatorio", "Delete reminder"), isPresented: $confirmarEliminar, titleVisibility: .visible) {
                Button(L.t("Eliminar", "Delete"), role: .destructive) {
                    Task { await servicio.cambiar { $0.recordatorio = nil } }
                }
                Button(L.t("Cancelar", "Cancel"), role: .cancel) {}
            }
        }
        .tint(.appPrimary)
    }

    private func contenido(ahora: Date) -> some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(servicio.resumen(ahora: ahora))
                            .font(.title3.bold())
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text(L.t("Organiza tus salidas y elige cuándo recibir avisos.", "Plan your departures and choose when to receive notifications."))
                            .font(.subheadline)
                    }
                }
                .padding(.vertical, 12)
                .foregroundStyle(.onPrimaryFill)
                .listRowBackground(Color.primaryFill)
            }

            Section {
                Toggle(L.t("Recibir notificaciones", "Receive notifications"), isOn: Binding(
                    get: { servicio.preferencias.activadas },
                    set: { valor in Task { await servicio.activar(valor) } }
                ))
                .disabled(servicio.solicitandoPermiso)
                if servicio.autorizacion == .notDetermined {
                    Button(L.t("Permitir notificaciones", "Allow notifications")) {
                        Task { await servicio.activar(true) }
                    }
                    .disabled(servicio.solicitandoPermiso)
                } else if servicio.autorizacion == .denied {
                    Text(L.t("iOS bloquea los avisos. Puedes permitirlos en los ajustes del sistema.", "iOS blocks notifications. You can allow them in system settings."))
                        .font(.subheadline)
                    Button(L.t("Abrir ajustes de iOS", "Open iOS settings")) { abrirAjustes() }
                } else if servicio.permitido && !servicio.bannersPermitidos {
                    Text(L.t("Los banners están apagados en iOS. Revisa los ajustes si quieres verlos en pantalla.", "Banners are turned off in iOS. Check settings if you want to see them on screen."))
                        .font(.subheadline)
                    Button(L.t("Abrir ajustes de iOS", "Open iOS settings")) { abrirAjustes() }
                }
                if servicio.programando || servicio.solicitandoPermiso {
                    HStack {
                        ProgressView()
                        Text(L.t("Actualizando avisos…", "Updating notifications…"))
                            .font(.subheadline)
                    }
                }
            } header: { Text(L.t("Permiso y estado", "Permission and status")) }

            if let error = servicio.errorMensaje {
                Section {
                    Text(L.aviso(error)).foregroundStyle(.appError)
                    Button(L.t("Reintentar", "Try again")) { Task { await servicio.refrescar() } }
                }
            }

            Section {
                if let recordatorio = servicio.preferencias.configuracion.recordatorio {
                    Label(servicio.destinoActual?.nombre ?? L.t("Destino no disponible", "Destination unavailable"), systemImage: "mappin.circle.fill")
                        .font(.headline)
                    LabeledContent(L.t("Hora de salida", "Departure time")) {
                        Text(DiasNotificaciones.fecha(minutos: recordatorio.minutoDelDia), style: .time)
                    }
                    Text(DiasNotificaciones.resumen(recordatorio.dias))
                        .font(.subheadline)
                    if servicio.destinoActual == nil {
                        Text(L.t("El lugar se eliminó o tu sede cambió. Edita el destino para volver a recibir este recordatorio.", "The place was deleted or your workplace changed. Edit the destination to receive this reminder again."))
                            .font(.subheadline)
                            .foregroundStyle(.appError)
                    }
                    Button(L.t("Editar recordatorio", "Edit reminder")) { editarRecordatorio = true }
                    Button(L.t("Eliminar recordatorio", "Delete reminder"), role: .destructive) { confirmarEliminar = true }
                } else {
                    Text(L.t("Elige un destino, una hora y los días en que quieres recordar tu salida.", "Choose a destination, a time and the days you want a departure reminder."))
                        .font(.subheadline)
                    Button { editarRecordatorio = true } label: {
                        Label(L.t("Crear recordatorio", "Create reminder"), systemImage: "plus.circle.fill")
                    }
                }
                if let primera = servicio.fechasProgramadas.first(where: { $0 > ahora }),
                   let ultima = servicio.fechasProgramadas.last {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L.t("Próximo aviso", "Next notification")).font(.caption)
                        Text(servicio.fechaTexto(primera)).font(.subheadline.bold())
                        Text(L.f("Agenda cubierta hasta {0}", "Schedule covered until {0}", [servicio.fechaTexto(ultima)]))
                            .font(.footnote)
                    }
                } else if servicio.preferencias.activadas && servicio.permitido && servicio.destinoActual != nil && !servicio.programando {
                    Text(L.t("No hay fechas programadas. Revisa los días y horarios de silencio.", "There are no scheduled dates. Check quiet days and hours."))
                        .font(.footnote)
                }
            } header: { Text(L.t("Recordatorio de viaje", "Trip reminder")) }
              footer: { Text(L.t("Los avisos quedan programados hasta la fecha indicada. Abre la app para renovar la agenda.", "Notifications are scheduled until the date shown. Open the app to renew the schedule.")) }

            seccionAvisosDiarios(ahora: ahora)
            seccionCambiosRuta

            Section {
                Menu {
                    Button(L.t("Pausar 1 hora", "Pause for 1 hour")) { pausarHoras(1) }
                    ForEach([8, 24], id: \.self) { horas in
                        Button(L.f("Pausar {0} horas", "Pause for {0} hours", [String(horas)])) { pausarHoras(horas) }
                    }
                    ForEach([3, 7], id: \.self) { dias in
                        Button(L.f("Pausar {0} días", "Pause for {0} days", [String(dias)])) {
                            if let fin = ProgramadorRecordatorios.calendario.date(byAdding: .day, value: dias, to: Date()) { pausar(hasta: fin) }
                        }
                    }
                    Button(L.t("Elegir fecha y hora", "Choose date and time")) {
                        fechaPausa = max(Date().addingTimeInterval(3600), servicio.preferencias.configuracion.pausaHasta ?? Date())
                        pausaPersonalizada = true
                    }
                    Button(L.t("Hasta que vuelva a activarlas", "Until I turn them on again")) {
                        Task { await servicio.activar(false) }
                    }
                } label: {
                    Label(L.t("Pausar avisos", "Pause notifications"), systemImage: "moon.zzz.fill")
                        .frame(minHeight: 44)
                }
                .disabled(!servicio.preferencias.activadas || servicio.preferencias.datosInvalidos)
                if servicio.preferencias.activadas, let fin = servicio.preferencias.configuracion.pausaHasta, fin > ahora {
                    Text(L.f("Se reanudan después de {0}", "They resume after {0}", [servicio.fechaTexto(fin)]))
                        .font(.subheadline)
                    Button(L.t("Reactivar ahora", "Resume now")) { Task { await servicio.reactivar() } }
                } else if !servicio.preferencias.activadas {
                    Button(L.t("Reactivar notificaciones", "Turn notifications back on")) { Task { await servicio.reactivar() } }
                }
            } header: { Text(L.t("Pausas", "Pauses")) }
              footer: { Text(L.t("Los avisos omitidos durante una pausa no se acumulan al reactivar.", "Notifications skipped during a pause are not sent when you resume.")) }

            Section {
                SeleccionDiasNotificaciones(seleccionados: servicio.preferencias.configuracion.diasSilencio) { dia in
                    Task {
                        await servicio.cambiar {
                            if $0.diasSilencio.contains(dia) { $0.diasSilencio.remove(dia) }
                            else { $0.diasSilencio.insert(dia) }
                        }
                    }
                }
                .disabled(servicio.preferencias.datosInvalidos)
            } header: { Text(L.t("Días sin avisos", "Days without notifications")) }
              footer: { Text(L.t("Los días marcados quedan silenciados cada semana.", "Selected days are muted every week.")) }

            Section {
                Toggle(L.t("Silenciar por horario", "Mute during quiet hours"), isOn: Binding(
                    get: { servicio.preferencias.configuracion.silencioHorario },
                    set: { valor in Task { await servicio.cambiar { $0.silencioHorario = valor } } }
                ))
                if servicio.preferencias.configuracion.silencioHorario {
                    DatePicker(L.t("Desde", "From"), selection: horaSilencio(inicio: true), displayedComponents: .hourAndMinute)
                    DatePicker(L.t("Hasta", "Until"), selection: horaSilencio(inicio: false), displayedComponents: .hourAndMinute)
                    if servicio.preferencias.configuracion.inicioSilencio == servicio.preferencias.configuracion.finSilencio {
                        Text(L.t("Con la misma hora de inicio y fin, el silencio dura todo el día.", "When start and end times match, quiet hours last all day."))
                            .font(.footnote)
                    }
                }
            } header: { Text(L.t("Horario de silencio", "Quiet hours")) }
              footer: { Text(L.t("Puedes silenciar la noche, aunque el horario cruce la medianoche.", "You can mute the night, even when quiet hours cross midnight.")) }
              .disabled(servicio.preferencias.datosInvalidos)

            Section {
                Toggle(L.t("Sonido de los avisos", "Notification sound"), isOn: Binding(
                    get: { servicio.preferencias.configuracion.sonido },
                    set: { valor in Task { await servicio.cambiar { $0.sonido = valor } } }
                ))
                .disabled(servicio.preferencias.datosInvalidos)
                if servicio.permitido && !servicio.sonidoPermitido {
                    Text(L.t("El sonido está apagado en iOS. Puedes cambiarlo en los ajustes del sistema.", "Sound is turned off in iOS. You can change it in system settings."))
                        .font(.footnote)
                    Button(L.t("Abrir ajustes de iOS", "Open iOS settings")) { abrirAjustes() }
                }
                Button { Task { await servicio.probar() } } label: {
                    Label(L.t("Enviar aviso local de prueba", "Send a local test notification"), systemImage: "bell.and.waves.left.and.right.fill")
                        .frame(minHeight: 44)
                }
                .disabled(!servicio.permiteAviso(ahora.addingTimeInterval(5)) || servicio.programando)
                if let mensaje = servicio.mensajePrueba {
                    Text(L.aviso(mensaje)).font(.footnote)
                }
            } footer: {
                Text(L.t("iOS puede silenciar o retrasar los avisos con Concentración o el Resumen programado.", "iOS may silence or delay notifications with Focus or Scheduled Summary."))
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.appSurface)
        .foregroundStyle(.onSurface)
    }

    private func seccionAvisosDiarios(ahora: Date) -> some View {
        Section {
            Toggle(L.t("Avisos diarios aleatorios", "Random daily notifications"), isOn: Binding(
                get: { servicio.avisosDiarios.configuracion.activa },
                set: { valor in Task { await servicio.activarAvisosDiarios(valor) } }
            ))
            .disabled(servicio.avisosDiarios.datosInvalidos || servicio.avisosDiarios.registroInvalido || servicio.preferencias.datosInvalidos || servicio.solicitandoPermiso)
            if servicio.avisosDiarios.configuracion.activa {
                Text(ConfiguracionAvisosDiarios.textoCantidad(servicio.avisosDiarios.configuracion.cantidad))
                    .font(.subheadline)
                HStack {
                    Text(L.t("Franja de envío", "Delivery window"))
                    Spacer()
                    Text(DiasNotificaciones.fecha(minutos: servicio.avisosDiarios.configuracion.inicio), style: .time)
                    Text("–")
                    Text(DiasNotificaciones.fecha(minutos: servicio.avisosDiarios.configuracion.fin), style: .time)
                }
                .font(.subheadline)
                Button(L.t("Elegir horario y cantidad", "Choose time and frequency")) { editarDiarios = true }
                    .disabled(servicio.avisosDiarios.datosInvalidos || servicio.avisosDiarios.registroInvalido)
                if let siguiente = servicio.fechasDiarias.first(where: { $0 > ahora }), let ultimo = servicio.fechasDiarias.last {
                    Text(L.f("Próximo aviso diario: {0}", "Next daily notification: {0}", [servicio.fechaTexto(siguiente)]))
                        .font(.subheadline)
                    Text(L.f("Último aviso programado: {0}. Abre la app para renovar la agenda.", "Last scheduled notification: {0}. Open the app to renew the schedule.", [servicio.fechaTexto(ultimo)]))
                        .font(.footnote)
                } else if !servicio.preferencias.activadas {
                    Text(L.t("Activa las notificaciones para recibir los avisos diarios.", "Turn on notifications to receive daily notifications."))
                        .font(.footnote)
                } else if servicio.permitido && !servicio.programando {
                    Text(L.t("No hay avisos diarios programados. Revisa la franja y tus reglas de silencio.", "There are no daily notifications scheduled. Check the delivery window and your quiet settings."))
                        .font(.footnote)
                }
            }
        } header: { Text(L.t("Avisos del día", "Daily notifications")) }
          footer: { Text(L.t("La hora se elige al azar dentro de tu franja. Son recordatorios generales: los avisos de obstrucciones o descuentos concretos necesitan datos confirmados.", "The time is chosen randomly within your window. These are general reminders: notifications about specific obstructions or discounts require confirmed data.")) }
    }

    private var seccionCambiosRuta: some View {
        Section {
            Toggle(L.t("Cambios en mis líneas guardadas", "Changes on my saved lines"), isOn: Binding(
                get: { push.activadas },
                set: { valor in Task { await push.cambiar(valor) } }
            ))
            .disabled(!push.disponibleEnVersion || push.datosInvalidos || servicio.preferencias.datosInvalidos)
            Text(push.textoEstado).font(.subheadline)
            if push.lineas.isEmpty {
                Text(L.t("Guarda una línea para recibir sus cambios de ruta.", "Save a line to receive its route changes."))
                    .font(.footnote)
            } else {
                Text(L.f("Líneas guardadas: {0}", "Saved lines: {0}", [String(push.lineas.count)]))
                    .font(.footnote)
            }
            if push.disponibleEnVersion {
                Button(L.t("Sincronizar ahora", "Sync now")) { push.sincronizar(forzar: true) }
                if let hasta = push.fechaCobertura {
                    Text(L.f("Registro válido hasta {0}. Abre la app para renovarlo.", "Registration valid until {0}. Open the app to renew it.", [servicio.fechaTexto(hasta)]))
                        .font(.footnote)
                }
            }
            if push.pendienteSincronizar {
                Text(L.t("La pausa o el cambio aún no llegó al servidor. Los avisos remotos pueden seguir usando tus ajustes anteriores hasta sincronizar.", "The pause or change has not reached the server yet. Remote notifications may use your previous settings until you sync."))
                    .font(.footnote).foregroundStyle(.appError)
            }
        } header: { Text(L.t("Cambios de ruta", "Route changes")) }
          footer: { Text(L.t("Avisos de la comunidad cuando al menos dos cuentas reportan el mismo cambio. Las pausas, días y horarios también se aplican al envío remoto una vez sincronizados.", "Community notifications when at least two accounts report the same change. Pauses, days and quiet hours also apply to remote delivery once synced.")) }
    }

    private func pausarHoras(_ horas: Int) { pausar(hasta: Date().addingTimeInterval(Double(horas) * 3600)) }
    private func pausar(hasta fecha: Date) { Task { await servicio.cambiar { $0.pausaHasta = fecha } } }
    private func abrirAjustes() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
    private func horaSilencio(inicio: Bool) -> Binding<Date> {
        Binding(
            get: { DiasNotificaciones.fecha(minutos: inicio ? servicio.preferencias.configuracion.inicioSilencio : servicio.preferencias.configuracion.finSilencio) },
            set: { fecha in
                let minutos = DiasNotificaciones.minutos(fecha)
                Task { await servicio.cambiar { if inicio { $0.inicioSilencio = minutos } else { $0.finSilencio = minutos } } }
            }
        )
    }
    private var editorPausa: some View {
        NavigationStack {
            Form {
                DatePicker(L.t("Pausar hasta", "Pause until"), selection: $fechaPausa,
                           in: Date()...Date().addingTimeInterval(365 * 86400), displayedComponents: [.date, .hourAndMinute])
                Button(L.t("Confirmar pausa", "Confirm pause")) {
                    Task {
                        if await servicio.cambiar({ $0.pausaHasta = fechaPausa }) { pausaPersonalizada = false }
                    }
                }
                if let error = servicio.errorMensaje { Text(L.aviso(error)).foregroundStyle(.appError) }
            }
            .navigationTitle(L.t("Pausar avisos", "Pause notifications"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L.t("Cancelar", "Cancel")) { pausaPersonalizada = false } } }
        }
        .seguirTemaForzado()
        .presentationDetents([.medium, .large])
    }
}

private struct EditorAvisosDiariosView: View {
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
                Text(L.t("La franja debe terminar después de la hora inicial, dentro del mismo día. Los silencios y pausas también se respetan.", "The window must end after its start time, within the same day. Quiet settings and pauses are also respected."))
                    .font(.footnote)
                if let error { Text(L.aviso(error)).foregroundStyle(.appError) }
            }
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

private struct EditorRecordatorioView: View {
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
                        Text(L.t("Tus notificaciones están desactivadas. El recordatorio se guardará sin avisarte.", "Your notifications are disabled. The reminder will be saved without notifying you."))
                    }
                }
                if let error = servicio.errorMensaje { Section { Text(L.aviso(error)).foregroundStyle(.appError) } }
            }
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
        .tint(.appPrimary)
    }
}

private struct SeleccionDiasNotificaciones: View {
    let seleccionados: Set<Int>
    let onToggle: (Int) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 8) {
            ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { dia in
                let seleccionado = seleccionados.contains(dia)
                Button { onToggle(dia) } label: {
                    Text(DiasNotificaciones.nombre(dia, corto: true))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(seleccionado ? Color.onPrimaryFill : Color.onSurface)
                        .background(seleccionado ? Color.primaryFill : Color.surfaceContainerHigh, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(DiasNotificaciones.nombre(dia, corto: false))
                .accessibilityAddTraits(seleccionado ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

private enum DiasNotificaciones {
    static func fecha(minutos: Int) -> Date {
        let calendar = ProgramadorRecordatorios.calendario
        return calendar.date(bySettingHour: minutos / 60, minute: minutos % 60, second: 0, of: Date()) ?? Date()
    }
    static func minutos(_ fecha: Date) -> Int {
        let calendar = ProgramadorRecordatorios.calendario
        return calendar.component(.hour, from: fecha) * 60 + calendar.component(.minute, from: fecha)
    }
    static func nombre(_ dia: Int, corto: Bool) -> String {
        let formatter = FormatoFecha.formateador(patron: "EEEE", locale: IdiomaManager.shared.idioma.locale)
        let nombres = corto ? formatter.shortStandaloneWeekdaySymbols ?? [] : formatter.standaloneWeekdaySymbols ?? []
        guard nombres.indices.contains(dia - 1) else { return "" }
        return nombres[dia - 1]
    }
    static func resumen(_ dias: Set<Int>) -> String {
        [2, 3, 4, 5, 6, 7, 1].filter(dias.contains).map { nombre($0, corto: true) }.joined(separator: ", ")
    }
}
