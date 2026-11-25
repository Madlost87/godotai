# Progetto Godot 4.7 (GDScript, renderer Compatibility)

Flusso di lavoro: l'utente descrive cosa vuole, Claude scrive i file direttamente
(scene `.tscn`, script `.gd`, `project.godot`) e verifica in headless. Non si usa
l'editor grafico né l'MCP Godot AI.

## Comandi
- `./check.sh` — verifica headless: import, avvio breve della scena principale, test in `tests/`. Eseguilo dopo ogni modifica e correggi gli errori prima di dire che hai finito.
- `./play.sh` — avvia il gioco in finestra per l'utente. Lancialo in background quando l'utente chiede di provare il gioco.
- `./play.sh res://tools/body_demo/body_demo.tscn` — demo dell'input corporeo (simulatore col mouse se il tracker non c'è).
- `./play_body.sh [scena] [opzioni tracker]` — tracker dalla webcam + gioco insieme (default: Bolle, `res://games/bubbles/bubbles.tscn`). Lancialo in background quando l'utente vuole giocare col corpo.
- `./tracker.sh --debug` — tracker del corpo dalla webcam, con finestra di debug. `--synthetic 2` = persone finte senza camera; `--help` per le opzioni. Ambiente Python in `tracker/.venv` (3.12, `uv`).
- Calibrazione: `./play.sh res://tools/calibration/calibration.tscn` (sul proiettore; `-- --windowed` per provarla in finestra) + `./tracker.sh --calibrate --debug`. Salva `tracker/calibration.json`.
- `./check.sh` esegue anche i test pytest del tracker (`tracker/tests`) e un test end-to-end Python → Godot.

## Struttura
- `scenes/main.tscn` — scena principale (`run/main_scene`).
- `scripts/` — script GDScript (tipizzati, tab per l'indentazione).
- `tests/` — test headless: script `extends SceneTree` che terminano con `quit(0)` se ok, `quit(1)` se falliscono.
- `addons/godot_ai/` — plugin Godot AI 4.4.2: non modificarlo.

## Input corporeo (in sviluppo)
Obiettivo: comandare giochi proiettati con marker colorati, braccia, mani e faccia
ripresi da webcam. Riferimento: **`docs/SPEC.md`** (architettura, protocollo UDP v1,
API `BodyInput`, fasi). Tracker Python in `tracker/` → UDP → autoload `BodyInput` →
controller → azioni Input Map. Leggi la spec prima di lavorare su questa parte e
aggiornala se cambiano le decisioni.

## Regole
- Input sempre tramite azioni dell'Input Map (es. `increment_counter` = Spazio), mai tasti cablati nel codice: l'utente le rimappa su un pulsante esterno.
- Solo risorse locali semplici (forme, Polygon2D, ColorRect, Label).
- Quando aggiungi una funzionalità, aggiungi o aggiorna un test in `tests/`.
- Se modifichi un `.tscn` a mano, mantieni coerenti gli id di `ext_resource`/`sub_resource`.
- Test headless: le classi che usano l'autoload `BodyInput` vanno caricate con `load()` negli script di test (con `-s` l'autoload non esiste ancora in compilazione); la viewport headless è 64×64, quindi misure in proporzione.
- Tracker Python: codice modulare. Nuove sorgenti, rilevatori, regole di assegnazione e uscite si aggiungono come classi registrate (`registry.py`) e si attivano da `tracker/config.json`, senza toccare la pipeline. Python tipizzato, 4 spazi.
