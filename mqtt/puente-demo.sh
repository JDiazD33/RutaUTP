#!/usr/bin/env bash
#
# puente-demo.sh — Puente de DEMOSTRACIÓN observaciones → vehiculos.
#
# Hasta que el equipo decida el backend definitivo, este script hace de
# puente mínimo viable: escucha las balizas del pasajero y las republica
# como posiciones vehiculares para que el mapa de los demás usuarios las
# dibuje. NO valida contra el shape GTFS ni agrupa pasajeros del mismo
# micro: es una demo, no la arquitectura final.
#
# Requisitos: mosquitto (brew install mosquitto) y python3.
#
# Uso:
#   ./puente-demo.sh                                   # broker local (1883)
#   ./puente-demo.sh 192.168.1.50                      # broker en otra máquina
#   MQTT_USER=observer MQTT_PASS='...' \
#     ./puente-demo.sh ce14c140....emqxsl.com 8883 --tls  # EMQX Cloud (TLS)
#
# Credenciales por variables de entorno MQTT_USER / MQTT_PASS (opcional;
# mejor como entorno que como argumento, para que no aparezcan en `ps`).
set -euo pipefail

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
