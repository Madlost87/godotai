#!/bin/sh
# Avvia il tracker del corpo (Python) che manda i dati a Godot via UDP.
# Esempi: ./tracker.sh --debug     ./tracker.sh --list-cameras     ./tracker.sh --help
cd "$(dirname "$0")" || exit 1
if [ ! -x tracker/.venv/bin/python ]; then
	echo "Ambiente mancante. Crealo con:"
	echo "  uv venv --python 3.12 tracker/.venv && uv pip install --python tracker/.venv/bin/python -r tracker/requirements.txt"
	exit 1
fi
exec tracker/.venv/bin/python -m tracker "$@"
