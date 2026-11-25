# Giochi proiettati comandati dal corpo

Giochi Godot 4.7 (GDScript) proiettati su muro, pavimento o tavolo, comandati dal corpo
dei giocatori: una camera (oggi una webcam, domani un LiDAR o un altro sensore) vede le
persone e un tracker Python manda a Godot dove sono mani, busto, faccia o punti di contatto.

```
sensore ──► tracker/ (Python, plugin) ──UDP, protocollo v1──► core/ (Godot) ──► games/<id>/
             sorgente → rilevatori                              BodyInput, BodyMetrics,
             → identità → pacchetto                             BodyColliders, controller
```

## Avvio rapido

```sh
./play_body.sh --debug     # tracker dalla webcam + menu dei giochi (+ finestra della camera)
./play.sh                  # solo Godot: senza tracker, il mouse simula una persona
./check.sh                 # tutti i test (Godot headless + pytest del tracker)
./new_game.sh <id> "Titolo"   # crea un gioco nuovo dal modello
```

Prima volta: ambiente Python per il tracker (Python 3.12, con [uv](https://docs.astral.sh/uv/)):

```sh
uv venv --python 3.12 tracker/.venv
uv pip install --python tracker/.venv/bin/python -r tracker/requirements.txt
```

I modelli MediaPipe si scaricano da soli al primo avvio in `tracker/models/`.

## Struttura

| Cartella | Cosa contiene |
|---|---|
| `core/` | Framework Godot riusabile, non legato a nessun gioco né sensore |
| `core/body_input/` | `BodyInput` (autoload): riceve i pacchetti, filtra, simulatore, registrazione/replay |
| `core/body/` | `BodyMetrics` (braccio alzato, busto, effettori…), `BodyColliders`, `BodyDebugDraw` |
| `core/controllers/` | `GestureController` (gesto → azione dell'Input Map), `DwellTarget` (selezione con la mano ferma) |
| `core/game/` | `BodyGame` (base dei giochi), `GameManifest` (`game.json`), `GameRegistry` |
| `games/<id>/` | Un gioco: `game.json`, scena, script, `tests/` |
| `games/_template/` | Modello usato da `new_game.sh` (anche lui testato) |
| `launcher/` | Menu dei giochi (scena principale): li trova da solo |
| `tools/` | Calibrazione proiettore↔camera, demo del corpo |
| `tracker/` | Tracker Python a plugin: `sources/`, `detectors/`, identità, protocollo, uscite |
| `tests/` | Test del core e di integrazione (anche Python ↔ Godot) |
| `docs/` | Specifica e guide |
| `examples/` | Demo iniziale (contatore), solo come esempio |

## Guide

- [Nuovo gioco](docs/GUIDA_NUOVO_GIOCO.md): dal modello al menu, con test.
- [Nuovo sensore](docs/GUIDA_NUOVO_SENSORE.md): LiDAR, camera di profondità o altro, senza rompere i giochi.
- [Specifica](docs/SPEC.md): architettura, protocollo v1, fasi, prestazioni misurate.

## Principi

1. **I giochi non conoscono il sensore.** Usano capacità (`pose`, `hands`, `face`,
   `markers`, `effectors`) ed effettori ("i punti che toccano"), dichiarati in `game.json`.
2. **Il protocollo v1 è il contratto.** Qualsiasi programma che lo parla
   (`tracker/protocol.py: validate_packet`) può sostituire il tracker.
3. **Plugin, non modifiche.** Sorgenti, rilevatori, regole di assegnazione, uscite,
   metodi di calibrazione e giochi si aggiungono con un file o una cartella nuova: si
   registrano da soli.
4. **Input solo da azioni dell'Input Map** (rimappabili su pulsanti esterni).
5. **Ogni pezzo ha i suoi test**, e `./check.sh` deve restare verde.
