# Spec — Input corporeo per giochi proiettati

Versione 0.7 — 2026-11-25 — stato: **fase 1 completata; fasi 2, 3 e 4 implementate**, da
validare con persone, camera e proiettore reali (vedi §10). **Prossimo lavoro: §10.2,
movimento del cursore fluido e stabile.** Per ora si prova con la webcam
del portatile, senza proiettore (coordinate camera a specchio, senza calibrazione).

Novità della 0.7: repo predisposta per molti giochi e per cambiare sensore (§4.1):
framework `core/`, giochi in `games/<id>/` con `game.json`, menu `launcher/`,
`new_game.sh`; tracker a plugin con `produces`/`accepts`/`provides`; nel protocollo
**effettori** e **capacità** (§5). Guide in `docs/GUIDA_NUOVO_GIOCO.md` e
`docs/GUIDA_NUOVO_SENSORE.md`.

Hardware: una webcam HP FHD Camera. Linux la espone come `/dev/video0` (immagini) e
`/dev/video1` (solo metadati UVC); il tracker sceglie da solo il nodo che dà immagini.
Formati: MJPG fino a 1920×1080 a 30 fps; il tracker usa 640×480.

Novità della 0.3: i marker diventano facoltativi (modalità `markerless` / `markers` / `mixed`),
id stabili senza marker, punti del busto ampliati, fasi riordinate (prima il corpo, poi i colori).

## 1. Scopo

Comandare giochi Godot proiettati (proiettore su muro/pavimento/tavolo) usando come input
il corpo dei giocatori ripreso da una webcam: busto, braccia, mani e faccia, e in più,
**facoltativamente**, marker colorati tenuti in mano (rosso, blu, giallo) che danno
un'identità certa al giocatore.

L'obiettivo di questa spec è la **pipeline di input generica**: dalla camera fino a dati
puliti e azioni dentro Godot. **Cosa significa** ogni input in un gioco (braccio = bastone,
mano = cursore, faccia = sterzo...) si decide dopo, gioco per gioco, nello strato di
mappatura (§6.3), senza toccare il resto.

### Fuori ambito (per ora)
- Misure 3D reali / profondità (si lavora in 2D sul piano della proiezione).
- Più camere, rete tra macchine diverse.
- Riconoscimento dell'identità della persona (l'identità è data dal colore del marker).

## 2. Contesto e vincoli

- Godot 4.7, GDScript tipizzato, renderer Compatibility, Linux. Regole in `CLAUDE.md`.
- Ogni input arriva ai giochi tramite **azioni dell'Input Map** o tramite l'API di
  `BodyInput`; mai tasti o sorgenti cablate nei giochi.
- Tracker in Python separato dal gioco: Python 3.12 in un venv dedicato
  (`tracker/.venv`). Il Python di sistema è 3.14, che MediaPipe potrebbe non supportare.
- Webcam disponibili sulla macchina: `/dev/video0`, `/dev/video1`.
- Tutto gira in locale sulla stessa macchina.

## 3. Requisiti

### Funzionali
| ID | Requisito |
|----|-----------|
| F1 | *(Facoltativo)* Rilevare fino a 3 marker colorati (rosso, blu, giallo) e darne la posizione. |
| F2 | Rilevare lo scheletro della parte superiore del corpo (§5, punti della pose) di 1–3 persone; anche e parti non inquadrate arrivano come "non viste". |
| F3 | Rilevare per ogni mano: posizione, mano aperta/chiusa, pizzico. |
| F4 | Rilevare la faccia: posizione, imbardata/beccheggio/rollio della testa, bocca aperta. |
| F5 | Dare a ogni persona un **id stabile nel tempo**, con o senza marker (§5, identità dei giocatori). |
| F6 | Convertire tutte le coordinate camera → schermo proiettato tramite calibrazione. |
| F7 | Ogni rilevatore (F1–F4) si attiva/disattiva da configurazione. |
| F8 | Godot espone i dati filtrati per giocatore e segnala ingresso/uscita dei giocatori. |
| F9 | Godot funziona anche senza tracker: simulatore (mouse/tastiera) e replay da file. |
| F10 | Le sessioni reali si possono registrare su file e rigiocare in modo deterministico. |
| F11 | Overlay di debug che disegna sopra il gioco tutto ciò che il sistema vede. |
| F12 | Controller riutilizzabili che trasformano i dati in azioni/nodi di gioco (§6.3). |
| F13 | Modalità di identità da config: `markerless`, `markers`, `mixed` (§5). |
| F14 | Regola di assegnazione dei giocatori senza marker scelta dal gioco: a zone o in ordine di arrivo (§5). |
| F15 | Valori derivati del busto (inclinazione, braccia alzate/aperte, accovacciato/salto) disponibili ai giochi (§6.3). |

### Non funzionali
| ID | Requisito |
|----|-----------|
| N1 | Latenza camera → Godot < 100 ms (obiettivo 60 ms). |
| N2 | Tracker ≥ 30 fps con colori + pose; i rilevatori pesanti si spengono se non servono. |
| N3 | Se il tracker si ferma o crasha, il gioco continua (giocatori marcati "persi"). |
| N4 | Ogni strato è testabile in headless senza camera (`./check.sh`). |
| N5 | Il protocollo è versionato; Godot ignora i pacchetti con versione sconosciuta. |

## 4. Architettura

