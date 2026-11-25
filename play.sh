#!/bin/sh
# Avvia il gioco in finestra (senza editor).
cd "$(dirname "$0")" || exit 1
exec godot --path . "$@"
