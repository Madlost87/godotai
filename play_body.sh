#!/bin/sh
# Avvia il tracker (webcam) in background e un gioco; chiude il tracker quando il gioco esce.
# Uso: ./play_body.sh [scena] [opzioni del tracker...]
#   ./play_body.sh                                  → Bolle
#   ./play_body.sh res://tools/body_demo/body_demo.tscn --debug
cd "$(dirname "$0")" || exit 1
scene="res://games/bubbles/bubbles.tscn"
case "$1" in res://*) scene="$1"; shift ;; esac
./tracker.sh "$@" &
tracker_pid=$!
trap 'kill "$tracker_pid" 2>/dev/null' EXIT INT TERM
godot --path . "$scene"