```
┌──────────────────────── tracker/ (Python) ─────────────────────────┐
│ 1. CATTURA      camera → frame (thread dedicato, esposizione fissa)│
│ 2. RILEVATORI   pose · mani · faccia (MediaPipe) · colori (OpenCV  │
│                 HSV, facoltativo), ognuno attivabile da config     │
│ 3. PROIEZIONE   camera → schermo (0..1): omografia se calibrato,   │
│                 altrimenti coordinate camera specchiate            │
│ 4. IDENTITÀ     tracciamento frame→frame = id stabili (calcolato   │
│                 sullo schermo); con marker il colore ha precedenza │
└──────────────────────────────┬─────────────────────────────────────┘
                               │ UDP JSON su 127.0.0.1:4242
┌──────────────────────── Godot ┴────────────────────────────────────┐
│ 5. PONTE        autoload BodyInput: sorgente (UDP/simulatore/      │
│                 replay), filtro One Euro, timeout, registrazione   │
│ 6. DATI         BodyInput.get_player("red").point("wrist_r") ...   │
│ 7. MAPPATURA    controller: Stick, Pointer, Head, Gesture          │
│ 8. INPUT        azioni Input Map (anche analogiche) + nodi di gioco│
└────────────────────────────────────────────────────────────────────┘
```

Gli strati 1–6 sono comuni a tutti i giochi. Gli strati 7–8 sono dove si progetta il gioco.

### Struttura dei file
```
README.md, CLAUDE.md      panoramica; istruzioni per Claude
check.sh                  tutti i test (Godot headless + pytest)
play.sh, play_body.sh     avvio (solo Godot / tracker + menu)
tracker.sh, new_game.sh   avvio del tracker; crea un gioco dal modello
core/                     framework Godot riusabile
  body_input/             BodyInput (autoload), PlayerState, OneEuroFilter, sources/ (udp, simulatore, replay)
  body/                   BodyMetrics (+ Baseline), BodyColliders, BodyDebugDraw
  controllers/            GestureController, DwellTarget
  game/                   BodyGame (base dei giochi), GameManifest (game.json), GameRegistry
games/<id>/               un gioco: game.json, scena, script (extends BodyGame), tests/
games/_template/          modello per new_game.sh (testato come un gioco)
launcher/                 menu dei giochi (scena principale)
tools/calibration/        scena di calibrazione (ArUco)
tools/body_demo/          demo: tutti i giocatori su sfondo scuro
examples/counter/         demo iniziale (contatore)
data/aruco_4x4_50.json    pattern dei marker, letti da Godot e dai test Python
recordings/*.jsonl        sessioni registrate (session_* non versionate)
tests/                    test del core e di integrazione (anche Python ↔ Godot)
tracker/                  pacchetto Python (escluso da Godot con .gdignore)
  __main__.py             riga di comando (--list-plugins, --source, --detectors, ...)
  config.py, config.json  default + configurazione
  registry.py, plugins.py registri nome → classe; import automatico dei plugin
  structs.py              Frame (data + kind), Point, Person (points, effectors, ...), FrameResult
  sources/                plugin sorgenti: camera, video, synthetic (FrameSource.produces)
  detectors/              plugin rilevatori: pose, synthetic, synthetic_contacts (accepts / provides)
  identity.py             tracciamento + assegnatori "zones"/"arrival"
  projection.py           CameraProjection / HomographyProjection
  protocol.py             formato v1 + validate_packet (il contratto)
  sinks.py                uscite: "udp"
  control.py              canale Godot → tracker
  calibration.py          metodi di calibrazione (CALIBRATION_METHODS: "aruco")
  pipeline.py             assemblaggio, compatibilità, sessione, capacità
  debug_view.py           finestra OpenCV (--debug)
  models.py, models/      modelli MediaPipe (scaricati se mancano)
  tests/                  pytest
```

### 4.1 Estendibilità: giochi e sensori

```
 sensore A ─┐                                        ┌─ games/bubbles
 sensore B ─┼─► plugin del tracker ─► protocollo v1 ─┼─ games/<nuovo>
 altro prog.┘   (o qualsiasi programma   (contratto) └─ launcher
                 che parla il v1)
```

- **Il protocollo v1 è il confine.** A sinistra si cambia hardware, a destra si fanno giochi;
  nessuno dei due lati conosce i dettagli dell'altro.
- **Capacità**: il tracker annuncia in ogni pacchetto cosa sa fare (`caps`: `pose`,
  `hands`, `face`, `markers`, `effectors`), unione dei `provides` dei rilevatori attivi.
  Ogni gioco dichiara in `game.json` cosa richiede (`requires`) e cosa usa se c'è
  (`optional`); il menu segnala le capacità mancanti.
- **Effettori**: i punti che possono "toccare" i giochi. Da un sensore senza scheletro
  arrivano espliciti (`effectors`); con la pose Godot usa le mani
  (`BodyMetrics.effectors`). `BodyColliders` mette le aree sugli effettori: i giochi
  basati sul tocco funzionano con qualsiasi sensore.
- **Tracker a plugin**: `FrameSource.produces` (tipo di dato: "image", "scan2d",
  "depth"...), `Detector.accepts` / `provides`. La pipeline rifiuta subito combinazioni
  incompatibili. Sorgenti e rilevatori si registrano da soli (`plugins.py`).
- **Giochi a cartella**: `games/<id>/` + `game.json`; `GameRegistry` li trova, il menu li
  mostra, `BodyGame` manda la sessione al tracker e gestisce l'uscita.

