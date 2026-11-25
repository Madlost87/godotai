#!/bin/sh
# Avvia il tracker (webcam) in background e il menu dei giochi (o una scena precisa);
# chiude il tracker quando Godot esce.
# Uso: ./play_body.sh [scena] [opzioni del tracker...]
#   ./play_body.sh                                   → menu dei giochi
#   ./play_body.sh --debug                           → menu + finestra della camera
#   ./play_body.sh res://games/bubbles/bubbles.tscn  → direttamente Bolle
cd "$(dirname "$0")" || exit 1
scene=""
case "$1" in res://*) scene="$1"; shift ;; esac
./tracker.sh "$@" &
tracker_pid=$!
trap 'kill "$tracker_pid" 2>/dev/null' EXIT INT TERM
godot --path . $scene
