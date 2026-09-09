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
#   ./puente-demo.sh              # broker en esta máquina
#   ./puente-demo.sh 192.168.1.50 # broker en otra máquina de la red
#
set -euo pipefail

HOST="${1:-127.0.0.1}"

echo "[puente-demo] Escuchando rutautp/observaciones/# en $HOST ..."
echo "[puente-demo] Republicando a rutautp/vehiculos/baliza-*/posicion"

mosquitto_sub -h "$HOST" -t 'rutautp/observaciones/#' -v |
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

    mosquitto_pub -h "$HOST" \
        -t "rutautp/vehiculos/$vid/posicion" \
        -m "$body"

    echo "[puente-demo] $vid → $body"
done