## 5. Protocollo tracker → Godot (v1)

- Trasporto: UDP, `127.0.0.1:4242` (configurabile), un JSON UTF-8 per datagramma,
  massimo 8 KB.
- Frequenza: un pacchetto per frame elaborato (30–60 Hz). Ogni pacchetto è uno stato
  completo, non un delta: perderne uno non crea problemi.
- Coordinate: `x`, `y` normalizzati in 0..1 sullo schermo proiettato (origine in alto a
  sinistra). Possono uscire da 0..1 se il punto è fuori dalla proiezione.
  Se non c'è calibrazione, `"space": "camera"` e le coordinate sono relative al frame
  camera, specchiate orizzontalmente.
- Punto: `[x, y, c]`, dove `c` è l'affidabilità 0..1. **Campo assente = non visto.**

```json
{
  "v": 1,
  "t": 12.345,
  "space": "screen",
  "fps": 31.2,
  "caps": ["effectors", "face", "hands", "markers", "pose"],
  "players": [
    {
      "id": "red",
      "marker": {"x": 0.42, "y": 0.61, "area": 0.004},
      "pose": {
        "nose": [0.45, 0.18, 0.99],
        "shoulder_l": [0.50, 0.33, 0.98], "shoulder_r": [0.40, 0.33, 0.98],
        "elbow_l": [0.55, 0.45, 0.90],    "elbow_r": [0.36, 0.47, 0.93],
        "wrist_l": [0.57, 0.58, 0.85],    "wrist_r": [0.42, 0.60, 0.91],
        "hip_l": [0.49, 0.62, 0.95],      "hip_r": [0.41, 0.62, 0.95]
      },
      "hands": {
        "r": {"wrist": [0.42, 0.60, 0.9], "index_tip": [0.43, 0.55, 0.9],
              "open": 0.92, "pinch": 0.05}
      },
      "face": {"x": 0.45, "y": 0.17, "yaw": -12.0, "pitch": 4.0, "roll": 1.5,
               "mouth_open": 0.7}
    }
  ]
}
```

- `caps` (facoltativo): capacità del sensore (§4.1). Se manca, Godot le deduce dai campi
  presenti.
- `effectors` (facoltativo, per giocatore): `{"nome": [x, y, c]}`, punti che possono
  toccare, per sensori senza scheletro. Esempio (un LiDAR):
  `{"id": "p1", "effectors": {"e0": [0.42, 0.61, 0.9]}}`.
- Il contratto completo è `tracker/protocol.py: validate_packet()`.
- `id`: `"red"`, `"blue"`, `"yellow"` se c'è un marker associato; altrimenti `"p1"`,
  `"p2"`, `"p3"` (stabili, vedi sotto). Il campo `marker` è presente solo se c'è un marker.
- `l`/`r` sono la sinistra/destra **della persona**, non dell'immagine.
- Angoli in gradi. `open`, `pinch`, `mouth_open` vanno da 0 a 1.

### Mappatura sensore → schermo
Le coordinate dei pacchetti sono già sullo schermo di gioco (0..1). Come ci arrivano lo
decide la mappatura del tracker (`projection.mode` in config, `--mapping`, plugin in
`tracker/projection.py: PROJECTIONS`):

| Modalità | Quando | Cosa fa |
|---|---|---|
| `homography` | proiettore calibrato | omografia camera → schermo: la mano cade sulla sua ombra |
| `body_zone` | senza calibrazione (default, es. webcam del portatile) | attorno a ogni giocatore una zona larga `width_sw` (3,2) larghezze spalle, bordo alto `top_sw` (1,1) larghezze spalle sopra le spalle, altezza dalle proporzioni dello schermo: quella zona diventa tutto lo schermo. Stessa posa = stesso punto a qualsiasi distanza dalla camera; la zona segue la persona in ~1 s; le mani a riposo restano sotto lo schermo. Senza spalle: come `mirror` |
| `mirror` | — | immagine intera a specchio, senza deformazioni (taglia i bordi in più) |
| `stretch` | — | immagine stirata (vecchio comportamento) |
| `auto` | default | `homography` se c'è `calibration.json`, altrimenti `uncalibrated` (`body_zone`) |

L'identità (zone p1/p2) usa sempre la mappatura globale, non la zona personale. Le
proporzioni della camera vengono dai frame, quelle dello schermo da Godot (campo `screen`
della sessione). La finestra di debug del tracker disegna la zona di ogni giocatore.

### Schermo intero (Godot)
Il progetto parte a schermo intero (`window/size/mode=3`, stretch `canvas_items` +
`expand`: le scene si adattano a 16:9, 16:10, 4:3...). L'autoload `Display`
(`core/app/display.gd`) gestisce `--windowed`, `--screen=N` (es. il proiettore) e
l'azione `toggle_fullscreen` (F11). `play_body.sh` accetta `--windowed` e `--screen N`.
Nota: la registrazione video di Godot (`--write-movie`) con schermo HiDPI taglia la parte
alta dei fotogrammi; per controlli visivi usare una cattura della viewport.

### Campi extra
Un pacchetto può avere campi in più, che Godot passa così come sono nel segnale
`BodyInput.packet_received`. Oggi: `"calibration"` (stato della calibrazione, §7), inviato
con `players` vuota mentre il tracker è in modalità `--calibrate`.

