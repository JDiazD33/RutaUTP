# Imagen del puente para el perfil de despliegue (mqtt/compose.prod.yaml).
#
# Deliberadamente mínima: el servicio solo necesita Python y `paho-mqtt`. El
# feed GTFS no se copia aquí, se monta desde el repositorio (`../gtfs`) para
# que app y backend validen contra la misma geometría.
#
# `PYTHONUNBUFFERED` importa: sin él, Docker retiene la salida en un búfer y el
# registro aparece a ráfagas, justo cuando más hace falta verlo.
#
# Construir desde la raíz de `backend/`:
#   docker build -t rutautp-backend backend/

FROM python:3.12-slim

WORKDIR /app

# Las dependencias primero: así la capa se reutiliza mientras no cambie
# `requirements.txt`.
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY rutautp_backend ./rutautp_backend

ENV PYTHONUNBUFFERED=1
ENV GTFS_DIR=/gtfs
ENV BACKEND_DB_PATH=/data/rutautp.sqlite
ENV BACKEND_HEALTH_FILE=/data/health.json

# Sin privilegios: el servicio solo lee el feed y escribe en /data.
RUN useradd --system --create-home --uid 10001 rutautp \
    && mkdir -p /data \
    && chown -R rutautp:rutautp /data
USER rutautp

CMD ["python", "-m", "rutautp_backend"]
