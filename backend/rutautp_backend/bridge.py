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
from .metrics import Metrics
from .models import RejectReason
from .validation import ObservationValidator

logger = logging.getLogger(__name__)

# `(topico, carga_util)` -> nada. Se inyecta para poder capturar publicaciones.
Publisher = Callable[[str, str], None]

# Cada cuántos segundos se vuelca el resumen de contadores.
SUMMARY_INTERVAL_S = 60.0


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
    ) -> None:
        self.config = config
        self.feed = feed
        self.publisher = publisher
        self.validator = validator or ObservationValidator(feed, config)
        self.aggregator = aggregator or VehicleAggregator(config)
        self.metrics = metrics or Metrics()

        self._last_summary_at = 0.0

    # ── Un mensaje ────────────────────────────────────────────────────────

    def handle_message(
        self,
        topic: str,
        payload: bytes | str,
        now: float | None = None,
    ) -> HandleOutcome:
        """Procesa un mensaje entrante del broker."""
        now = time.time() if now is None else now

        self.metrics.record_received()

        self._warn_on_topic_mismatch(topic, payload)

        result = self.validator.validate(payload, now)

        if not result.ok:
            reason = result.reason or RejectReason.MALFORMED_JSON

            self.metrics.record_rejected(reason)

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

        published = self._publish_if_due(vehicle, now)

        return HandleOutcome(
            accepted=True,
            vehicle_id=vehicle.vehicle_id,
            created_vehicle=created,
            published=published,
        )

    def _publish_if_due(self, vehicle: Any, now: float) -> bool:
        """Publica el vehículo si le toca por ritmo."""
        if self.publisher is None:
            return False

        if not self.aggregator.should_publish(vehicle, now):
            return False

        self.publisher(
            self.config.vehicles_topic(vehicle.vehicle_id),
            vehicle.encode(),
        )

        self.aggregator.mark_published(vehicle, now)
        self.metrics.record_published()

        logger.debug(
            "publicado %s: %s", vehicle.vehicle_id, vehicle.to_vehicle_position()
        )

        return True

    def _warn_on_topic_mismatch(self, topic: str, payload: bytes | str) -> None:
        """Avisa si el tópico y el `sessionId` no concuerdan.

        No se rechaza: el `sessionId` del cuerpo es el que manda, y un cliente
        con un error de formato no debería perder datos por esto. Pero la
        discrepancia se registra porque suele indicar un cliente mal escrito.
        """
        try:
            body = json.loads(payload)
            session_id = str(body.get("sessionId", "")).strip()
        except (json.JSONDecodeError, UnicodeDecodeError, AttributeError):
            return

        if not session_id:
            return

        parts = topic.split("/")

        # `rutautp/observaciones/{sessionId}/posicion`
        if len(parts) >= 3 and parts[2] != session_id:
            logger.warning(
                "el tópico declara la sesión %r y el cuerpo %r",
                parts[2],
                session_id,
            )

    # ── Mantenimiento periódico ───────────────────────────────────────────

    def tick(self, now: float | None = None) -> int:
        """Caduca vehículos, libera estado y vuelca el resumen si toca."""
        now = time.time() if now is None else now

        expired = self.aggregator.expire(now)

        if expired:
            self.metrics.record_expired(len(expired))

            logger.info(
                "caducados %d vehículo(s): %s", len(expired), ", ".join(expired)
            )

        self.validator.prune(now)

        if now - self._last_summary_at >= SUMMARY_INTERVAL_S:
            self._last_summary_at = now

            self.metrics.log_summary(
                {
                    "vehicles": self.aggregator.vehicle_count,
                    "routes": self.aggregator.route_count,
                }
            )

        return len(expired)

    # ── Red ───────────────────────────────────────────────────────────────

    def run(self, publish: bool = True, tick_interval_s: float = 1.0) -> None:
        """Conecta al broker y atiende mensajes hasta que se interrumpa.

        Se usa `client.loop()` en el hilo principal en vez de `loop_start()`:
        así los mensajes se procesan en el mismo hilo que `tick()` y no hay
        estado compartido entre hilos.

        Con `publish=False` no se publica nada, aunque el publicador estuviera
        inyectado: es el modo de prueba contra un broker real.
        """
        import paho.mqtt.client as mqtt

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

        client.connect(self.config.host, self.config.port, keepalive=30)

        running = True

        def stop(signum: int, _frame: Any) -> None:
            nonlocal running
            running = False
            logger.info("señal %d recibida, cerrando", signum)

        previous_handlers: dict[int, Any] = {}

        for signum in (signal.SIGINT, signal.SIGTERM):
            previous_handlers[signum] = signal.signal(signum, stop)

        try:
            while running:
                client.loop(timeout=tick_interval_s)
                self.tick()
        finally:
            for signum, handler in previous_handlers.items():
                signal.signal(signum, handler)

            client.disconnect()

            self.metrics.log_summary(
                {
                    "vehicles": self.aggregator.vehicle_count,
                    "routes": self.aggregator.route_count,
                }
            )

    def _client_publisher(self, client: Any) -> Publisher:
        """Publicador que entrega al broker con QoS 1 y sin retención.

        Sin retención, a propósito: una posición vehicular es un dato perecedero
        y el cliente ya descarta lo que supera 45 s. Dejar el último mensaje
        retenido haría que un usuario que se conecta tarde viera un vehículo
        fantasma hasta que el saneador lo descartara.
        """

        def publish(topic: str, payload: str) -> None:
            info = client.publish(topic, payload, qos=1, retain=False)

            if info.rc != 0:
                logger.warning(
                    "no se pudo publicar en %s (rc=%s)", topic, info.rc
                )

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