### 5.1 Canale di controllo Godot → tracker
UDP JSON su `127.0.0.1:4243` (`control` in config.json, `BodyInput.control_port` in Godot),
un oggetto per datagramma con un campo `"type"`. Messaggi:

| `type` | Campi | Uso |
|--------|-------|-----|
| `calibration_layout` | `dictionary`, `screen: [w, h]`, `markers: {"0": [[x,y]×4], ...}` (angoli TL, TR, BR, BL normalizzati) | la scena di calibrazione dice dove sono i marker, ogni 0,5 s |
| `session` | `max_players` (1–8); `requires` (capacità), `game` (id); `screen: [w, h]` (aggiunto da BodyInput: proporzioni per la mappatura) | il gioco dice di quanti giocatori ha bisogno; ripetuto ogni 1 s finché il gioco è aperto. Il tracker cambia `identity.max_players` e il numero di persone cercate da MediaPipe (`num_poses`), a caldo |

In futuro `session` potrà dire anche quali rilevatori servono (mani, faccia, colori).
Lato tracker ogni rilevatore riceve la sessione in `Detector.apply_session()`.

### Punti della pose
Tutti facoltativi (assente = non visto o fuori inquadratura):
`nose`, `eye_l`, `eye_r`, `ear_l`, `ear_r`, `mouth_l`, `mouth_r`,
`shoulder_l`, `shoulder_r`, `elbow_l`, `elbow_r`, `wrist_l`, `wrist_r`,
`index_l`, `index_r`, `hip_l`, `hip_r`, e due punti calcolati dal tracker:
`shoulder_c` (centro delle spalle) e `hip_c` (centro delle anche).
Ginocchia e piedi si possono aggiungere più avanti con gli stessi nomi di MediaPipe
(`knee_l`, `ankle_l`...), senza cambiare versione del protocollo.

### Identità dei giocatori (F5, F13, F14)
Modalità in `tracker/config.json` → `"identity": {"mode": ..., "assign": ...}`:

| `mode` | Comportamento |
|--------|---------------|
| `markerless` (default) | Nessun rilevatore colori. Ogni scheletro riceve un id `p1`..`p3` secondo `assign`. |
| `markers` | Solo le persone con un marker sono giocatori (`red`/`blue`/`yellow`); le altre non vengono inviate. |
| `mixed` | Chi ha un marker prende il colore; gli altri ricevono `p1`..`p3`. |

**Tracciamento (sempre attivo).** Il punto di riferimento di una persona è
`shoulder_c` (in mancanza `nose`, poi `hip_c`), nello spazio dello schermo. Ogni traccia
stima la propria velocità; a ogni frame gli scheletri si agganciano alla **posizione
prevista** della traccia più vicina, entro 0.15, con accoppiamento greedy per distanza
crescente. Grazie alla previsione, due persone che si incrociano non si scambiano l'id.
Una persona non vista resta "in attesa" per 0.5 s (il suo id non viene dato ad altri):
se riappare vicino alla posizione prevista, riprende lo stesso id.

**Assegnazione degli id `pN`** (`assign`):
- `zones` (default): lo schermo è diviso in N fasce verticali (N = `max_players`, default 2);
  l'id è quello della fascia in cui la persona **entra**, e poi lo mantiene finché
  è tracciata. Due persone nella stessa fascia: la seconda prende la prima fascia libera.
- `arrival`: il primo id libero, nell'ordine in cui le persone compaiono.

**Associazione ai marker** (`markers`/`mixed`): per ogni marker si sceglie lo scheletro
con il polso più vicino entro 0.08, accoppiamento greedy; ogni scheletro va a un solo
marker. Una volta associato, lo scheletro tiene il colore finché è tracciato, anche se il
marker sparisce per un attimo. Mani e faccia vanno allo scheletro con il polso / il naso
più vicino.

## 6. Lato Godot

### 6.1 Autoload `BodyInput`
```gdscript
signal player_entered(id: StringName)
signal player_lost(id: StringName)
signal frame_updated
signal packet_received(packet: Dictionary)   # pacchetto grezzo, con eventuali campi extra
signal source_changed(source_name: String)
signal replay_finished

enum Source { UDP, SIMULATOR, REPLAY }
var control_port: int = 4243
func send_control(message: Dictionary) -> void  # canale di controllo §5.1
func set_session(session: Dictionary) -> void   # es. {"max_players": 1}, ripetuta ogni 1 s
func clear_session() -> void
var source: Source                    # default UDP; SIMULATOR se nessun pacchetto entro 2 s (configurabile)
var lost_timeout: float = 0.3         # secondi senza dati prima di "perso"

func get_player(id: StringName) -> PlayerState   # null se assente
func get_players() -> Array[PlayerState]
func start_recording(path: String) -> void
func stop_recording() -> void
func play_recording(path: String, loop := false) -> void
```

`PlayerState`:
```gdscript
var id: StringName
func has_point(name: StringName) -> bool          # "wrist_r", "marker", "face", "hand_r.index_tip"...
func point(name: StringName) -> Vector2           # in pixel della viewport, filtrato
func confidence(name: StringName) -> float
func value(name: StringName) -> float             # "hand_r.open", "face.yaw", "face.mouth_open"...
```

