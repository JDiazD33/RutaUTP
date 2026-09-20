#!/usr/bin/env bash
#
# puente-demo.sh — Puente de DEMOSTRACIÓN observaciones → vehiculos.
#
# ┌──────────────────────────────────────────────────────────────────────┐
# │ NO VALIDA NADA. Es un script de prueba, no la arquitectura final.    │
# └──────────────────────────────────────────────────────────────────────┘
#
# Republica TODO lo que llega a `observaciones/#` como si fuera una posición
# vehicular, sin comprobar el esquema, ni las coordenadas, ni que el punto
# caiga sobre el recorrido, ni el ritmo de publicación, y sin agrupar a los
# pasajeros que van en el mismo bus.
#
# Consecuencia de seguridad: la ACL impide que el usuario `observer` publique
# en `vehiculos/#`, pero SÍ puede escribir en `observaciones/#` con cualquier
# `sessionId`. Mientras este script esté corriendo, cualquier cliente
# autenticado puede **suplantar vehículos** ante todos los usuarios. Por eso
# exige una confirmación explícita para arrancar.
#
# Para el puente de verdad, con validación contra el GTFS y agrupación por
# unidad, usar `backend/` (ver `backend/README.md`). Este script se conserva
# porque es una prueba de humo de 60 líneas que solo necesita mosquitto y
# python3, sin dependencias que instalar.
#
# Requisitos: mosquitto (brew install mosquitto) y python3.
#
# Uso:
#   PUENTE_DEMO_INSECURE=1 ./puente-demo.sh                 # broker local
#   PUENTE_DEMO_INSECURE=1 ./puente-demo.sh 192.168.1.50    # otra máquina
#   PUENTE_DEMO_INSECURE=1 MQTT_USER=observer MQTT_PASS='...' \
#     ./puente-demo.sh ce14c140....emqxsl.com 8883 --tls    # EMQX Cloud (TLS)
#
# Credenciales por variables de entorno MQTT_USER / MQTT_PASS (opcional;
# mejor como entorno que como argumento, para que no aparezcan en `ps`).
set -euo pipefail

# Salvaguarda: sin esto, un copiar y pegar arrancaría un puente que permite
# suplantar vehículos sin que nadie se diera cuenta.
if [ "${PUENTE_DEMO_INSECURE:-}" != "1" ]; then
    cat >&2 <<'AVISO'

  ┌────────────────────────────────────────────────────────────────────┐
  │  puente-demo.sh NO VALIDA NADA                                     │
  └────────────────────────────────────────────────────────────────────┘

  Republica como posición vehicular todo lo que entre en
  `rutautp/observaciones/#`, sin comprobar el esquema, las coordenadas, la
  distancia al recorrido ni el ritmo de publicación.

  Mientras esté corriendo, cualquier cliente autenticado puede suplantar
  vehículos ante el resto de usuarios.

  Para el puente real, con validación contra el GTFS y agrupación por unidad:

      cd backend && python -m rutautp_backend

  Si aun así lo quieres para una prueba puntual, arranca con:

      PUENTE_DEMO_INSECURE=1 ./puente-demo.sh

AVISO
    exit 1
fi

HOST="${1:-127.0.0.1}"
PORT="${2:-1883}"
TLSARGS=""
AUTHARGS=""

if [ "${3:-}" = "--tls" ]; then
    TLSARGS="--cafile /etc/ssl/cert.pem"
fi

if [ -n "${MQTT_USER:-}" ]; then
    AUTHARGS="-u ${MQTT_USER} -P ${MQTT_PASS:-}"
fi

echo "[puente-demo] Escuchando rutautp/observaciones/# en $HOST:$PORT ..."
echo "[puente-demo] Republicando a rutautp/vehiculos/baliza-*/posicion"

mosquitto_sub -h "$HOST" -p "$PORT" $TLSARGS $AUTHARGS -t 'rutautp/observaciones/#' -v |
while read -r _topic payload; do
    json=$(printf '%s' "$payload" | python3 -c '
import sys, json
m = json.loads(sys.stdin.read())
vid = "baliza-" + str(m.get("sessionId", "s/i"))[:8]
print(vid + "\t" + json.dumps({
    "vehicleId": vid,
    "linea": m.get("linea", ""),
    "lat": m.get("lat", 0),
    "lon": m.get("lon", 0),
    "speed": m.get("speed", -1),
    "heading": m.get("heading", -1),
    "timestamp": m.get("timestamp", 0),
}))')

    vid="${json%%$'\t'*}"
    body="${json#*$'\t'}"

    mosquitto_pub -h "$HOST" -p "$PORT" $TLSARGS $AUTHARGS \
        -t "rutautp/vehiculos/$vid/posicion" \
        -m "$body"

    echo "[puente-demo] $vid → $body"
done
