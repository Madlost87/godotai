#!/bin/sh
# Crea un gioco nuovo in games/<id>/ partendo dal modello games/_template.
# Uso:    ./new_game.sh <id> "<Titolo>"
# Esempio: ./new_game.sh bastone "Bastone"
# Poi: modifica games/<id>/game.json, la scena e lo script; ./check.sh lo prova; il
# gioco compare da solo nel menu.
set -e
cd "$(dirname "$0")" || exit 1

id="$1"
title="$2"
if [ -z "$id" ] || [ -z "$title" ]; then
	echo 'Uso: ./new_game.sh <id> "<Titolo>"   (es. ./new_game.sh bastone "Bastone")'
	exit 1
fi
if ! echo "$id" | grep -Eq '^[a-z][a-z0-9_]*$'; then
	echo "id non valido: '$id' — solo minuscole, cifre e _, e deve iniziare con una lettera"
	exit 1
fi
if [ -e "games/$id" ]; then
	echo "games/$id esiste già"
	exit 1
fi

dir="games/$id"
cp -r games/_template "$dir"
find "$dir" -name "*.uid" -delete   # Godot ne genera di nuovi: copiati sarebbero duplicati
mv "$dir/game.tscn" "$dir/$id.tscn"
mv "$dir/game.gd" "$dir/${id}_game.gd"
mv "$dir/tests/game_test.gd" "$dir/tests/${id}_test.gd"

title_sed=$(printf '%s' "$title" | sed 's/[\\|&]/\\&/g')
# Porta di controllo diversa per ogni gioco, così i test non si scontrano.
port=$((42441 + $(ls -d games/*/ | wc -l)))
find "$dir" -type f \( -name "*.gd" -o -name "*.tscn" -o -name "*.json" -o -name "*.md" \) -exec sed -i \
	-e "s|res://games/_template/|res://games/$id/|g" \
	-e "s|\"id\": \"_template\"|\"id\": \"$id\"|" \
	-e "s|Nuovo gioco|$title_sed|g" \
	-e "s|game\\.tscn|$id.tscn|g" \
	-e "s|game\\.gd|${id}_game.gd|g" \
	-e "s|game_test\\.gd|${id}_test.gd|g" \
	-e "s|CONTROL_PORT := 42440|CONTROL_PORT := $port|" \
	{} +

echo "Creato $dir:"
find "$dir" -type f | sort | sed 's/^/  /'
echo
echo "Prossimi passi:"
echo "  1. descrivi il gioco in $dir/game.json (giocatori, capacità richieste)"
echo "  2. scrivi la logica in $dir/${id}_game.gd e la scena $dir/$id.tscn"
echo "  3. aggiungi i test in $dir/tests/${id}_test.gd"
echo "  4. ./check.sh   — poi ./play_body.sh res://$dir/$id.tscn per provarlo"