- **Filtro**: One Euro per ogni punto (parametri `min_cutoff`, `beta` in config).
  Il filtro usa l'istante di scatto del sensore (campo `t` del pacchetto), non l'ora di
  arrivo: le irregolarità di rete non diventano finte accelerazioni. Si elaborano tutti i
  pacchetti arrivati, in ordine.
- **Fluidità a schermo** (`display_smoothing`, default attivo): il sensore dà ~30
  campioni/s, lo schermo 60. `point()` prosegue il movimento con la velocità stimata tra
  un campione e l'altro (max `extrapolation_limit` = 50 ms) e assorbe in ~`correction_time`
  (60 ms) la differenza quando arriva il campione nuovo. `point_filtered()` dà il campione
  puro. Misurato (`tests/smoothness_test.gd`): variazione della velocità a schermo da 195%
  a 10%, frame fermi da 79% a 0%, ritardo medio da 45 a 26 ms; arresto improvviso: va
  oltre di ~1,6% dello schermo, poi si ferma nel punto giusto.
- **Centro della mano** (`BodyMetrics.hand_center`): avambraccio prolungato del 30% oltre
  il polso (il gomito è stabile); senza gomito tra polso e indice; altrimenti il polso.
- **Perdita**: un punto non visto mantiene l'ultimo valore per `lost_timeout`, poi
  `has_point` diventa falso. Se il giocatore non ha punti per `lost_timeout`,
  parte `player_lost`.
- **Simulatore**: il mouse muove marker e polso destro del giocatore attivo (la spalla
  resta dove è comparso, il gomito è calcolato). Azioni: `sim_hand_close` (clic
  sinistro, mano chiusa), `sim_next_player` (Tab, red → blue → yellow).
- **Cambio sorgente**: azzera tutti i giocatori (emette `player_lost`), per non
  mescolare dati simulati e reali. Da UDP si ingerisce solo il pacchetto più recente
  per frame.
- **Porta**: `listen(port)` cambia porta (i test usano 42424). Se la porta è occupata
  c'è un warning e il gioco prosegue.
- **Registrazione**: file `.jsonl` con i pacchetti grezzi e il tempo di arrivo; il
  replay li rimette in coda con gli stessi tempi.

### 6.2 Overlay di debug (F11)
Già disponibile: `BodyDebugDraw` (Node2D) disegna marker, scheletri, mani, faccia con la
direzione dello sguardo e id dei giocatori; si aggiunge come figlio a qualsiasi scena
(lo usano `body_demo.tscn` e `calibration.tscn`). Da completare in fase 4: una `CanvasLayer`
che lo contiene, si accende/spegne con l'azione `toggle_debug_overlay` e mostra fps del
tracker, latenza e sorgente attiva.

### 6.3 Controller (strato 7)
Nodi da aggiungere alla scena di gioco, configurati da Inspector con `player_id` e
`side`. Producono **azioni dell'Input Map** (`Input.action_press(azione, forza)` per
valori analogici) e/o proprietà leggibili. Nomi delle azioni: `<giocatore>_<controller>_<cosa>`,
es. `red_pointer_click`, `blue_head_steer_left`.

| Controller | Ingresso | Uscita |
|------------|----------|--------|
| `StickController` | spalla → polso (o gomito → marker) | segmento con `Area2D`/forma di collisione che segue il braccio, angolo, velocità della punta |
| `PointerController` | marker o `hand_*.index_tip` | posizione cursore; click per sosta (default 1 s) o pizzico |
| `HeadController` | `face.yaw` / `face.pitch` | assi analogici (`*_steer_left/right`, `*_up/down`) |
| `GestureController` | `hand_*.open`, `face.mouth_open`, braccia alzate... | azioni digitali con isteresi |

Quale controller usare e come si chiama ogni azione si decide gioco per gioco.

**Valori derivati del busto (F15)**: una classe di utilità `BodyMetrics` (statica, in
GDScript) calcola da un `PlayerState`, usando solo i punti disponibili:

| Valore | Calcolo | Uso tipico |
|--------|---------|------------|
| `torso_lean` | angolo di `shoulder_c` → `hip_c` dalla verticale; senza anche, inclinazione della linea delle spalle | sterzare, schivare |
| `arm_raised_l/r` | 0..1, polso sotto la spalla → sopra la testa | saltare, alzare la mano per rispondere |
| `arms_spread` | distanza tra i polsi / larghezza delle spalle | volare, "grande/piccolo" |
| `arm_angle_l/r` | angolo spalla → polso | bastone, puntare |
| `crouch` / `jump` | spostamento verticale di `shoulder_c` rispetto alla posizione di riposo (media mobile lenta), normalizzato sulla larghezza delle spalle | accovacciarsi, saltare |

I rapporti sono normalizzati sulla larghezza delle spalle, così non dipendono dalla
distanza dalla camera. `BodyMetrics` vive in Godot, non nel tracker: si può cambiare
senza toccare Python e si testa con le registrazioni.

**Implementato (fase 4):**
- `BodyMetrics` (statica): `shoulder_width`, `shoulder_center`, `has_hand`, `hand_center`
  (tra polso e indice, o il polso), `torso_lean`, `arm_raised`, `arms_spread`, `arm_angle`.
  NAN se mancano i punti. `BodyMetrics.Baseline` (una per giocatore): `update()`,
  `crouch()`, `jump()`; il riposo si adatta in ~3 s.
