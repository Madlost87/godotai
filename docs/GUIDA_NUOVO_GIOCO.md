# Guida: creare un gioco nuovo

## 1. Crealo dal modello

```sh
git switch -c gioco/<id>          # un ramo per gioco
./new_game.sh <id> "Titolo"       # es. ./new_game.sh bastone "Bastone"
./check.sh                        # deve essere già verde
```

Ottieni `games/<id>/` con un gioco funzionante (tocca il bersaglio) da trasformare:

```
games/<id>/
  game.json            descrizione, giocatori, capacità richieste
  <id>.tscn            scena principale
  <id>_game.gd         logica: extends BodyGame
  tests/<id>_test.gd   test headless
```

Il gioco compare da solo nel menu (`launcher/`): non c'è nessun elenco da aggiornare.

## 2. Descrivilo in `game.json`

```json
{
  "id": "bastone",
  "title": "Bastone",
  "description": "Una o due frasi: compaiono sulla scheda del menu.",
  "controls": "Come si gioca, in breve.",
  "scene": "bastone.tscn",
  "players": {"min": 1, "max": 2},
  "requires": ["pose"],
  "optional": ["hands"]
}
```

- `players.max` viene chiesto al tracker all'avvio del gioco: MediaPipe cerca solo
  quelle persone, e chi passa dietro non diventa un giocatore.
- `requires`: capacità senza cui il gioco non funziona. Il menu avvisa se il sensore
  collegato non le ha. Capacità: `pose` (scheletro), `hands` (dettaglio delle mani),
  `face`, `markers` (marker colorati), `effectors` (punti che toccano: mani o contatti).
- **Preferisci `effectors` a giunture specifiche** quando basta "toccare": così il
  gioco funziona anche con un LiDAR o un altro sensore senza scheletro.

## 3. Scrivi la logica

```gdscript
extends BodyGame

func _game_ready() -> void:      # al posto di _ready()
    ...
```

`BodyGame` legge `game.json`, manda la sessione al tracker, gestisce Esc (torna al menu)
e offre `manifest` e `missing_capabilities()`. Se ridefinisci `_ready()` o `_exit_tree()`
chiama `super()`.

Pezzi pronti in `core/`:

| Serve… | Usa |
|---|---|
| far toccare oggetti al corpo | `BodyColliders` nella scena + `collision_mask = BodyColliders.BODY_LAYER` sugli oggetti; `BodyColliders.owner_of(area)` dice chi ha toccato |
| il braccio come bastone | `BodyColliders.forearms = true` (rettangoli sugli avambracci, con `velocity`) |
| un gesto come pulsante | `GestureController` (braccio alzato, braccia aperte…) → azione dell'Input Map |
| un "clic" tenendo ferma la mano | `DwellTarget` |
| misure del corpo | `BodyMetrics`: `arm_raised`, `torso_lean`, `arms_spread`, `arm_angle`, `effectors`; `BodyMetrics.Baseline` per accovacciarsi/saltare |
| vedere cosa vede il sensore | `BodyDebugDraw` (anche in trasparenza, con `modulate`) |
| i dati grezzi | `BodyInput.get_players()`, `PlayerState.point("wrist_r")`, segnali `player_entered` / `player_lost` |

Regole:
- **Input solo da azioni dell'Input Map**, mai tasti cablati: aggiungile in `project.godot`.
- **Misure in proporzione allo schermo** (es. `get_viewport_rect().size.y * 0.08`), non
  in pixel: si proietta a risoluzioni diverse.
- **Colori**: evita rosso, blu e giallo saturi (sono i colori dei marker).
- Niente `class_name` nei giochi (evita conflitti tra giochi); le classi condivise vanno in `core/`.
- Se un pezzo serve a più giochi, spostalo in `core/` con il suo test in `tests/`.

## 4. Testalo

Il test del modello mostra lo schema: si mandano pacchetti finti a `BodyInput` e si
controlla lo stato del gioco. Note:
- con `godot -s` gli autoload non esistono in compilazione: le classi che usano
  `BodyInput` (`BodyColliders`, `GestureController`, il tuo gioco…) si caricano con
  `load()` invece di citarle per nome;
- la viewport headless è 64×64: posizioni e misure in proporzione;
- `tests/game_framework_test.gd` controlla da solo che ogni gioco abbia `game.json`
  valido, una scena che estende `BodyGame` e almeno un test.

## 5. Provalo

```sh
./play_body.sh --debug                         # menu + camera
./play_body.sh res://games/<id>/<id>.tscn      # direttamente il gioco
./play.sh res://games/<id>/<id>.tscn           # senza camera: il mouse simula una persona
./tracker.sh --synthetic 2                     # (altro terminale) persone finte
./tracker.sh --synthetic 1 --synthetic-kind contacts   # come un LiDAR: solo punti di contatto
```

## 6. Chiudi

`./check.sh` verde, commit sul ramo `gioco/<id>`, poi merge in `main`.
