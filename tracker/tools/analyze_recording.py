"""Analisi di una registrazione del tracker (./tracker.sh --record file.jsonl).
Uso: tracker/.venv/bin/python -m tracker.tools.analyze_recording file.jsonl [--screen 1152x720] [--stabilize]

Misura ciò che rende il cursore poco fluido (docs/SPEC.md §10.2):
- quanto spesso i punti ci sono e quante volte compaiono/scompaiono;
- rumore ad alta frequenza (scarto dalla mediana di 5 frame), in camera e sullo schermo;
- la mano come la vede Godot: presenza, interruzioni, salti tra frame;
- con --stabilize: come sarebbe la mano facendo passare i punti grezzi nello
  stabilizzatore attuale (per provare le sue impostazioni su registrazioni vecchie)."""
from __future__ import annotations

import argparse
import json
import sys

import numpy as np

POINTS = ["nose", "shoulder_l", "shoulder_r", "elbow_r", "wrist_r", "index_r", "elbow_l", "wrist_l"]


def load(path: str) -> list[dict]:
    rows = [json.loads(line) for line in open(path, encoding="utf-8") if line.strip()]
    return [r for r in rows if "t" in r]


def series(rows: list[dict], src: str, name: str) -> np.ndarray:
    out = []
    for r in rows:
        if src == "raw":
            pts = r["raw"][0]["points"] if r["raw"] else {}
        else:
            pl = r["packet"]["players"]
            pts = pl[0].get("pose", {}) if pl else {}
        p = pts.get(name)
        out.append((p[0], p[1]) if p else (np.nan, np.nan))
    return np.array(out)


def gap_stats(present: np.ndarray, fps: float = 30.0) -> tuple[int, int]:
    """Interruzioni (sequenze di frame senza il punto) e quante durano più di 0,3 s."""
    gaps, run = [], 0
    for p in present:
        if not p:
            run += 1
        elif run:
            gaps.append(run)
            run = 0
    return len(gaps), int(np.sum(np.array(gaps) / fps > 0.3)) if gaps else 0


def stabilized_hand(rows: list[dict], params: dict | None = None) -> np.ndarray:
    """Mano destra (polso/indice) dopo lo stabilizzatore, dai punti grezzi registrati."""
    from tracker.stabilizer import Stabilizer
    from tracker.structs import Frame, FrameResult, Person, Point

    stab = Stabilizer(params)
    out = []
    for i, r in enumerate(rows):
        res = FrameResult(Frame(None, r["t"], i, kind="none"))
        if r["raw"]:
            person = Person(id="p1")
            person.points = {n: Point(*v) for n, v in r["raw"][0]["points"].items()}
            res.persons = [person]
        stab.process(res)
        pts = res.persons[0].points if res.persons else {}
        w, ix = pts.get("wrist_r"), pts.get("index_r")
        if w and ix:
            out.append(((w.x + ix.x) / 2, (w.y + ix.y) / 2))
        elif w or ix:
            q = w or ix
            out.append((q.x, q.y))
        else:
            out.append((np.nan, np.nan))
    return np.array(out)


def jitter(xy: np.ndarray, sx: float, sy: float) -> np.ndarray:
    x, y = xy[:, 0] * sx, xy[:, 1] * sy
    res = []
    for i in range(2, len(x) - 2):
        wx, wy = x[i - 2:i + 3], y[i - 2:i + 3]
        if not np.isnan(wx).any():
            res.append(np.hypot(x[i] - np.median(wx), y[i] - np.median(wy)))
    return np.array(res)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("file")
    ap.add_argument("--screen", default="1152x720", help="dimensioni dello schermo di gioco, es. 1152x720")
    ap.add_argument("--camera", default="", help="dimensioni dell'immagine della camera "
                    "(default: quelle registrate, altrimenti 640x480)")
    ap.add_argument("--stabilize", action="store_true", help="simula lo stabilizzatore sui punti grezzi")
    args = ap.parse_args(argv)
    sw, sh = (float(v) for v in args.screen.split("x"))
    rows = load(args.file)
    cam = args.camera or ("x".join(str(v) for v in rows[0]["camera"]) if rows and "camera" in rows[0] else "640x480")
    cw, ch = (float(v) for v in cam.split("x"))
    if len(rows) < 10:
        print("registrazione troppo corta")
        return 1
    t = np.array([r["t"] for r in rows])
    dt = np.diff(t)
    print(f"Frame {len(rows)} in {t[-1] - t[0]:.1f} s ({len(rows) / (t[-1] - t[0]):.1f} fps); intervalli >50 ms: {(dt > 0.05).sum()}")
    seen = [r for r in rows if r["raw"]]
    print(f"Persona vista nel {len(seen) / len(rows) * 100:.0f}% dei frame")
    if not seen:
        return 0
    print("\nPunti: presenza e lampeggi (compare/scompare)")
    for n in POINTS:
        pts = [r["raw"][0]["points"].get(n) for r in seen]
        pres = [p is not None and p[2] >= 0.5 for p in pts]  # come la vecchia soglia fissa
        flips = sum(1 for a, b in zip(pres, pres[1:]) if a != b)
        any_conf = np.mean([p is not None for p in pts]) * 100
        print(f"  {n:11s} {np.mean(pres) * 100:5.1f}%   lampeggi {flips:4d}   (con punti incerti {any_conf:5.1f}%)")
    print("\nRumore da fermo (mediana / 90° percentile, pixel)")
    for n in ["nose", "shoulder_r", "wrist_r", "index_r"]:
        jr, js = jitter(series(seen, "raw", n), cw, ch), jitter(series(seen, "pkt", n), sw, sh)
        if len(jr) > 10:
            print(f"  {n:11s} camera {np.median(jr):4.1f} / {np.percentile(jr, 90):4.1f}   schermo {np.median(js):4.1f} / {np.percentile(js, 90):4.1f}")
    wr, ix = series(seen, "pkt", "wrist_r"), series(seen, "pkt", "index_r")
    hand = np.where(np.isnan(wr), np.where(np.isnan(ix), np.nan, ix), np.where(np.isnan(ix), wr, (wr + ix) / 2))
    present = ~np.isnan(hand[:, 0])
    n_gaps, long_gaps = gap_stats(present)
    print(f"\nMano destra (come in Godot): presente {present.mean() * 100:.0f}%, interruzioni {n_gaps}, "
          f">0,3 s {long_gaps}")
    d = np.hypot(np.diff(hand[:, 0]) * sw, np.diff(hand[:, 1]) * sh)
    d = d[~np.isnan(d)]
    if len(d):
        print(f"  spostamento tra frame: mediana {np.median(d):.1f} px, 90° {np.percentile(d, 90):.1f} px, salti >60 px {int(np.sum(d > 60))}")
    if args.stabilize:
        sh_ = stabilized_hand(seen)
        sp = ~np.isnan(sh_[:, 0])
        g, lg = gap_stats(sp)
        ds = np.hypot(np.diff(sh_[:, 0]) * cw, np.diff(sh_[:, 1]) * ch)
        ds = ds[~np.isnan(ds)]
        print(f"  con lo stabilizzatore: presente {sp.mean() * 100:.0f}%, interruzioni {g}, >0,3 s {lg}"
              + (f", salti >60 px camera {int(np.sum(ds > 60))}" if len(ds) else ""))
    raw_w = series(seen, "raw", "wrist_r")
    v = raw_w[~np.isnan(raw_w[:, 0])]
    if len(v):
        print(f"  polso nell'immagine: y mediana {np.median(v[:, 1]):.2f} (1 = bordo basso)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