- `GestureController` (Node): gesti `ANY_ARM_RAISED`, `BOTH_ARMS_RAISED`, `ARMS_SPREAD`
  → azione dell'Input Map, con soglie on/off (isteresi), `hold_time`, filtro per
  giocatore; segnali `activated`/`deactivated`. Gira con `process_priority = -10`.
- `BodyColliders` (Node2D): `Area2D` sulle mani (cerchi) e, se attivato, sugli avambracci
  (rettangoli), sul layer fisico 2 "body". Metadati `player_id`, `part`, `velocity`;
  `BodyColliders.owner_of(area)`. Disegna le mani come "cursori" colorati per giocatore.
  Misure in proporzione all'altezza dello schermo.

**Nota sui test headless**: con `-s` lo script di test viene compilato prima che esista
l'autoload `BodyInput`, quindi le classi che lo usano (`GestureController`,
`BodyColliders`, `Bubble`, `BodyDebugDraw`) vanno caricate con `load()` e non citate per
nome. La viewport headless è 64×64 e non si ridimensiona: i test lavorano in proporzione.

### 6.4 Framework dei giochi
- **`games/<id>/game.json`** (`GameManifest`): `id` (= nome cartella), `title`,
  `description`, `controls`, `scene`, `players {min, max}`, `requires`, `optional`.
  Validato all'avvio e da `tests/game_framework_test.gd`.
- **`BodyGame`** (base di ogni gioco): legge il manifest, manda la sessione al tracker
  (`{"max_players", "requires", "game"}`), la ritira all'uscita, `game_exit` (Esc) torna
  al menu. I giochi implementano `_game_ready()`.
- **`GameRegistry`**: trova i giochi in `games/` (ignora le cartelle che iniziano con `_`).
- **`launcher/`** (scena principale): una scheda per gioco; si sceglie tenendo ferma la
  mano su una scheda (`DwellTarget`) o con frecce + Invio; segnala capacità mancanti.
- **`DwellTarget`** (Area2D): "clic" tenendo un effettore fermo per `dwell_time` secondi.
- **`new_game.sh <id> "Titolo"`**: copia `games/_template` (gioco minimo funzionante con
  test) e rinomina tutto. Procedura completa in `docs/GUIDA_NUOVO_GIOCO.md`.

### 6.5 Minigioco "Bolle" (fase 4)
`scenes/bubbles.tscn`, script in `scripts/games/bubbles/`. **Un giocatore**: con la webcam
del portatile bisogna stare vicini per vedere il busto, e in due non ci si sta. All'avvio
il gioco chiede al tracker `{"max_players": 1}` (§5.1). Le bolle salgono dal basso
ondeggiando e si scoppiano con le mani. Normale +1, dorata +3, spinosa −3. La partita
dura 60 s e accelera nel tempo. Si parte e si riparte alzando un braccio (azione
`game_start`, anche con Invio). Punteggio e record della sessione.
Avvio con la webcam: `./play_body.sh` (tracker in background + gioco).

### 6.6 Gioco "Tris"
`games/tris/`. Si gioca con la **mano destra**, che segna a turno X e O (da soli o in due
che si alternano); la sinistra è ignorata (`BodyColliders.part_filter` e
`DwellTarget.accept_parts` = `["hand_r"]`). Mano ferma su una casella libera per 1,2 s →
simbolo del turno. Griglia in alto (le mani a riposo non la toccano); "Nuova partita" con
la mano o Invio; il pulsante non copre mai la griglia (sotto, se lo schermo è stretto).
Senza capacità `pose` (es. LiDAR) vale qualsiasi effettore. Nel core sono stati aggiunti i
filtri di `DwellTarget` (`accept_parts`, `accept_players`, `enabled`, segnale
`selected_by`) e `BodyColliders.part_filter`.
`DwellTarget.exclusive_group`: i bersagli dello stesso gruppo si escludono, una mano
conta solo per quello più vicino al suo centro (anche se occupato). Evita la doppia
selezione con la mano a cavallo di due caselle; usato in Tris e nel menu.

### 6.7 Gioco "Taglia il filo"
`games/taglia_filo/`. Una lancetta gira su un quadrante con una finestra verde; si taglia
portando la mano destra sul filo (a destra) quando la lancetta è nel verde, poi la mano
deve uscire per ricaricare. Nel verde +1, al centro +2; la finestra si sposta e si
stringe (×0,9, min ~11°), la lancetta accelera (×1,1, max ~340°/s) e dal livello 4
inverte il senso a intervalli casuali. Fuori dal verde o 3 passaggi senza taglio: −1
vita (3 vite). **Compensazione del ritardo**: il taglio si giudica dove era la lancetta a
`now − BodyInput.input_latency` (0,10 s di default; la storia esatta del movimento è in
`needle_angle_at`). `BodyInput.input_latency` è nel core per tutti i giochi di timing.

## 7. Calibrazione

**Procedura** (da ripetere quando si spostano camera o proiettore):
1. `./play.sh res://tools/calibration/calibration.tscn` sul proiettore: sfondo bianco e 4 marker
   ArUco (DICT_4X4_50, id 0 alto sx, 1 alto dx, 2 basso dx, 3 basso sx) a schermo intero.
   Per provarla in finestra: `./play.sh res://tools/calibration/calibration.tscn -- --windowed`.
2. `./tracker.sh --calibrate --debug`: il tracker riceve il layout sul canale di controllo,
   cerca i marker nella camera e manda lo stato a Godot, che lo mostra al centro dello schermo.
