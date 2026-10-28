#!/usr/bin/env python3
"""Servicio explícito de presentación; no arranca nada al importar."""
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from simulation.presentation import main
if __name__ == '__main__':
    raise SystemExit(main())
