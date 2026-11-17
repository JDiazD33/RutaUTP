// Avisos compartidos por Ajustes y la tarjeta del viaje. El UUID de viaje
// cambia, pero la cuenta autenticada permite relacionar sesiones. La app no
// conoce la configuración de conservación del servidor: no prometer borrado.

import Foundation

enum TextoConsentimientoContribucion {
    // Propiedades calculadas: L.t debe leer el idioma actual en cada vista,
    // sin almacenar la traducción elegida al abrir la app por primera vez.
    static var explicacion: String {
        L.t("Si lo activas, la app analizará tu ubicación y actividad física para detectar viajes. Tras confirmar uno, enviará al servicio configurado ubicación y precisión, fecha, ruta y línea, velocidad, rumbo y actividad física, junto a la cuenta de esta instalación y un identificador de viaje. La cuenta permite relacionar distintos viajes. El servidor puede conservar un historial sin borrado automático, según su configuración. Por defecto, la contribución se pausa en segundo plano o con la pantalla bloqueada; si lo permites, continúa solo durante tus viajes. Desactivarla detiene futuros envíos, sin borrar lo ya recibido.",
            "If you turn this on, the app will analyse your location and motion activity to detect trips. After confirming one, it will send location and accuracy, time, route and line, speed, heading and motion activity to the configured service, along with this installation's account and a trip identifier. The account allows different trips to be linked. Depending on its configuration, the server may keep a history without automatic deletion. By default, contribution pauses in the background or while the screen is locked; if you allow it, it continues only during your trips. Turning it off stops future uploads without deleting data already received.")
    }

    static var confirmacion: String {
        L.t("Solo tras confirmar un viaje se enviarán ubicación, fecha, ruta y datos de movimiento al servicio configurado, asociados a la cuenta de esta instalación y al identificador del viaje. La cuenta permite relacionar distintos viajes. El servidor puede conservar un historial sin borrado automático, según su configuración. Por defecto, el envío se pausa en segundo plano o con la pantalla bloqueada; puedes permitir que continúe durante tus viajes. Desactivar detiene futuros envíos; no borra lo recibido.",
            "Only after confirming a trip will location, time, route and motion data be sent to the configured service, linked to this installation's account and the trip identifier. The account allows different trips to be linked. Depending on its configuration, the server may keep a history without automatic deletion. By default, uploads pause in the background or while the screen is locked; you can allow them to continue during your trips. Turning this off stops future uploads; it does not delete data already received.")
    }

    // MARK: - Segundo plano

    // Consentimiento propio, separado del de contribución: iOS mantiene el GPS
    // con permiso «Al usar la app» y lo indica en la barra de estado.

    static var segundoPlanoTitulo: String {
        L.t("Seguir en segundo plano", "Continue in background")
    }

    static var segundoPlanoDetalle: String {
        L.t("Solo durante tus viajes", "Only during your trips")
    }

    static var segundoPlanoDialogo: String {
        L.t("¿Seguir ayudando en segundo plano?", "Keep helping in the background?")
    }

    static var segundoPlanoConfirmacion: String {
        L.t("Durante un viaje, RutaUTP seguirá usando tu ubicación y enviando los mismos datos aunque bloquees la pantalla o cambies de app. iOS lo indicará en la barra de estado. Se detiene al terminar el viaje y no se usa fuera de uno. Consume más batería. Puedes desactivarlo cuando quieras.",
            "During a trip, RutaUTP will keep using your location and sending the same data even if you lock the screen or switch apps. iOS shows this in the status bar. It stops when the trip ends and isn't used outside a trip. It uses more battery. You can turn it off at any time.")
    }

    static var segundoPlanoAceptar: String {
        L.t("Permitir en segundo plano", "Allow in background")
    }

    static var segundoPlanoPista: String {
        L.t("Permite que la contribución siga con la pantalla bloqueada o en otra app durante un viaje.",
            "Lets contribution continue with the screen locked or in another app during a trip.")
    }

    static var segundoPlanoNota: String {
        L.t("Solo durante tus viajes. iOS lo indica en la barra de estado y consume más batería.",
            "Only during your trips. iOS shows it in the status bar, and it uses more battery.")
    }

    static var pistaAccesibilidad: String {
        L.t("Activar solicita permiso para enviar ubicación y datos del viaje al servicio configurado, asociados a la cuenta de esta instalación y a un identificador de viaje. Desactivar detiene futuros envíos, sin borrar lo recibido.",
            "Turning this on requests permission to send location and trip data to the configured service, linked to this installation's account and a trip identifier. Turning it off stops future uploads without deleting data already received.")
    }
}