3. Con tutti i 4 marker visibili per `frames_needed` frame consecutivi (default 15), il
   tracker fa la media degli angoli, calcola l'omografia con i 16 angoli (minimi quadrati)
   e la salva in `tracker/calibration.json` se l'errore RMS è sotto `max_error` (default 2%
   dello schermo). Altrimenti segnala `failed` e riprova.
4. Il tracker passa da solo al tracciamento normale (con `--calibrate-only` esce); la scena
   passa da sola alla **vista di verifica** (sfondo scuro, griglia, scheletri): lo scheletro
   deve cadere sopra la persona. Tasto C: torna ai marker. Esc: esci.

**Geometria dei marker**: lato = 22% del lato corto dello schermo, margine 4%, sfondo
bianco (fa da zona di rispetto). Gli angoli vengono calcolati da Godot e inviati al tracker,
quindi funziona con qualsiasi risoluzione e rapporto del proiettore.

**Stati** (campo `calibration` dei pacchetti): `waiting_layout` → `searching` (non vede
tutti i marker; `found` dice quali) → `collecting` (`progress` 0..1) → `done` (`error`)
oppure `failed` (`message`).

Opzioni del tracker: `--calibrate`, `--calibrate-only`, `--calibration-timeout S`,
`--uncalibrated` (ignora la calibrazione salvata).

Limite noto: l'omografia è esatta solo sul piano della proiezione. Il corpo sta davanti,
quindi la posizione corrisponde a dove cadrebbe la sua **ombra**. È una scelta voluta.

## 8. Rischi e contromisure

| Rischio | Contromisura |
|---------|--------------|
| Il proiettore proietta colori scambiati per marker | Palette dei giochi senza rosso/blu/giallo saturi; filtro su area e forma; esposizione e bilanciamento del bianco fissi; in seguito LED o IR |
| La luce proiettata sul corpo disturba MediaPipe | Luce ambiente minima, camera vicina all'asse del proiettore, soglie di affidabilità |
| Carico CPU con tutti i rilevatori attivi | Rilevatori attivabili da config; ogni gioco dichiara cosa usa; faccia/mani a frequenza ridotta |
| L'identità degli scheletri salta | Tracciamento con attesa di 0.5 s; assegnazione a zone; in `mixed`/`markers` il colore del marker ha la precedenza |
| MediaPipe non supporta il Python di sistema | venv con Python 3.12 |

## 9. Test

- **Godot (headless, `./check.sh`)**:
  - Parsing del protocollo: pacchetti validi, campi mancanti, versione sconosciuta.
  - Invio di pacchetti UDP finti a `BodyInput` e verifica di posizioni, filtro e timeout.
  - Replay di registrazioni in `recordings/` e verifica di eventi e azioni dei controller.
- **Tracker (`pytest`)**: immagini sintetiche con cerchi colorati e immagini ArUco per
  colori e calibrazione; associazione con scheletri finti.
- **Manuale**: overlay di debug con camera e proiettore reali.

## 10. Fasi e criteri di accettazione

| Fase | Contenuto | Fatto quando |
|------|-----------|--------------|
| 1 ✅ | Ponte Godot: `BodyInput`, `PlayerState`, filtro, simulatore, registrazione/replay, scena demo (`scenes/body_demo.tscn`) | Test headless passano; con il mouse i cerchi si muovono |
| 2 🟡 | Tracker corpo: cattura, MediaPipe Pose, identità `markerless` (tracciamento + `zones`/`arrival`), invio UDP, finestra di debug | 2 persone reali nella demo con id stabili per 1 minuto, anche incrociandosi; ≥ 25 fps. **Codice e test fatti; manca la prova con persone vere** |
| 3 🟡 | Calibrazione ArUco | Lo scheletro proiettato sta sopra la persona come un'ombra (errore < 2% dello schermo sul piano). **Codice e test fatti (anche: marker renderizzati da Godot riconosciuti da OpenCV); manca la prova con proiettore e camera reali** |
| 4 🟡 | `BodyMetrics` + primi controller + minigioco "Bolle" (§6.4) | Un minigioco giocabile solo col corpo, senza marker. **Fatto e testato con simulatore e tracker sintetico; manca la prova con la webcam del portatile.** Ancora da fare: la `CanvasLayer` di debug con fps e latenza (§6.2) |
| 5 | Marker colorati (OpenCV + `tune_colors.py`), modalità `markers`/`mixed` | 3 marker stabili col proiettore acceso; il colore resta allo scheletro giusto |
| 6 | Mani e faccia (MediaPipe Hands, Face) | Mano aperta/chiusa e inclinazione della testa nella demo |
| 7 | Rifinitura: latenza, parametri, `play.sh` avvia tracker + gioco | N1–N3 rispettati |

## 10.1 Prestazioni misurate (2026-11-25, Intel Core Ultra 7 155H, 22 thread, solo CPU)

