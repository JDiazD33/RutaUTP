"""Orquestación del puente `observaciones` -> `vehiculos`.

`Bridge` concentra la lógica y no sabe nada de sockets: recibe un mensaje, lo
valida, lo agrega y, si toca, publica. La publicación se inyecta como una
función, de modo que todo el comportamiento se puede probar sin levantar un
broker.

La capa de red (paho-mqtt) vive solo en `run()`.
"""

from __future__ import annotations

import json
import logging
import signal
import time
import uuid
from dataclasses import dataclass, replace
from typing import Any, Callable

from .aggregation import VehicleAggregator
from .config import Config
from .gtfs import GtfsFeed
from .health import remove_heartbeat, write_heartbeat
from .metrics import Metrics
from .models import RejectReason
from .persistence import ObservationStore, SimulationPersistenceUnavailable, open_store
from .simulation_models import DataOrigin, OBSERVED_SOURCE, UNKNOWN_SOURCE, SourceContext
from .simulation_ingress import (
    AdmissionProvider, SimulationAdmission, SIMULATION_OBSERVATIONS_TOPIC,
    SIMULATION_CONTROL_TOPIC, is_reserved_principal, parse_observation_topic,
)
from .simulation_control import ControlPublisher, SimulationController
from .simulation_control_store import ControlBusy, ControlStore, ControlUnavailable
from .validation import ObservationValidator
from .route_changes import RouteChanges, REPORT_TOPIC
from .occupancy import Occupancy, REPORT_TOPIC as OCCUPANCY_REPORT_TOPIC

logger = logging.getLogger(__name__)

# `(topico, carga_util)` -> `True` si el broker aceptó el mensaje.
#
# Devolver un booleano importa: antes el publicador no comunicaba el fallo, así
# que el puente contaba como publicada una posición que el broker había
# rechazado, y no volvía a intentarlo.
Publisher = Callable[[str, str], bool]

# Cada cuántos segundos se vuelca el resumen de contadores.
SUMMARY_INTERVAL_S = 60.0

# Espera progresiva entre reintentos de conexión. Empieza en un segundo para
# recuperarse rápido de un corte breve y se dobla hasta el máximo, para no
# martillear un broker caído ni consumir CPU reintentando sin parar.
RECONNECT_INITIAL_S = 1.0
RECONNECT_MAX_S = 30.0


def _sleep_until_reconnect(
    now: float,
    next_attempt_at: float,
    max_sleep_s: float,
) -> None:
    """Cede CPU mientras todavía no corresponde reconectar.

    `paho.Client.loop()` retorna inmediatamente cuando no existe un socket. Sin
    esta pausa, el bucle exterior gira a máxima velocidad durante todo el
    backoff aunque los intentos de conexión sí estén espaciados correctamente.
    La espera se divide en tramos de `max_sleep_s` para volver pronto al bucle,
    actualizar el latido y atender una señal de cierre.
    """
    remaining = next_attempt_at - now

    if remaining > 0:
        time.sleep(min(remaining, max_sleep_s))


@dataclass(frozen=True)
class HandleOutcome:
    """Qué pasó con un mensaje. Útil para pruebas y para el registro."""

    accepted: bool
    vehicle_id: str | None = None
    reason: RejectReason | None = None
    detail: str = ""
    created_vehicle: bool = False
    published: bool = False


