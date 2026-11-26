# Giochi proiettati comandati dal corpo — Godot 4.7 (GDScript, Compatibility) + tracker Python

Flusso di lavoro: l'utente descrive cosa vuole, Claude scrive i file direttamente
(scene `.tscn`, script `.gd`, `project.godot`, Python) e verifica in headless. Non si usa
l'editor grafico né l'MCP Godot AI. Panoramica: `README.md`. Riferimento tecnico:
**`docs/SPEC.md`** (leggilo prima di toccare input, protocollo o tracker; aggiornalo se
cambiano le decisioni). Guide: `docs/GUIDA_NUOVO_GIOCO.md`, `docs/GUIDA_NUOVO_SENSORE.md`.

## Comandi
- `./check.sh` — verifica completa: import Godot, avvio del menu, test Godot (`tests/`, `games/*/tests/`, `tools/*/tests/`, `examples/*/tests/`, 120 s max ciascuno), pytest del tracker. Eseguilo dopo ogni modifica; deve essere verde prima di dire che hai finito.
- `./play_body.sh [res://scena] [--windowed] [--screen N] [opzioni tracker]` — tracker dalla webcam + menu dei giochi (o la scena indicata), a schermo intero. `--debug` mostra la camera. Lancialo in background quando l'utente vuole giocare. F11 in gioco: finestra/schermo intero.
- `./play.sh [res://scena]` — solo Godot (senza tracker il mouse simula una persona).
- `./new_game.sh <id> "Titolo"` — crea `games/<id>/` dal modello `games/_template/`.
- Registrare e misurare il movimento: `./tracker.sh --record recordings/session_x.jsonl` (anche via `./play_body.sh`), poi `tracker/.venv/bin/python -m tracker.tools.analyze_recording recordings/session_x.jsonl`. Lavoro aperto: docs/SPEC.md §10.2.
- `./tracker.sh` — tracker: `--debug`, `--record`, `--mapping body_zone|mirror|stretch|homography|auto`, `--synthetic N [--synthetic-kind contacts]` (persone finte / finto LiDAR), `--source`, `--detectors`, `--list-plugins`, `--calibrate`, `--help`. Ambiente in `tracker/.venv` (Python 3.12, `uv`).
- Calibrazione: `./play.sh res://tools/calibration/calibration.tscn` (sul proiettore; `-- --windowed` in finestra) + `./tracker.sh --calibrate --debug`.

## Struttura
- `core/` — framework riusabile, non legato a giochi o sensori: `body_input/` (autoload `BodyInput`), `body/` (`BodyMetrics`, `BodyColliders`, `BodyDebugDraw`), `controllers/` (`GestureController`, `DwellTarget`), `game/` (`BodyGame`, `GameManifest`, `GameRegistry`). Test in `tests/`.
- `games/<id>/` — un gioco per cartella: `game.json`, scena, script (`extends BodyGame`), `tests/`. `games/_template/` è il modello (non è un gioco, ma è testato).
- `launcher/` — menu, scena principale; trova i giochi da solo.
- `tools/` — calibrazione, demo del corpo. `examples/` — demo iniziale (contatore).
- `tracker/` — Python a plugin: `sources/`, `detectors/` (si registrano da soli), `identity.py`, `protocol.py` (contratto v1 + `validate_packet`), `sinks.py`, `calibration.py`, `control.py`.
- `data/` — file condivisi Godot/Python (pattern ArUco). `docs/` — spec e guide.
- `addons/godot_ai/` — plugin Godot AI 4.4.2: non modificarlo.

## Regole
- **Schermo**: i giochi disegnano in proporzione alla viewport (schermo intero, qualsiasi rapporto). La corrispondenza corpo → schermo è del tracker (mappatura `body_zone` senza proiettore, `homography` con il proiettore calibrato), non dei giochi. Per controlli visivi usa una cattura della viewport (`get_viewport().get_texture().get_image()`), non `--write-movie` (su schermi HiDPI taglia l'alto).
- **Giochi indipendenti dal sensore**: usano capacità (`pose`, `hands`, `face`, `markers`, `effectors`) dichiarate in `game.json` ed effettori (`BodyMetrics.effectors`, `BodyColliders`), non dettagli del tracker. Quando basta "toccare", usa gli effettori.
- **Gioco nuovo**: sempre con `./new_game.sh`, su un ramo `gioco/<id>`. Script principale `extends BodyGame`, inizializzazione in `_game_ready()`. Niente `class_name` nei giochi; ciò che serve a più giochi va in `core/` con un test.
- **Sensore nuovo**: plugin in `tracker/sources/` + `tracker/detectors/` (con `produces` / `accepts` / `provides`), oppure un altro programma che parla il protocollo v1. Non cambiare il protocollo senza aggiornare `protocol.py`, `validate_packet`, `PlayerState` e la spec.
- Input sempre tramite azioni dell'Input Map (rimappabili su pulsanti esterni), mai tasti cablati.
- Solo risorse locali semplici (forme, Polygon2D, ColorRect, Label). Misure in proporzione allo schermo. Nei giochi evita rosso, blu e giallo saturi (colori dei marker).
- Ogni funzionalità ha un test; ogni gioco ha almeno un test in `games/<id>/tests/` (lo verifica `tests/game_framework_test.gd`).
- Test headless: con `godot -s` gli autoload non esistono in compilazione, quindi le classi che usano `BodyInput` si caricano con `load()`; la viewport headless è 64×64, quindi misure in proporzione.
- Se modifichi un `.tscn` a mano, mantieni coerenti gli id di `ext_resource`/`sub_resource`. Spostando script, sposta anche i `.uid`.
- GDScript tipizzato, tab. Python tipizzato, 4 spazi.
- Git: `main` sempre verde; remoto `origin` = GitHub. Non committare `tracker/.venv`, modelli, `.godot/`, registrazioni personali (vedi `.gitignore`).
