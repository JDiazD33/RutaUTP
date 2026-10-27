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
        .tintePreferencias()
    }

    private func contenido(ahora: Date) -> some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { servicio.preferencias.activadas },
                    set: { valor in Task { await servicio.activar(valor) } }
                )) {
                    FilaNotificaciones(titulo: L.t("Recibir notificaciones", "Receive notifications"),
                                       simbolo: "bell.fill", detalle: servicio.resumen(ahora: ahora))
                }
                .disabled(servicio.solicitandoPermiso)
                controlesPermiso
                if servicio.programando || servicio.solicitandoPermiso {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(L.t("Actualizando avisos…", "Updating notifications…"))
                            .font(.subheadline).foregroundStyle(EstiloPreferencias.textoSecundario)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            if let error = servicio.errorMensaje {
                Section {
                    Label(L.aviso(error), systemImage: "exclamationmark.circle")
                        .foregroundStyle(.appError)
                    Button(L.t("Reintentar", "Try again")) { Task { await servicio.refrescar() } }
                }
            }

            Section {
                NavigationLink { detalleRecordatorio } label: {
                    FilaNotificaciones(titulo: L.t("Recordatorio de viaje", "Trip reminder"),
                                       simbolo: "clock.fill", detalle: resumenRecordatorio)
                }
                NavigationLink { detalleDiarios } label: {
                    FilaNotificaciones(titulo: L.t("Avisos del día", "Daily notifications"),
                                       simbolo: "sun.max.fill", detalle: resumenDiarios)
                }
                NavigationLink { detalleCambiosRuta } label: {
                    FilaNotificaciones(titulo: L.t("Cambios de ruta", "Route changes"),
                                       simbolo: "arrow.triangle.branch", detalle: resumenPush)
                }
                if push.pendienteSincronizar {
                    Label(L.t("Cambios sin sincronizar. El servidor aún usa tus ajustes anteriores.", "Changes haven't synced. The server still uses your previous settings."),
                          systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                        .font(.footnote).foregroundStyle(.appError)
                }
            } header: { Text(L.t("Tus avisos", "Your notifications")) }

            Section {
                menuPausa(ahora: ahora)
                if servicio.preferencias.activadas,
                   let fin = servicio.preferencias.configuracion.pausaHasta, fin > ahora {
                    Button(L.t("Reactivar ahora", "Resume now")) { Task { await servicio.reactivar() } }
                } else if !servicio.preferencias.activadas {
                    Button(L.t("Reactivar notificaciones", "Turn notifications back on")) { Task { await servicio.reactivar() } }
                }
                NavigationLink { detalleSilencios } label: {
                    FilaNotificaciones(titulo: L.t("Días y horas de silencio", "Quiet days and hours"),
                                       simbolo: "moon.fill", detalle: resumenSilencios)
                }
                Toggle(isOn: Binding(
                    get: { servicio.preferencias.configuracion.sonido },
                    set: { valor in Task { await servicio.cambiar { $0.sonido = valor } } }
                )) {
                    FilaNotificaciones(titulo: L.t("Sonido", "Sound"), simbolo: "speaker.wave.2.fill")
                }
                .disabled(servicio.preferencias.datosInvalidos)
                if servicio.permitido && !servicio.sonidoPermitido {
                    Button { abrirAjustes() } label: {
                        Label(L.t("Sonido desactivado en iOS", "Sound is off in iOS"), systemImage: "speaker.slash")
                            .font(.subheadline)
                    }
                }
            } header: { Text(L.t("Preferencias", "Preferences")) }

            Section {
                Button { Task { await servicio.probar() } } label: {
                    FilaNotificaciones(titulo: L.t("Probar notificación", "Test notification"),
                                       simbolo: "bell.and.waves.left.and.right.fill",
                                       detalle: L.t("Aviso local en 5 segundos", "Local notification in 5 seconds"))
                }
                .disabled(!servicio.permiteAviso(ahora.addingTimeInterval(5)) || servicio.programando)
                if let mensaje = servicio.mensajePrueba {
                    Text(L.aviso(mensaje)).font(.footnote).foregroundStyle(EstiloPreferencias.textoSecundario)
                }
                NavigationLink { informacion } label: {
                    Label(L.t("Cómo funcionan los avisos", "How notifications work"), systemImage: "info.circle")
                        .font(.subheadline)
                        .frame(minHeight: 44)
                }
            }
        }
        .estiloFormularioNotificaciones()
    }

    @ViewBuilder private var controlesPermiso: some View {
        if servicio.autorizacion == .notDetermined {
            Button(L.t("Permitir notificaciones", "Allow notifications")) {
                Task { await servicio.activar(true) }
            }
            .disabled(servicio.solicitandoPermiso)
        } else if servicio.autorizacion == .denied {
            Button { abrirAjustes() } label: {
                Label(L.t("Permitir en Ajustes de iOS", "Allow in iOS Settings"), systemImage: "arrow.up.forward.app")
            }
        } else if servicio.permitido && !servicio.bannersPermitidos {
            Button { abrirAjustes() } label: {
                Label(L.t("Banners desactivados en iOS", "Banners are off in iOS"), systemImage: "rectangle.topthird.inset.filled")
                    .font(.subheadline)
            }
        }
    }

    // Cada categoría conserva sus controles y agenda; el inicio muestra solo un resumen.
    private var detalleRecordatorio: some View {
        TimelineView(.periodic(from: .now, by: 60)) { contexto in
            Form {
                Section {
                    if let recordatorio = servicio.preferencias.configuracion.recordatorio {
                        LabeledContent(L.t("Destino", "Destination"),
                                       value: servicio.destinoActual?.nombre ?? L.t("Destino no disponible", "Destination unavailable"))
                        LabeledContent(L.t("Hora de salida", "Departure time")) {
                            Text(DiasNotificaciones.fecha(minutos: recordatorio.minutoDelDia), style: .time)
                        }
                        LabeledContent(L.t("Días de salida", "Departure days"), value: DiasNotificaciones.resumen(recordatorio.dias))
                        if servicio.destinoActual == nil {
                            Text(L.t("Elige otro destino para reanudar este recordatorio.", "Choose another destination to resume this reminder."))
                                .font(.footnote).foregroundStyle(.appError)
                        }
                        Button(L.t("Editar recordatorio", "Edit reminder")) { editarRecordatorio = true }
                    } else {
                        Button { editarRecordatorio = true } label: {
                            Label(L.t("Crear recordatorio", "Create reminder"), systemImage: "plus.circle.fill")
                        }
                    }
                } footer: {
                    if servicio.preferencias.configuracion.recordatorio == nil {
                        Text(L.t("Hora, días y destino. Tú eliges.", "Time, days and destination. Your choice."))
                    }
                }
                seccionAgenda(fechas: servicio.fechasProgramadas, ahora: contexto.date)
                if servicio.preferencias.activadas && servicio.permitido && servicio.destinoActual != nil
                    && !servicio.programando && !servicio.fechasProgramadas.contains(where: { $0 > contexto.date }) {
                    Section {
                        Text(L.t("No hay fechas programadas. Revisa los días y horarios de silencio.", "There are no scheduled dates. Check quiet days and hours."))
                            .font(.subheadline)
                    }
                }
                if let error = servicio.errorMensaje {
                    Section { Text(L.aviso(error)).foregroundStyle(.appError) }
                }
                if servicio.preferencias.configuracion.recordatorio != nil {
                    Section {
                        Button(L.t("Eliminar recordatorio", "Delete reminder"), role: .destructive) { confirmarEliminar = true }
                    }
                }
            }
            .estiloFormularioNotificaciones()
        }
        .navigationTitle(L.t("Recordatorio de viaje", "Trip reminder"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var detalleDiarios: some View {
        TimelineView(.periodic(from: .now, by: 60)) { contexto in
            Form {
                Section {
                    Toggle(L.t("Avisos diarios aleatorios", "Random daily notifications"), isOn: Binding(
                        get: { servicio.avisosDiarios.configuracion.activa },
                        set: { valor in Task { await servicio.activarAvisosDiarios(valor) } }
                    ))
                    .disabled(servicio.avisosDiarios.datosInvalidos || servicio.avisosDiarios.registroInvalido || servicio.preferencias.datosInvalidos || servicio.solicitandoPermiso)
                } footer: {
                    Text(L.t("Consejos generales, en un horario al azar.", "General tips, at a random time."))
                }
                if servicio.avisosDiarios.configuracion.activa {
                    Section {
                        Text(ConfiguracionAvisosDiarios.textoCantidad(servicio.avisosDiarios.configuracion.cantidad))
                        LabeledContent(L.t("Franja de envío", "Delivery window"), value: franjaDiarios)
                        Button(L.t("Horario y cantidad", "Time and frequency")) { editarDiarios = true }
                            .disabled(servicio.avisosDiarios.datosInvalidos || servicio.avisosDiarios.registroInvalido)
                    }
                    seccionAgenda(fechas: servicio.fechasDiarias, ahora: contexto.date)
                    if !servicio.preferencias.activadas {
                        Section {
                            Text(L.t("Activa las notificaciones para recibir los avisos diarios.", "Turn on notifications to receive daily notifications."))
                                .font(.subheadline)
                        }
                    } else if servicio.permitido && !servicio.programando
                                && !servicio.fechasDiarias.contains(where: { $0 > contexto.date }) {
                        Section {
                            Text(L.t("Sin avisos programados. Revisa la franja y los silencios.", "No notifications scheduled. Check the window and quiet settings."))
                                .font(.subheadline)
                        }
                    }
                }
                if let error = servicio.errorMensaje {
                    Section { Text(L.aviso(error)).foregroundStyle(.appError) }
                }
            }
            .estiloFormularioNotificaciones()
        }
        .navigationTitle(L.t("Avisos del día", "Daily notifications"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var detalleCambiosRuta: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            Form {
                Section {
                    Toggle(L.t("Cambios en mis líneas guardadas", "Changes on my saved lines"), isOn: Binding(
                        get: { push.activadas },
                        set: { valor in Task { await push.cambiar(valor) } }
                    ))
                    .disabled(!push.disponibleEnVersion || push.datosInvalidos || servicio.preferencias.datosInvalidos)
                    Text(push.textoEstado).font(.subheadline).foregroundStyle(EstiloPreferencias.textoSecundario)
                } footer: {
                    Text(L.t("Reportes de la comunidad sobre tus líneas guardadas.", "Community reports about your saved lines."))
                }
                Section {
                    if push.lineas.isEmpty {
                        Text(L.t("Guarda una línea para recibir sus cambios de ruta.", "Save a line to receive its route changes."))
                    } else {
                        Text(L.f("Líneas guardadas: {0}", "Saved lines: {0}", [String(push.lineas.count)]))
                    }
                    if push.disponibleEnVersion {
                        Button(L.t("Sincronizar ahora", "Sync now")) { push.sincronizar(forzar: true) }
                        if let hasta = push.fechaCobertura {
                            LabeledContent(L.t("Registro válido hasta", "Registration valid until"), value: servicio.fechaTexto(hasta))
                        }
                    }
                } footer: {
                    if push.disponibleEnVersion && push.fechaCobertura != nil {
                        Text(L.t("Abre la app para renovar el registro.", "Open the app to renew registration."))
                    }
                }
                if push.pendienteSincronizar {
                    Section {
                        Text(L.t("La pausa o el cambio aún no llegó al servidor. Los avisos remotos pueden seguir usando tus ajustes anteriores hasta sincronizar.", "The pause or change has not reached the server yet. Remote notifications may use your previous settings until you sync."))
                            .font(.subheadline).foregroundStyle(.appError)
                    }
                }
            }
            .estiloFormularioNotificaciones()
        }
        .navigationTitle(L.t("Cambios de ruta", "Route changes"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var detalleSilencios: some View {
        Form {
            Section {
                SeleccionDiasNotificaciones(seleccionados: servicio.preferencias.configuracion.diasSilencio) { dia in
                    Task {
                        await servicio.cambiar {
                            if $0.diasSilencio.contains(dia) { $0.diasSilencio.remove(dia) }
                            else { $0.diasSilencio.insert(dia) }
                        }
                    }
                }
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
                        Text(L.t("Silencio todo el día.", "Muted all day."))
                            .font(.footnote).foregroundStyle(EstiloPreferencias.textoSecundario)
                    }
                }
            } header: { Text(L.t("Horario de silencio", "Quiet hours")) }
              footer: { Text(L.t("Puede cruzar la medianoche. Horas iguales silencian todo el día.", "Can cross midnight. Matching times mute the entire day.")) }
            if let error = servicio.errorMensaje {
                Section { Text(L.aviso(error)).foregroundStyle(.appError) }
            }
        }
        .disabled(servicio.preferencias.datosInvalidos)
        .estiloFormularioNotificaciones()
        .navigationTitle(L.t("Días y horas de silencio", "Quiet days and hours"))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private func seccionAgenda(fechas: [Date], ahora: Date) -> some View {
        if let primera = fechas.first(where: { $0 > ahora }), let ultima = fechas.last {
            Section {
                LabeledContent(L.t("Próximo aviso", "Next notification"), value: servicio.fechaTexto(primera))
                LabeledContent(L.t("Programado hasta", "Scheduled until"), value: servicio.fechaTexto(ultima))
            } header: { Text(L.t("Agenda", "Schedule")) }
              footer: { Text(L.t("Abre la app para renovar la agenda.", "Open the app to renew the schedule.")) }
        }
    }

    private var informacion: some View {
        Form {
            Section(L.t("Recordatorio de viaje", "Trip reminder")) {
                Text(L.t("Los avisos quedan programados hasta la fecha indicada. Abre la app para renovar la agenda.", "Notifications are scheduled until the date shown. Open the app to renew the schedule."))
            }
            Section(L.t("Avisos del día", "Daily notifications")) {
                Text(L.t("La hora se elige al azar dentro de tu franja. Son recordatorios generales: los avisos de obstrucciones o descuentos concretos necesitan datos confirmados.", "The time is chosen randomly within your window. These are general reminders: notifications about specific obstructions or discounts require confirmed data."))
            }
            Section(L.t("Cambios de ruta", "Route changes")) {
                Text(L.t("Avisos de la comunidad cuando al menos dos cuentas reportan el mismo cambio. Las pausas, días y horarios también se aplican al envío remoto una vez sincronizados.", "Community notifications when at least two accounts report the same change. Pauses, days and quiet hours also apply to remote delivery once synced."))
            }
            Section(L.t("Pausas", "Pauses")) {
                Text(L.t("Los avisos omitidos durante una pausa no se acumulan al reactivar.", "Notifications skipped during a pause are not sent when you resume."))
            }
            Section(L.t("Entrega y sonido", "Delivery and sound")) {
                Text(L.t("iOS puede silenciar o retrasar los avisos con Concentración o el Resumen programado.", "iOS may silence or delay notifications with Focus or Scheduled Summary."))
                Button(L.t("Abrir ajustes de iOS", "Open iOS settings")) { abrirAjustes() }
            }
        }
        .estiloFormularioNotificaciones()
        .navigationTitle(L.t("Cómo funcionan los avisos", "How notifications work"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var resumenRecordatorio: String {
        guard !servicio.preferencias.datosInvalidos else { return L.t("Revisa tus ajustes", "Check your settings") }
        guard let recordatorio = servicio.preferencias.configuracion.recordatorio else {
            return L.t("Hora, días y destino", "Time, days and destination")
        }
        guard let destino = servicio.destinoActual else { return L.t("Revisa el destino", "Check the destination") }
        return destino.nombre + " · " + horaTexto(recordatorio.minutoDelDia)
    }
    private var resumenDiarios: String {
        guard !servicio.avisosDiarios.datosInvalidos && !servicio.avisosDiarios.registroInvalido else {
            return L.t("Revisa tus ajustes", "Check your settings")
        }
        return servicio.avisosDiarios.configuracion.activa
            ? ConfiguracionAvisosDiarios.textoCantidad(servicio.avisosDiarios.configuracion.cantidad)
            : L.t("Desactivados", "Off")
    }
    private var resumenPush: String {
        if push.datosInvalidos { return L.t("Revisa tus ajustes", "Check your settings") }
        if !push.disponibleEnVersion { return L.t("No disponible en esta versión", "Unavailable in this version") }
        if push.pendienteSincronizar { return L.t("Pendiente de sincronizar", "Waiting to sync") }
        switch push.estado {
        case .desactivadas: return L.t("Desactivados", "Off")
        case .versionSinPush: return L.t("No disponible en esta versión", "Unavailable in this version")
        case .faltaPermiso: return L.t("Bloqueadas por iOS", "Blocked by iOS")
        case .registrandoApple, .sincronizando: return L.t("Sincronizando…", "Syncing…")
        case .pendiente: return L.t("Pendiente de sincronizar", "Waiting to sync")
        case .confirmado: return L.t("Registro remoto confirmado", "Remote registration confirmed")
        case .faltaConexion, .requiereTLS, .errorApple, .faltaProveedor, .rechazado:
            return L.t("Revisar servicio", "Check service")
        }
    }
    private var resumenSilencios: String {
        let config = servicio.preferencias.configuracion
        guard !servicio.preferencias.datosInvalidos else { return L.t("Revisa tus ajustes", "Check your settings") }
        var partes: [String] = []
        if !config.diasSilencio.isEmpty { partes.append(DiasNotificaciones.resumen(config.diasSilencio)) }
        if config.silencioHorario {
            partes.append(config.inicioSilencio == config.finSilencio
                          ? L.t("Silencio todo el día.", "Muted all day.")
                          : horaTexto(config.inicioSilencio) + " – " + horaTexto(config.finSilencio))
        }
        return partes.isEmpty ? L.t("Sin silencios", "No quiet settings") : partes.joined(separator: " · ")
    }
    private var franjaDiarios: String {
        horaTexto(servicio.avisosDiarios.configuracion.inicio) + " – " + horaTexto(servicio.avisosDiarios.configuracion.fin)
    }
    private func horaTexto(_ minutos: Int) -> String {
        DiasNotificaciones.fecha(minutos: minutos)
            .formatted(.dateTime.hour().minute().locale(IdiomaManager.shared.idioma.locale))
    }

    private func menuPausa(ahora: Date) -> some View {
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
            HStack(spacing: 12) {
                FilaNotificaciones(titulo: L.t("Pausar avisos", "Pause notifications"), simbolo: "pause.fill",
                                   detalle: servicio.preferencias.configuracion.pausaHasta.flatMap { $0 > ahora ? servicio.fechaTexto($0) : nil }
                                   ?? L.t("Sin pausa", "Not paused"))
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(EstiloPreferencias.textoSecundario)
                    .accessibilityHidden(true)
            }
        }
        .disabled(!servicio.preferencias.activadas || servicio.preferencias.datosInvalidos)
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
            .estiloFormularioNotificaciones()
            .navigationTitle(L.t("Pausar avisos", "Pause notifications"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L.t("Cancelar", "Cancel")) { pausaPersonalizada = false } } }
        }
        .seguirTemaForzado()
        .presentationDetents([.medium, .large])
    }
}

/// Etiqueta de Ajustes: icono, título y un único resumen, sin recortar texto grande.
private struct FilaNotificaciones: View {
    let titulo: String
    let simbolo: String
    var detalle: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            IconoPreferencias(simbolo: simbolo)
            VStack(alignment: .leading, spacing: 3) {
                Text(titulo).font(.body).foregroundStyle(EstiloPreferencias.texto)
                if let detalle {
                    Text(detalle).font(.subheadline).foregroundStyle(EstiloPreferencias.textoSecundario)
                }
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 44)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    func estiloFormularioNotificaciones() -> some View {
        self.estiloFormularioPreferencias()
    }
}
