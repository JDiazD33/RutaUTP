#!/usr/bin/env python3
"""Arranca el backend usando deploy/backend.env, sin ejecutar su contenido."""
import argparse
import os
from pathlib import Path
import sys

BACKEND_DIR = Path(__file__).resolve().parents[1]


def load_environment(path):
    environment = dict(os.environ)
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        key, separator, value = line.partition("=")
        key = key.strip()
        if not separator or not key.startswith(("MQTT_", "BACKEND_", "GTFS_")):
            raise ValueError("Formato inválido: utiliza una variable KEY=value por línea.")
        # Contraseñas literales: no interpolar $, #, comillas ni comandos.
        environment[key] = value
    for key in ("MQTT_HOST", "MQTT_USERNAME", "MQTT_PASSWORD"):
        if not environment.get(key):
            raise ValueError(f"Falta completar {key} en el archivo local de configuración.")
    return environment


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=BACKEND_DIR / "deploy/backend.env")
    args, backend_args = parser.parse_known_args()
    try:
        environment = load_environment(args.config)
    except (OSError, ValueError) as error:
        parser.exit(2, f"No se inició el backend: {error}\n")
    os.chdir(BACKEND_DIR)
    os.execve(sys.executable, [sys.executable, "-m", "rutautp_backend", *backend_args], environment)


if __name__ == "__main__":
    main()
