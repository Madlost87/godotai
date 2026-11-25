#!/bin/sh
# Avvia il tracker (webcam) in background e il menu dei giochi (o una scena precisa),
# a schermo intero; chiude il tracker quando Godot esce.
# Uso: ./play_body.sh [res://scena] [--windowed] [--screen N] [opzioni del tracker...]
#   ./play_body.sh                                   → menu dei giochi, schermo intero
#   ./play_body.sh --debug                           → + finestra della camera
#   ./play_body.sh --screen 1                        → sul secondo monitor (es. proiettore)
#   ./play_body.sh --windowed                        → in finestra
#   ./play_body.sh res://games/tris/tris.tscn        → direttamente un gioco
# In gioco: F11 passa da schermo intero a finestra, Esc torna al menu.
cd "$(dirname "$0")" || exit 1
scene=""
godot_args=""
tracker_args=""
while [ $# -gt 0 ]; do
	case "$1" in
		res://*) scene="$1" ;;
		--windowed) godot_args="$godot_args --windowed" ;;
		--screen) shift; godot_args="$godot_args --screen=$1" ;;
		--screen=*) godot_args="$godot_args $1" ;;
		*) tracker_args="$tracker_args $1" ;;
	esac
	shift
done
# shellcheck disable=SC2086
./tracker.sh $tracker_args &
tracker_pid=$!
trap 'kill "$tracker_pid" 2>/dev/null' EXIT INT TERM
# shellcheck disable=SC2086
godot --path . $scene -- $godot_args
