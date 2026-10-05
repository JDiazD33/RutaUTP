// Avisos compartidos por Ajustes y la tarjeta del viaje. El UUID de viaje
// cambia, pero la cuenta autenticada permite relacionar sesiones. La app no
// conoce la configuración de conservación del servidor: no prometer borrado.

import Foundation

enum TextoConsentimientoContribucion {
    // Propiedades calculadas: L.t debe leer el idioma actual en cada vista,
    // sin almacenar la traducción elegida al abrir la app por primera vez.
    static var explicacion: String {
        L.t("Si lo activas, la app analizará tu ubicación y actividad física para detectar viajes. Tras confirmar uno, enviará al servicio configurado ubicación y precisión, fecha, ruta y línea, velocidad, rumbo y actividad física, junto a la cuenta de esta instalación y un identificador de viaje. La cuenta permite relacionar distintos viajes. El servidor puede conservar un historial sin borrado automático, según su configuración. La contribución se pausa en segundo plano o con la pantalla bloqueada. Desactivarla detiene futuros envíos, sin borrar lo ya recibido.",
            "If you turn this on, the app will analyse your location and motion activity to detect trips. After confirming one, it will send location and accuracy, time, route and line, speed, heading and motion activity to the configured service, along with this installation's account and a trip identifier. The account allows different trips to be linked. Depending on its configuration, the server may keep a history without automatic deletion. Contribution pauses in the background or while the screen is locked. Turning it off stops future uploads without deleting data already received.")
    }

    static var confirmacion: String {
        L.t("Solo tras confirmar un viaje se enviarán ubicación, fecha, ruta y datos de movimiento al servicio configurado, asociados a la cuenta de esta instalación y al identificador del viaje. La cuenta permite relacionar distintos viajes. El servidor puede conservar un historial sin borrado automático, según su configuración. El envío se pausa en segundo plano o con la pantalla bloqueada. Desactivar detiene futuros envíos; no borra lo recibido.",
            "Only after confirming a trip will location, time, route and motion data be sent to the configured service, linked to this installation's account and the trip identifier. The account allows different trips to be linked. Depending on its configuration, the server may keep a history without automatic deletion. Uploads pause in the background or while the screen is locked. Turning this off stops future uploads; it does not delete data already received.")
    }

    static var pistaAccesibilidad: String {
        L.t("Activar solicita permiso para enviar ubicación y datos del viaje al servicio configurado, asociados a la cuenta de esta instalación y a un identificador de viaje. Desactivar detiene futuros envíos, sin borrar lo recibido.",
            "Turning this on requests permission to send location and trip data to the configured service, linked to this installation's account and a trip identifier. Turning it off stops future uploads without deleting data already received.")
    }
}