class Bridge:
    """Puente entre las balizas del pasajero y el mapa de los demás usuarios."""

    def __init__(
        self,
        config: Config,
        feed: GtfsFeed,
        publisher: Publisher | None = None,
        validator: ObservationValidator | None = None,
        aggregator: VehicleAggregator | None = None,
        metrics: Metrics | None = None,
        store: ObservationStore | None = None,
        admission_provider: AdmissionProvider | None = None,
        simulation_control: SimulationController | None = None,
    ) -> None:
        self.config = config
        self.feed = feed
        self.route_changes = RouteChanges(feed)
        self.push = None
        self.publisher = publisher
        self.validator = validator or ObservationValidator(feed, config)
        # El feed se pasa al agregador para que conozca la longitud de cada
        # recorrido: es lo que convierte una diferencia de `progress` en metros.
        self.aggregator = aggregator or VehicleAggregator(config, feed)
        self.occupancy = Occupancy(self.aggregator.snapshot)
        self.metrics = metrics or Metrics()
        self.store = store or open_store(
            config.database_path, config.retention_days
        )

        # El controlador S04 inyectará permisos verificados. Por defecto la
        # simulación permanece cerrada, incluso si se activa su suscripción.
        self.admission_provider = admission_provider
        self.simulation_control = simulation_control
        self.control_publisher: ControlPublisher | None = None
        if (self.simulation_control is None and admission_provider is None
                and config.simulation_ingress_enabled and config.simulation_control_path):
            try:
                self.simulation_control = SimulationController(
                    ControlStore(config.simulation_control_path), self.store, config.gtfs_dir,
                )
            except (ControlUnavailable, OSError, ValueError):
                logger.error("control sintético ausente/no disponible; rama cerrada")
        if self.simulation_control is not None:
            if admission_provider is not None:
                raise ValueError("no combinar controlador y proveedor de admisión independientes")
            self.admission_provider = self.simulation_control.admission
        self._simulation_validator: ObservationValidator | None = None
        self._simulation_aggregator: VehicleAggregator | None = None
        self._simulation_policy: tuple[str, frozenset[str]] | None = None
        self._simulation_revision = 0
        self._simulation_revision_run: str | None = None
        self._simulation_revision_principals: frozenset[str] | None = None

        self._last_summary_at = 0.0

        #: Momento de la última publicación aceptada por el broker. Es lo que
        #: permite distinguir "no hay pasajeros contribuyendo" de "el servicio
        #: dejó de publicar".
        self._last_publish_at = 0.0

    # ── Un mensaje ────────────────────────────────────────────────────────

    def handle_message(
        self,
        topic: str,
        payload: bytes | str,
        now: float | None = None,
        *, retained: bool = False,
    ) -> HandleOutcome:
        """Procesa un mensaje entrante del broker.

        Es la única entrada del sistema y **nunca propaga una excepción**: un
        mensaje manipulado no puede detener el servicio. Los fallos esperables se
        convierten en un motivo de rechazo; los inesperados se registran con su
        traza y se cuentan aparte, para que no se confundan con datos inválidos
        del cliente.
        """
        now = time.time() if now is None else now

        self.metrics.record_received()

        try:
            return self._handle(topic, payload, now, retained=retained)
        except Exception:  # noqa: BLE001 - barrera deliberada de último recurso
            if topic.startswith("rutautp/simulacion/"):
                self._clear_simulation()
            self.metrics.record_rejected(RejectReason.INTERNAL_ERROR)
            self.metrics.record_internal_error()

            logger.exception(
                "fallo inesperado procesando un mensaje de %s; se descarta y "
                "el servicio continúa",
                topic,
            )

            return HandleOutcome(
                accepted=False,
                reason=RejectReason.INTERNAL_ERROR,
                detail="error interno",
            )

    def _clear_simulation(self) -> None:
        self._simulation_validator = None
        self._simulation_aggregator = None
        self._simulation_policy = None

    def _current_admission(self, now: float) -> SimulationAdmission | None:
        admission = None
        self._admission_was_busy = False
        if self.config.simulation_ingress_enabled and self.admission_provider is not None:
            try:
                candidate = self.admission_provider(now)
                if isinstance(candidate, SimulationAdmission) and candidate.is_current(now):
                    # Defensa adicional contra revisiones regresivas o la
                    # reutilización de una revisión con otro run.
                    if candidate.control_revision > self._simulation_revision or (
                        candidate.control_revision == self._simulation_revision
                        and candidate.run_id == self._simulation_revision_run
                        and candidate.principals == self._simulation_revision_principals
                    ):
                        self.store.require_simulation_run(candidate.run_id)
                        admission = candidate
                        self._simulation_revision = candidate.control_revision
                        self._simulation_revision_run = candidate.run_id
                        self._simulation_revision_principals = candidate.principals
            except ControlBusy:
                # Sin lectura actual no se autoriza nada. Conservar únicamente
                # la caché: al volver se revalidan lease, run, revisión y quorum.
                # Disable, caducidad y errores persistentes siguen vaciándola.
                self._admission_was_busy = True
                return None
            except Exception:  # un controlador/almacén fallido cierra solo esta rama
                logger.error("autorización sintética no disponible; entrada cerrada")
        if admission is None or (
            self._simulation_policy is not None
            and self._simulation_policy != (admission.run_id, admission.principals)
        ):
            self._clear_simulation()
        return admission

    def _reject(
        self, reason: RejectReason, detail: str, now: float,
        source: SourceContext = UNKNOWN_SOURCE,
    ) -> HandleOutcome:
        self.metrics.record_rejected(reason, source)
        try:
            self.store.record_rejection(reason, detail, now, source=source)
        except (SimulationPersistenceUnavailable, ValueError):
            # El rechazo sigue contado aunque ya no pueda escribirse en disco.
            self._clear_simulation()
            logger.error("no se pudo guardar un rechazo sintético")
        return HandleOutcome(accepted=False, reason=reason, detail=detail)

    def _handle(
        self, topic: str, payload: bytes | str, now: float, *, retained: bool = False,
    ) -> HandleOutcome:
        started = time.monotonic()
        # Límite antes de cualquier decodificación JSON, también de la sesión.
        if len(payload) > self.config.max_message_bytes:
            return self._reject(
                RejectReason.MESSAGE_TOO_LARGE,
                f"{len(payload)} bytes > {self.config.max_message_bytes}", now,
            )
        identity = parse_observation_topic(topic)
        if identity is None:
            return self._reject(RejectReason.SESSION_MISMATCH, "tópico de observación no canónico", now)
        if retained:
            return self._reject(RejectReason.SOURCE_NOT_AUTHORIZED, "las observaciones no admiten retained", now)

        admission = self._current_admission(now)
        source = SourceContext(DataOrigin.OBSERVED, principal=identity.principal)
        validator, aggregator = self.validator, self.aggregator
        if identity.origin is DataOrigin.SIMULATED:
            if (admission is None or identity.run_id != admission.run_id
                    or identity.principal not in admission.principals):
                if admission is None and self._admission_was_busy:
                    self.metrics.simulation_control_busy_rejections += 1
                    return self._reject(RejectReason.SOURCE_NOT_AUTHORIZED, "simulation_control_busy", now)
                return self._reject(RejectReason.SOURCE_NOT_AUTHORIZED, "run/principal sintético no autorizado", now)
            source = SourceContext(DataOrigin.SIMULATED, identity.run_id, identity.principal)
            if self._simulation_aggregator is None:
                self._simulation_policy = (admission.run_id, admission.principals)
                self._simulation_validator = self.validator.isolated_partition()
                # Una nueva instancia, incluso tras una pausa, no reutiliza IDs
                # que aún podrían estar visibles en un consumidor.
                partition_config = replace(self.config, vehicle_namespace=uuid.uuid4().hex)
                self._simulation_aggregator = VehicleAggregator(
                    partition_config, self.feed,
                    source=SourceContext(DataOrigin.SIMULATED, admission.run_id),
                )
            validator = self._simulation_validator
            aggregator = self._simulation_aggregator
            assert validator is not None and aggregator is not None
        elif is_reserved_principal(identity.principal):
            return self._reject(RejectReason.SOURCE_NOT_AUTHORIZED, "principal sintético en rama habitual", now)

        mismatch = self._session_mismatch(identity.session_id, payload)
        if mismatch is not None:
            # Un run todavía no registrado no debe introducir una FK inválida.
            return self._reject(RejectReason.SESSION_MISMATCH, mismatch, now)

        try:
            guard = None
            if source.origin is DataOrigin.SIMULATED:
                guard = lambda observation: self.store.require_simulation_observation(source, observation)
            if guard is None:
                result = validator.validate(payload, now, principal=identity.principal)
            else:
                result = validator.validate(payload, now, principal=identity.principal, guard=guard)
            if not result.ok:
                return self._reject(result.reason or RejectReason.MALFORMED_JSON, result.detail, now, source)
            observation = result.observation
            assert observation is not None
            vehicle, created = aggregator.ingest(observation, now, principal=identity.principal)
            self.store.record_observation(observation, vehicle.vehicle_id, now, source=source)
            if created:
                self.metrics.record_created(source)
            published = self._publish_if_due(
                vehicle, now, now, aggregator=aggregator, source=source,
                admission=admission, elapsed=time.monotonic() - started,
            )
        except SimulationPersistenceUnavailable:
            self._clear_simulation()
            return self._reject(RejectReason.SIMULATION_UNAVAILABLE, "histórico sintético no disponible", now)
        except ValueError:
            if source.origin is not DataOrigin.SIMULATED:
                raise
            return self._reject(RejectReason.SOURCE_NOT_AUTHORIZED, "abordaje/run no registrado o no vigente", now)

        self.metrics.record_accepted(source, at=now)
        return HandleOutcome(
            accepted=True, vehicle_id=vehicle.vehicle_id,
            created_vehicle=created, published=published,
        )

    def _publish_if_due(
        self, vehicle: Any, now: float, wall_clock: float, *,
        aggregator: VehicleAggregator | None = None,
        source: SourceContext = OBSERVED_SOURCE,
        admission: SimulationAdmission | None = None,
        elapsed: float = 0.0,
    ) -> bool:
        publishing_started = time.monotonic()
        aggregator = aggregator or self.aggregator
        if self.publisher is None or not aggregator.should_publish(vehicle, now):
            return False
        if source.origin is DataOrigin.SIMULATED:
            # Antes de entregar al transporte, ambos registros deben ser
            # durables. Una fila es un intento de entrega, no un PUBACK.
            occupancy = {}
            if self.config.simulation_occupancy_enabled:
                from .simulation_occupancy import SCRIPT_VERSION, scenario_occupancy
                occupancy = {"scenario_occupancy": scenario_occupancy(source, vehicle.vehicle_id, vehicle.timestamp),
                             "occupancy_script_version": SCRIPT_VERSION}
            self.store.record_vehicle(vehicle, wall_clock, source=source, **occupancy)
            if not self.store.flush():
                raise SimulationPersistenceUnavailable("falló el commit sintético")
            current = self._current_admission(now + elapsed + time.monotonic() - publishing_started)
            if (current is None or admission is None or current.run_id != source.run_id
                    or current.principals != admission.principals):
                return False
            body = (vehicle.to_vehicle_position_v3(source, current.control_revision)
                    if self.config.simulation_occupancy_enabled
                    else vehicle.to_vehicle_position_v2(source, current.control_revision))
        elif self.config.vehicle_position_schema_version == 2:
            body = vehicle.to_vehicle_position_v2(source)
        else:
            body = vehicle.to_vehicle_position()

        self.metrics.record_publish_attempt(source)
        topic = self.config.vehicle_topic(vehicle.vehicle_id)
        try:
            accepted = self.publisher(topic, json.dumps(body, allow_nan=False))
        except Exception:  # un transporte roto no debe tumbar el puente
            self.metrics.record_publish_failed(source)
            logger.exception("el publicador lanzó una excepción para %s", topic)
            return False
        if not accepted:
            self.metrics.record_publish_failed(source)
            return False
        aggregator.mark_published(vehicle, now)
        self.metrics.record_published(source)
        if source.origin is DataOrigin.OBSERVED:
            self.store.record_vehicle(vehicle, wall_clock, source=source)
        self._last_publish_at = wall_clock
        return True

    @staticmethod
    def _topic_identity(topic: str) -> tuple[str, str] | None:
        """Extrae solo la identidad habitual; el parser completo admite ambas."""
        identity = parse_observation_topic(topic)
        if identity is None or identity.origin is not DataOrigin.OBSERVED:
            return None
        return identity.principal, identity.session_id

    def _session_mismatch(
        self, topic_session: str, payload: bytes | str
    ) -> str | None:
        """Comprueba que el tópico y el cuerpo declaren la misma sesión.

        Devuelve el motivo si no concuerdan, o `None` si concuerdan o si el
        cuerpo no puede decodificarse todavía.

        **Antes esto solo generaba una advertencia.** La consecuencia era que un
        cliente podía publicar en el tópico de una sesión y declarar otra en el
        cuerpo: el límite de tasa se aplicaba a la del cuerpo, mientras que el
        tópico —lo que un operador ve al diagnosticar— decía otra cosa. Rechazar
        hace que ambos coincidan siempre.

        La autenticidad del principal no se deduce del JSON: la garantiza la
        regla `%u` de Mosquitto, que solo permite publicar bajo el nombre del
        usuario autenticado. Aquí se comprueba la consistencia de la sesión.
        """
        try:
            body = json.loads(payload)
        except (json.JSONDecodeError, UnicodeDecodeError, TypeError):
            return None

        if not isinstance(body, dict):
            return None

        session_id = body.get("sessionId")

        # Tipos incorrectos y sesiones vacías conservan el diagnóstico del
        # validador. Una sesión presente debe coincidir exactamente, sin
        # autorizar una identidad distinta mediante recorte de espacios.
        if not isinstance(session_id, str) or not session_id.strip():
            return None

        if topic_session != session_id:
            return (
                f"el tópico declara {topic_session!r} y el cuerpo {session_id!r}"
            )

        return None

    # ── Mantenimiento periódico ───────────────────────────────────────────

    def _vehicle_counts(self) -> dict[str, int]:
        simulated = self._simulation_aggregator
        return {
            "vehicles": self.aggregator.vehicle_count + (simulated.vehicle_count if simulated else 0),
            "routes": self.aggregator.route_count + (simulated.route_count if simulated else 0),
            "observedVehicles": self.aggregator.vehicle_count,
            "simulationVehicles": simulated.vehicle_count if simulated else 0,
        }

    def tick(self, now: float | None = None, connected: bool | None = None) -> int:
        """Caduca vehículos, libera estado, late y vuelca el resumen si toca.

        `connected` es el estado real del cliente MQTT. Se inyecta en lugar de
        consultarlo aquí porque `Bridge` no conoce paho: así el latido se puede
        probar sin abrir un socket.
        """
        now = time.time() if now is None else now

        if self.simulation_control is not None:
            self.simulation_control.tick(now, None if connected is False else self.control_publisher)
        self._current_admission(now)
        expired = self.aggregator.expire(now)
        self.metrics.record_expired(len(expired), OBSERVED_SOURCE)
        if self._simulation_aggregator is not None:
            synthetic_expired = self._simulation_aggregator.expire(now)
            self.metrics.record_expired(len(synthetic_expired),
                SourceContext(DataOrigin.SIMULATED, self._simulation_policy[0]))
            expired += synthetic_expired
        if self._simulation_validator is not None:
            self._simulation_validator.prune(now)

        if expired:
            logger.info(
                "caducados %d vehículo(s): %s", len(expired), ", ".join(expired)
            )

        self.validator.prune(now)

        # Observados conservan el commit periódico. Sintéticos confirman además
        # antes de entregar cada posición, para cerrar ante fallos del histórico.
        self.store.flush()
        if not self.store.simulation_storage_status()["available"]:
            self._clear_simulation()
            if self.simulation_control is not None:
                self.simulation_control.tick(now, None if connected is False else self.control_publisher)
        self.store.prune(now)

        self._write_heartbeat(now, connected)

        if now - self._last_summary_at >= SUMMARY_INTERVAL_S:
            self._last_summary_at = now

            self.metrics.log_summary(
                {
                    **self._vehicle_counts(),
                    **self.store.counts.as_dict(),
                    **self.metrics.provenance_snapshot(),
                    'simulationStorage': self.store.simulation_storage_status(),
                }
            )

        return len(expired)

    def _write_heartbeat(self, now: float, connected: bool | None) -> None:
        """Deja constancia de que el servicio sigue ciclando.

        El estado de conexión solo se incluye cuando se conoce: escribirlo como
        `False` por omisión haría que una llamada desde una prueba —que no tiene
        broker— pareciera una caída real.
        """
        snapshot = self.metrics.snapshot()

        payload: dict[str, Any] = {
            "at": now,
            "received": snapshot["received"],
            "accepted": snapshot["accepted"],
            "rejected": snapshot["rejected"],
            "published": snapshot["published"],
            "publishFailures": snapshot["publishFailures"],
            "internalErrors": snapshot["internalErrors"],
            "simulationControlBusyRejections": snapshot["simulationControlBusyRejections"],
            **self._vehicle_counts(),
            "lastPublishAt": self._last_publish_at or None,
            **self.metrics.provenance_snapshot(),
            'persistence': self.store.counts.as_dict(),
            'simulationStorage': self.store.simulation_storage_status(),
            'positionPublicationMeaning': 'accepted_by_publisher_not_client_receipt',
            'app': {'positionsReceived': None, 'markersRendered': None, 'markerLimit': None},
        }
        if self.simulation_control is not None:
            payload["simulationControlError"] = self.simulation_control.error
            payload["simulationControlLock"] = self.simulation_control.control.lock_statistics()
            from .simulation_admin import status
            try:
                payload['simulation'] = status(self.simulation_control.control, now)
            except (ControlUnavailable, ValueError, OSError, TypeError, KeyError):
                payload['simulation'] = {'controlAvailable': False}

        if connected is not None:
            payload["connected"] = connected

        write_heartbeat(self.config.health_file, payload)

    # ── Red ───────────────────────────────────────────────────────────────

    def run(self, publish: bool = True, tick_interval_s: float = 1.0) -> None:
        """Conecta al broker y atiende mensajes hasta que se interrumpa.

        Se usa `client.loop()` en el hilo principal en vez de `loop_start()`:
        así las observaciones y reportes se procesan en el mismo hilo que
        `tick()`. APNs tiene su propio worker y serializa el acceso a su SQLite;
        no comparte geometria, votos ni estado vehicular con ese hilo.

        Con `publish=False` no se publica nada, aunque el publicador estuviera
        inyectado: es el modo de prueba contra un broker real.

        **La conexión se mantiene sola.** El bucle comprueba el estado real del
        cliente y reconecta con espera progresiva, en lugar de dar por hecho que
        `loop()` la restablece. Antes, un corte del broker dejaba el servicio
        desconectado para siempre y sin decir nada.
        """
        import paho.mqtt.client as mqtt
        from .push_config import PushConfig
        from .push_service import PushService

        if tick_interval_s <= 0:
            raise ValueError("tick_interval_s debe ser mayor que cero")

        # Nada de APNs en dry-run. El resto de la app sigue funcionando sin
        # Apple Developer: APNS_ENABLED=0 devuelve un estado honesto al cliente.
        self.push = None
        if publish:
            push_config = PushConfig.from_env(str(self.config.database_path), self.config.use_tls)
            self.push = PushService(push_config, self.feed)
            self.push.start()

        client = self._build_client(mqtt)

        if not publish:
            self.publisher = None
            self.control_publisher = None
            if self.simulation_control is not None:
                self.simulation_control.close(time.time())
                self.simulation_control = None
                self.admission_provider = None
            logger.info("publicación desactivada: nada saldrá hacia vehiculos/")
        elif self.publisher is None:
            self.publisher = self._client_publisher(client)
        if publish and self.simulation_control is not None and self.control_publisher is None:
            self.control_publisher = self._client_control_publisher(client)

        logger.info(
            "conectando a %s:%d (tls=%s, cliente=%s)",
            self.config.host,
            self.config.port,
            self.config.use_tls,
            self.config.client_id,
        )

        running = True

        def stop(signum: int, _frame: Any) -> None:
            nonlocal running
            running = False
            logger.info("señal %d recibida, cerrando", signum)

        previous_handlers: dict[int, Any] = {}

        for signum in (signal.SIGINT, signal.SIGTERM):
            previous_handlers[signum] = signal.signal(signum, stop)

        # El broker puede no estar disponible al arrancar. No es un error fatal:
        # el bucle reintenta igual que tras un corte.
        try:
            client.connect(self.config.host, self.config.port, keepalive=30)
        except OSError as error:
            logger.warning(
                "el broker no respondió al arrancar (%s); se reintentará", error
            )

        delay = RECONNECT_INITIAL_S
        next_attempt_at = 0.0

        try:
            while running:
                client.loop(timeout=tick_interval_s)
                self.tick(connected=client.is_connected())
                self.route_changes.publish_snapshot(time.time(), self.publisher)
                if self.push:
                    now_push = time.time()
                    if now_push - self.push.last_observe >= 5:
                        alerts = self.route_changes.confirmed_for_push(now_push) if self.push.ready else []
                        self.push.observe(alerts, now_push)
                self.occupancy.publish_snapshot(time.time(), self.publisher)

                if client.is_connected():
                    if delay != RECONNECT_INITIAL_S:
                        logger.info("conexión con el broker restablecida")

                    delay = RECONNECT_INITIAL_S
                    next_attempt_at = 0.0
                    continue

                now = time.monotonic()

                if now < next_attempt_at:
                    # Sin conexión, `client.loop()` no bloquea porque no hay
                    # socket. Hay que ceder CPU explícitamente durante el
                    # backoff; de lo contrario este `continue` ocupa un núcleo
                    # completo hasta el próximo intento.
                    _sleep_until_reconnect(
                        now,
                        next_attempt_at,
                        tick_interval_s,
                    )
                    continue

                logger.warning(
                    "sin conexión con el broker; reintentando en %.0f s", delay
                )

                try:
                    client.reconnect()
                except OSError as error:
                    logger.warning("reconexión fallida: %s", error)

                # Espera progresiva: no tiene sentido martillear un broker caído.
                next_attempt_at = now + delay
                delay = min(delay * 2, RECONNECT_MAX_S)
        finally:
            if self.simulation_control is not None:
                self.simulation_control.close(time.time(), self.control_publisher)
            if self.push:
                self.push.close()
            for signum, handler in previous_handlers.items():
                signal.signal(signum, handler)

            client.disconnect()
            self.store.close()

            # El latido se retira al salir: si se dejara, un supervisor lo vería
            # fresco hasta que venciera el margen y creería que el servicio
            # sigue en pie. Sin archivo, la comprobación dice la verdad de
            # inmediato.
            remove_heartbeat(self.config.health_file)

            self.metrics.log_summary(
                {
                    "vehicles": self.aggregator.vehicle_count,
                    "routes": self.aggregator.route_count,
                    **self.store.counts.as_dict(),
                }
            )

    def _client_control_publisher(self, client: Any) -> ControlPublisher:
        """Única excepción retained: control. El retorno es MID, no PUBACK."""
        def publish(topic: str, payload: str) -> int | None:
            if topic != SIMULATION_CONTROL_TOPIC or not client.is_connected():
                return None
            info = client.publish(topic, payload, qos=1, retain=True)
            return info.mid if info.rc == 0 else None
        return publish

    def _client_publisher(self, client: Any) -> Publisher:
        """Publicador que entrega al broker con QoS 1 y sin retención.

        Devuelve `True` solo si el broker aceptó el mensaje. `publish()` devuelve
        un código distinto de cero cuando la cola está llena o el cliente no
        está conectado, y ese caso no debe contarse como publicado.

        Sin retención, a propósito: una posición vehicular es un dato perecedero
        y el cliente ya descarta lo que supera 45 s. Dejar el último mensaje
        retenido haría que un usuario que se conecta tarde viera un vehículo
        fantasma hasta que el saneador lo descartara.
        """

        def publish(topic: str, payload: str) -> bool:
            info = client.publish(topic, payload, qos=1, retain=False)

            return info.rc == 0

        return publish

    def _build_client(self, mqtt: Any) -> Any:
        """Cliente paho configurado, compatible con paho 1.x y 2.x."""
        try:
            client = mqtt.Client(
                mqtt.CallbackAPIVersion.VERSION2,
                client_id=self.config.client_id,
            )
        except AttributeError:  # paho-mqtt 1.x
            client = mqtt.Client(client_id=self.config.client_id)

        if self.config.username:
            client.username_pw_set(self.config.username, self.config.password)

        if self.config.use_tls:
            # Con una CA propia hay que declararla: el certificado de Mosquitto
            # no está en el almacén del sistema. Nunca se desactiva la
            # verificación.
            client.tls_set(ca_certs=self.config.ca_cert or None)

        client.on_connect = self._on_connect
        client.on_disconnect = self._on_disconnect
        def on_publish(_client: Any, _userdata: Any, mid: int,
                       reason_code: Any = None, _properties: Any = None) -> None:
            code = getattr(reason_code, "value", reason_code)
            if self.simulation_control is not None and (code is None or int(code) < 128):
                self.simulation_control.acknowledge(mid, time.time())
        client.on_publish = on_publish

        def on_message(_client: Any, _userdata: Any, message: Any) -> None:
            if message.topic.startswith("rutautp/notificaciones/"):
                if self.push and self.config.use_tls and not message.retain:
                    try:
                        receipt = self.push.register(message.topic, message.payload, time.time())
                        if receipt and self.publisher:
                            principal, body = receipt
                            self.publisher(f"rutautp/notificaciones/{principal}/recibo", json.dumps(body))
                    except Exception:
                        # No incluir payload ni excepciones con datos privados.
                        logger.error("no se pudo guardar el registro de avisos")
                return
            if message.topic.startswith("rutautp/ocupacion/"):
                receipt = self.occupancy.handle(message.topic, message.payload, time.time())
                if receipt and self.publisher:
                    principal, body = receipt
                    self.publisher(f"rutautp/ocupacion/{principal}/recibo", json.dumps(body))
                return
            if message.topic.startswith("rutautp/cambios/"):
                receipt = self.route_changes.handle(message.topic, message.payload, time.time())
                if receipt and self.publisher:
                    principal, body = receipt
                    self.publisher(f"rutautp/cambios/{principal}/recibo", json.dumps(body))
                return
            self.handle_message(message.topic, message.payload, retained=bool(message.retain))

        client.on_message = on_message

        return client

    def _on_connect(
        self,
        client: Any,
        _userdata: Any,
        _flags: Any,
        reason_code: Any,
        _properties: Any = None,
    ) -> None:
        if int(getattr(reason_code, "value", reason_code)) != 0:
            logger.error("conexión rechazada por el broker: %s", reason_code)
            return

        logger.info("conectado; suscribiendo a %s", self.config.observations_topic)

        client.subscribe(self.config.observations_topic, qos=1)
        if self.simulation_control is not None:
            self.simulation_control.disconnected()  # reconectar exige otro PUBACK
        if self.config.simulation_ingress_enabled:
            client.subscribe(SIMULATION_OBSERVATIONS_TOPIC, qos=1)
        client.subscribe(REPORT_TOPIC, qos=1)
        if self.push:
            from .push_service import REGISTER_TOPIC
            client.subscribe(REGISTER_TOPIC, qos=1)
        self.route_changes.last_snapshot = float("-inf")
        client.subscribe(OCCUPANCY_REPORT_TOPIC, qos=1)
        self.occupancy.last_snapshot = float("-inf")

    def _on_disconnect(
        self,
        _client: Any,
        _userdata: Any,
        _flags: Any = None,
        reason_code: Any = None,
        _properties: Any = None,
    ) -> None:
        if self.simulation_control is not None:
            self.simulation_control.disconnected()
        if int(getattr(reason_code, "value", reason_code) or 0) != 0:
            logger.warning("desconectado del broker: %s", reason_code)
        else:
            logger.info("desconectado del broker")
