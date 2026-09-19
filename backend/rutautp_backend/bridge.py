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
from dataclasses import dataclass
from typing import Any, Callable

from .aggregation import VehicleAggregator
from .config import Config
from .gtfs import GtfsFeed
from .health import remove_heartbeat, write_heartbeat
from .metrics import Metrics
from .models import RejectReason
from .persistence import ObservationStore, open_store
from .validation import ObservationValidator

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
    ) -> None:
        self.config = config
        self.feed = feed
        self.publisher = publisher
        self.validator = validator or ObservationValidator(feed, config)
        # El feed se pasa al agregador para que conozca la longitud de cada
        # recorrido: es lo que convierte una diferencia de `progress` en metros.
        self.aggregator = aggregator or VehicleAggregator(config, feed)
        self.metrics = metrics or Metrics()
        self.store = store or open_store(
            config.database_path, config.retention_days
        )

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
            return self._handle(topic, payload, now)
        except Exception:  # noqa: BLE001 - barrera deliberada de último recurso
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

    def _handle(
        self,
        topic: str,
        payload: bytes | str,
        now: float,
    ) -> HandleOutcome:
        # Esta barrera debe estar antes de `_session_mismatch`: ese método
        # decodifica el JSON para comparar la sesión del cuerpo con la del
        # tópico. Si se confiara únicamente en el límite del validador, un
        # mensaje enorme ya se habría parseado una vez antes de ser rechazado,
        # anulando la protección de memoria y CPU.
        if len(payload) > self.config.max_message_bytes:
            detail = (
                f"{len(payload)} bytes > "
                f"{self.config.max_message_bytes}"
            )

            self.metrics.record_rejected(RejectReason.MESSAGE_TOO_LARGE)
            self.store.record_rejection(
                RejectReason.MESSAGE_TOO_LARGE,
                detail,
                now,
            )

            return HandleOutcome(
                accepted=False,
                reason=RejectReason.MESSAGE_TOO_LARGE,
                detail=detail,
            )

        topic_identity = self._topic_identity(topic)

        if topic_identity is None:
            mismatch = (
                "el tópico debe tener la forma "
                "rutautp/observaciones/{principal}/{sessionId}/posicion"
            )
        else:
            _, topic_session = topic_identity
            mismatch = self._session_mismatch(topic_session, payload)

        if mismatch is not None:
            self.metrics.record_rejected(RejectReason.SESSION_MISMATCH)
            self.store.record_rejection(
                RejectReason.SESSION_MISMATCH, mismatch, now
            )

            logger.warning("descartada (session_mismatch): %s", mismatch)

            return HandleOutcome(
                accepted=False,
                reason=RejectReason.SESSION_MISMATCH,
                detail=mismatch,
            )

        assert topic_identity is not None
        principal, _ = topic_identity
        result = self.validator.validate(payload, now, principal=principal)

        if not result.ok:
            reason = result.reason or RejectReason.MALFORMED_JSON

            self.metrics.record_rejected(reason)
            self.store.record_rejection(reason, result.detail, now)

            logger.debug(
                "descartada (%s): %s", reason.value, result.detail or "sin detalle"
            )

            return HandleOutcome(
                accepted=False, reason=reason, detail=result.detail
            )

        observation = result.observation
        assert observation is not None

        self.metrics.record_accepted()

        vehicle, created = self.aggregator.ingest(observation, now)

        if created:
            self.metrics.record_created()

            logger.info(
                "vehículo %s creado (línea %s, ruta %s)",
                vehicle.vehicle_id,
                vehicle.linea,
                vehicle.route_id,
            )

        self.store.record_observation(observation, vehicle.vehicle_id, now)

        published = self._publish_if_due(vehicle, now, now)

        return HandleOutcome(
            accepted=True,
            vehicle_id=vehicle.vehicle_id,
            created_vehicle=created,
            published=published,
        )

    def _publish_if_due(
        self, vehicle: Any, now: float, wall_clock: float
    ) -> bool:
        """Publica el vehículo si le toca por ritmo.

        Solo se marca como publicado cuando el broker acepta el mensaje. Si no,
        no se actualiza `last_published_at`, así que la siguiente observación
        vuelve a intentarlo sin esperar al intervalo completo. El reintento está
        limitado por la llegada de observaciones, no por un bucle propio.
        """
        if self.publisher is None:
            return False

        if not self.aggregator.should_publish(vehicle, now):
            return False

        self.metrics.record_publish_attempt()

        topic = self.config.vehicle_topic(vehicle.vehicle_id)

        try:
            accepted = self.publisher(topic, vehicle.encode())
        except Exception:  # noqa: BLE001 - un publicador roto no debe tumbar el puente
            self.metrics.record_publish_failed()
            logger.exception("el publicador lanzó una excepción para %s", topic)
            return False

        if not accepted:
            self.metrics.record_publish_failed()
            logger.warning(
                "el broker no aceptó la posición de %s; se reintentará con la "
                "próxima observación",
                vehicle.vehicle_id,
            )
            return False

        self.aggregator.mark_published(vehicle, now)
        self.metrics.record_published()
        self.store.record_vehicle(vehicle, wall_clock)

        self._last_publish_at = wall_clock

        logger.debug(
            "publicado %s: %s", vehicle.vehicle_id, vehicle.to_vehicle_position()
        )

        return True

    @staticmethod
    def _topic_identity(topic: str) -> tuple[str, str] | None:
        """Extrae el principal autenticado y la sesión del tópico canónico."""
        parts = topic.split("/")

        if len(parts) != 5:
            return None

        if parts[0:2] != ["rutautp", "observaciones"]:
            return None

        if parts[4] != "posicion" or not parts[2] or not parts[3]:
            return None

        return parts[2], parts[3]

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

        session_id = str(body.get("sessionId", "")).strip()

        if not session_id:
            return None

        if topic_session != session_id:
            return (
                f"el tópico declara {topic_session!r} y el cuerpo {session_id!r}"
            )

        return None

    # ── Mantenimiento periódico ───────────────────────────────────────────

    def tick(self, now: float | None = None, connected: bool | None = None) -> int:
        """Caduca vehículos, libera estado, late y vuelca el resumen si toca.

        `connected` es el estado real del cliente MQTT. Se inyecta en lugar de
        consultarlo aquí porque `Bridge` no conoce paho: así el latido se puede
        probar sin abrir un socket.
        """
        now = time.time() if now is None else now

        expired = self.aggregator.expire(now)

        if expired:
            self.metrics.record_expired(len(expired))

            logger.info(
                "caducados %d vehículo(s): %s", len(expired), ", ".join(expired)
            )

        self.validator.prune(now)

        # Una transacción por segundo en lugar de una por mensaje: cada `commit`
        # fuerza un `fsync` y hacerlo por mensaje limitaría el caudal.
        self.store.flush()
        self.store.prune(now)

        self._write_heartbeat(now, connected)

        if now - self._last_summary_at >= SUMMARY_INTERVAL_S:
            self._last_summary_at = now

            self.metrics.log_summary(
                {
                    "vehicles": self.aggregator.vehicle_count,
                    "routes": self.aggregator.route_count,
                    **self.store.counts.as_dict(),
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
            "vehicles": self.aggregator.vehicle_count,
            "routes": self.aggregator.route_count,
            "lastPublishAt": self._last_publish_at or None,
        }

        if connected is not None:
            payload["connected"] = connected

        write_heartbeat(self.config.health_file, payload)

    # ── Red ───────────────────────────────────────────────────────────────

    def run(self, publish: bool = True, tick_interval_s: float = 1.0) -> None:
        """Conecta al broker y atiende mensajes hasta que se interrumpa.

        Se usa `client.loop()` en el hilo principal en vez de `loop_start()`:
        así los mensajes se procesan en el mismo hilo que `tick()` y no hay
        estado compartido entre hilos.

        Con `publish=False` no se publica nada, aunque el publicador estuviera
        inyectado: es el modo de prueba contra un broker real.

        **La conexión se mantiene sola.** El bucle comprueba el estado real del
        cliente y reconecta con espera progresiva, en lugar de dar por hecho que
        `loop()` la restablece. Antes, un corte del broker dejaba el servicio
        desconectado para siempre y sin decir nada.
        """
        import paho.mqtt.client as mqtt

        if tick_interval_s <= 0:
            raise ValueError("tick_interval_s debe ser mayor que cero")

        client = self._build_client(mqtt)

        if not publish:
            self.publisher = None
            logger.info("publicación desactivada: nada saldrá hacia vehiculos/")
        elif self.publisher is None:
            self.publisher = self._client_publisher(client)

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

        def on_message(_client: Any, _userdata: Any, message: Any) -> None:
            self.handle_message(message.topic, message.payload)

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

    def _on_disconnect(
        self,
        _client: Any,
        _userdata: Any,
        _flags: Any = None,
        reason_code: Any = None,
        _properties: Any = None,
    ) -> None:
        if int(getattr(reason_code, "value", reason_code) or 0) != 0:
            logger.warning("desconectado del broker: %s", reason_code)
        else:
            logger.info("desconectado del broker")
