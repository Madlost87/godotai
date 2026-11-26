# Guida: cambiare o aggiungere un sensore

Oggi il sensore è una webcam con MediaPipe. Si può sostituire (LiDAR, camera di
profondità, sensori a pressione, tracker di terze parti…) **senza toccare i giochi**,
perché i giochi vedono solo il **protocollo v1** e le **capacità**.

## Tre modi, dal più semplice

### A. Un altro programma che parla il protocollo v1

Qualsiasi programma, in qualsiasi linguaggio, che manda pacchetti JSON via UDP a
`127.0.0.1:4242` nel formato v1 (`docs/SPEC.md` §5) sostituisce il tracker. Esempio minimo
di un sensore che vede solo punti di contatto:

```json
{"v": 1, "t": 12.3, "space": "screen", "caps": ["effectors"],
 "players": [{"id": "p1", "effectors": {"e0": [0.42, 0.61, 0.9], "e1": [0.55, 0.60, 0.8]}}]}
```

Controlla i pacchetti con `tracker/protocol.py: validate_packet()`. Se vuoi ricevere le
richieste dei giochi (giocatori, capacità), ascolta su `127.0.0.1:4243` i messaggi
`{"type": "session", ...}` (§5.1).

### B. Un nuovo plugin nel tracker Python (consigliato)

Così si riusano identità, stabilizzatore (niente punti che lampeggiano o saltano: il
rilevatore può passare anche i punti poco affidabili, con la loro `conf`),
proiezione/calibrazione, protocollo, uscite e test.

1. **Sorgente**: un file in `tracker/sources/`, si registra da solo.

```python
# tracker/sources/lidar2d.py
import time

from .base import SOURCES, FrameSource
from ..structs import Frame

@SOURCES.register("lidar2d")
class Lidar2DSource(FrameSource):
    produces = "scan2d"          # tipo di Frame.data

    def __init__(self, params):
        super().__init__(params)
        self.dev = open_lidar(params.get("port", "/dev/ttyUSB0"))   # driver del sensore
        self.index = 0

    def read(self):
        scan = self.dev.read_scan()          # es. [(angolo, distanza), ...]
        self.index += 1
        return Frame(scan, time.monotonic(), self.index, kind="scan2d")

    def close(self):
        self.dev.close()
```

2. **Rilevatore**: un file in `tracker/detectors/` che trasforma i dati in persone.

```python
# tracker/detectors/lidar_blobs.py
from .base import DETECTORS, Detector
from ..structs import Person, Point

@DETECTORS.register("lidar_blobs")
class LidarBlobs(Detector):
    accepts = ("scan2d",)            # deve corrispondere a Source.produces
    provides = ("effectors",)        # capacità annunciate ai giochi

    def process(self, frame, result):
        for blob in cluster(frame.data):              # punti vicini = una mano/un piede
            p = Person()
            p.effectors["e0"] = Point(blob.x, blob.y, blob.confidence)   # coordinate 0..1
            result.persons.append(p)
```

3. **Config**: in `tracker/config.json`

```json
"source": {"type": "lidar2d", "port": "/dev/ttyUSB0"},
"detectors": {"pose": {"enabled": false}, "lidar_blobs": {"enabled": true}}
```

oppure da riga di comando: `./tracker.sh --source lidar2d --detectors lidar_blobs`.
`./tracker.sh --list-plugins` mostra cosa c'è e cosa accetta/produce.

4. **Test**: come `tracker/tests/test_plugins_and_sensors.py`, che collega un LiDAR
   finto alla pipeline e controlla che i pacchetti siano validi.

Se sorgente e rilevatore non sono compatibili (es. `pose` con `scan2d`), la pipeline si
ferma subito con un messaggio chiaro.

### C. Più sensori insieme

Un rilevatore può completare le persone trovate da un altro (es. `pose` dalla camera +
un sensore di profondità che aggiunge la distanza). Per sorgenti diverse in parallelo
servirà una sorgente "composta" che produce un frame con più dati: da progettare quando
servirà, con lo stesso schema a plugin.

## Calibrazione

La calibrazione porta le coordinate del sensore su quelle dello schermo proiettato
(omografia in `tracker/calibration.json`). Il metodo `aruco` vale per le camere. Un
sensore che non vede i marker proiettati registra il suo metodo in
`tracker/calibration.py: CALIBRATION_METHODS` (es. toccare i 4 angoli dello schermo) e
lo si sceglie con `"calibration": {"method": "..."}`. Se il sensore dà già coordinate
dello schermo, basta mandare `"space": "screen"`.

## Capacità e giochi

| Capacità | Significa | Esempio di sensore |
|---|---|---|
| `pose` | scheletro (spalle, gomiti, polsi…) | camera + MediaPipe |
| `hands` | dettaglio delle mani (aperta, pizzico) | MediaPipe Hands |
| `face` | posizione e rotazione della testa | MediaPipe Face |
| `markers` | marker colorati tenuti in mano | camera + OpenCV |
| `effectors` | punti che "toccano" | mani dalla pose, tocchi di un LiDAR |

I giochi dichiarano in `game.json` cosa richiedono. Il menu avvisa se il sensore
collegato non lo offre. In Godot `BodyMetrics.effectors()` restituisce gli effettori
del sensore, o le mani se il sensore dà la pose: un gioco basato sugli effettori funziona
con entrambi (verificato in `tests/game_framework_test.gd` con Bolle).
