#!/bin/sh
# Apre il progetto nell'editor Godot partendo dalla sua cartella
# (così "Configure" di Godot AI scrive .mcp.json qui, con scope "project").
cd "$(dirname "$0")" || exit 1
exec godot --editor --path . "$@"
