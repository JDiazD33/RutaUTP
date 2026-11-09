//
//  PassiveTrackingCoordinator+CicloDeVida.swift
//  RutaUTP
//
//  Pausa y reanudación del coordinador pasivo con el ciclo de vida de la app.
//

import Foundation
import UIKit

extension PassiveTrackingCoordinator {

    // MARK: - Ciclo de vida de la app

    /// Registra los observadores de segundo plano/foreground.
    func observeAppLifecycle() {
        guard backgroundObserver == nil else {
            return
        }

        backgroundObserver = NotificationCenter
            .default
            .addObserver(
                forName:
                    UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.pauseObservationSessionForBackground()
                }
            }

        foregroundObserver = NotificationCenter
            .default
            .addObserver(
                forName:
                    UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.resumeObservationSessionIfNeeded()
                }
            }
    }

    func removeAppLifecycleObservers() {
        if let backgroundObserver {
            NotificationCenter
                .default
                .removeObserver(backgroundObserver)

            self.backgroundObserver = nil
        }

        if let foregroundObserver {
            NotificationCenter
                .default
                .removeObserver(foregroundObserver)

            self.foregroundObserver = nil
        }
    }

    /// Corta la publicación al pasar a segundo plano.
    ///
    /// iOS suspende el proceso pocos segundos después: el socket MQTT
    /// moriría sin desconexión limpia y el GPS se detendría. Se cierra
    /// la conexión conservando el `sessionID` y la ruta confirmada,
    /// porque el viaje sigue vigente y debe poder reanudarse.
    ///
    /// La existencia de la sesión es la condición suficiente: si no hay
    /// viaje en curso no hay nada que pausar, con o sin coordinador vivo.
    ///
    /// Visibilidad interna para que XCTest verifique la pausa/reanudación
    /// sin simular el ciclo de vida real de la app.
    func pauseObservationSessionForBackground() {
        appEnSegundoPlano = true
        shouldPublish = false
        tripOccupancy.stop()
        guard observationSessionID != nil, !sesionPausadaPorBackground else {
            return
        }

        sesionPausadaPorBackground = true
        observationPublisher?.stop()

        refreshObservationPublisherState()

        contributionStatus =
            .pausedBackground
    }

    /// Reanuda la publicación si el viaje detectado sigue vigente.
    ///
    /// Se reutiliza el mismo `sessionID`: la reanudación pertenece al
    /// mismo viaje y cuenta MQTT. La siguiente muestra GPS que apruebe el
    /// detector vuelve a transmitirse sin esperar un nuevo abordaje.
    ///
    /// Un posible descenso no autoriza envío todavía. Se conserva la pausa
    /// hasta que `process` reciba una decisión que vuelva a autorizarlo.
    func resumeObservationSessionIfNeeded() {
        appEnSegundoPlano = false
        reanudarSesionPausadaSiSePuede()
    }

    func reanudarSesionPausadaSiSePuede() {
        guard
            isEnabled, !appEnSegundoPlano, sesionPausadaPorBackground,
            detectionState == .onboard,
            let sessionID = observationSessionID,
            let linea = confirmedLine, confirmedRouteID != nil
        else {
            return
        }

        // Consumir la pausa antes de start: ni foreground repetido ni las
        // siguientes muestras deben duplicar conexiones o forzar un reenvío.
        sesionPausadaPorBackground = false
        observationPublisher?.start(
            sessionID: sessionID,
            linea: linea
        )

        refreshObservationPublisherState()

        contributionStatus =
            .detected(linea)
    }
}