| Stadio | Misura |
|--------|--------|
| Camera HP FHD 640×480 MJPG | 30 fps (con `buffers: 2`; con 1 buffer scendeva a 20 fps) |
| Pose `lite`, 1–2 persone | 20–21 ms/frame (p95 28 ms) → max ~50 fps |
| Pose `full`, 1–2 persone | 26–27 ms/frame (p95 31 ms) → max ~37 fps |
| Pose `heavy`, 1 / 2 persone | 60 / 95 ms/frame → 17 / 10 fps: **non adatto** al tempo reale |
| Identità + pacchetto + UDP | < 0,1 ms |
| Tracker a regime (2 persone, 30 fps) | `lite` 0,75 core, `full` 1,0 core (~4% della macchina), RAM ~270 MB |
| Godot `ingest_packet` (2 giocatori × 27 punti) | 0,15 ms |
| Ritardo del filtro One Euro | 47 ms a 0,1 schermi/s, 18 ms a 0,5, 8 ms a 1,5 (adattivo) |
| Gioco Bolle (20–100 bolle, 2 giocatori) | costo logico trascurabile |

**Latenza stimata camera → schermo** (fase 2, `full`): esposizione e trasferimento della
camera 33–66 ms + pose 27 ms + attesa del frame Godot ~8 ms + filtro 8–18 ms (mani veloci)
+ fisica fino a 17 ms + rendering e vsync 17–33 ms ≈ **110–170 ms** su monitor; il
proiettore aggiunge di solito 15–50 ms. La parte camera e la parte display sono stime: da
misurare con un test dedicato (fase 7).

Misure ottenute con l'immagine pubblica di prova di MediaPipe (`pose.jpg`), composta in
frame con 1 e 2 persone in movimento.

## 10.2 DA FARE — Movimento del cursore (mano) fluido e stabile

Stato: **da fare** (pianificato per la mattina del 2026-11-27). Segnalazione dell'utente:
in gioco il cursore della mano "si muove molto, non è fluido, fa scatti, trema".

### Misure (registrazione reale `recordings/session_tracker_analisi2.jsonl`, solo in locale, non versionata; 53 s, 29,4 fps, webcam del portatile, stanza in penombra, utente vicino al portatile)
Ottenute con `./tracker.sh --record file.jsonl` e
`tracker/.venv/bin/python -m tracker.tools.analyze_recording file.jsonl`:

| Misura | Valore |
|---|---|
| Rumore da fermo, mediana / 90° (pixel) | naso 0,1 / 0,7 camera; polso 0,8 / 5,1 camera → 1,1 / 6,9 schermo |
| Amplificazione della zona di gioco | ×1,4–2 (contenuta) |
| Polso destro presente | **34% dei frame, 184 lampeggi** in 53 s (indice 49%, 218) |
| Gomito destro | quasi mai visibile (0,1%): fuori inquadratura |
| Mano per Godot (polso o indice) | presente 49%, **109 interruzioni, 13 oltre 0,3 s** (il cursore sparisce) |
| Spostamento tra frame | mediana 13 px, 90° 47 px, 23 salti > 60 px |
| Posizione del polso nell'immagine | y mediana 0,83 (vicino al bordo basso) |
| Campo visivo camera | in 16:9 (1280×720) vede il **31% in più in larghezza** del 4:3, stessa altezza |

**Diagnosi**: il tremolio vero è piccolo. Gli scatti vengono dai punti delle mani che
**compaiono e scompaiono** più volte al secondo: il polso sta vicino al bordo basso
dell'immagine, la sua affidabilità oscilla attorno alla soglia fissa (0,5) e il tracker lo
accende e spegne a ogni oscillazione; il gomito è fuori campo. Peggiorano: penombra,
utente troppo vicino alla camera, inquadratura 4:3.

### Piano
1. **Stabilizzatore nel tracker** (stadio dopo l'identità, per tutti i sensori; bozza sul
   ramo `funzione/stabilita-tracker`, `tracker/stabilizer.py`, non ancora collegata):
   isteresi dell'affidabilità (compare ≥ 0,5, scompare < 0,25), tenuta di 0,25 s dei punti
   mancanti, scarto dei salti isolati > 0,25 altezze immagine (accettati se si ripetono).
   Il rilevatore `pose` deve passare anche i punti poco affidabili (soglia ~0,15) e
   lasciare la decisione allo stabilizzatore.
2. **Camera 16:9** (1280×720) di default; misurare fps e costo di MediaPipe.
3. **Godot**: centro mano anche con il solo indice (`BodyMetrics.hand_center`); verificare
   che previsione e correzione dolce non amplifichino il rumore residuo; eventuale
   taratura del filtro One Euro sulle registrazioni.
4. **Indicazioni all'utente** nel menu o nella finestra di debug: luce, distanza (gomiti
   visibili), con un avviso se le mani sono spesso fuori campo.
5. Nuova registrazione con lo stesso protocollo (10 s fermo, movimenti lenti, veloci, su e
   giù, gioco) e confronto con le misure sopra.

### Criteri di accettazione (con persona a 1,5–2 m e luce accesa)
- mano destra presente ≥ 90% dei frame in cui il polso è nell'inquadratura;
- interruzioni > 0,3 s: al massimo 1 al minuto;
- rumore da fermo sullo schermo: 90° percentile ≤ 3 px;
- nessun salto > 60 px che non corrisponda a un movimento reale;
- l'utente lo giudica fluido giocando a Bolle, Tris e Taglia il filo.

## 11. Decisioni aperte

- Disposizione: proiezione su muro, pavimento o tavolo; posizione della camera.
- Numero di giocatori contemporanei (default 2) e se ognuno ha un solo marker.
- Inquadratura: solo busto o corpo intero (decide se servono anche, ginocchia, piedi).
- Significato di braccio, mano e faccia in ciascun gioco (fase 5).
- Tipo di marker fisico (cartoncino fluo, gommapiuma, LED).
