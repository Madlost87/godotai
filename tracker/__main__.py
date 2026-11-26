"""Avvio: dalla radice del progetto, ./tracker.sh [opzioni]  (= tracker/.venv/bin/python -m tracker)."""
from __future__ import annotations

import argparse
import logging
import signal
import sys
from pathlib import Path

from .sources.camera import list_cameras
from .config import load_config


def parse_args(argv: list[str]) -> argparse.Namespace:
    ap = argparse.ArgumentParser(prog="tracker", description="Tracker del corpo → Godot (UDP)")
    ap.add_argument("--config", type=Path, help="file di configurazione (default tracker/config.json)")
    ap.add_argument("--debug", action="store_true", help="mostra la finestra di debug")
    ap.add_argument("--device", help="camera: indice /dev/videoN o 'auto'")
    ap.add_argument("--video", type=Path, help="usa un file video invece della camera")
    ap.add_argument("--port", type=int, help="porta UDP di Godot (sovrascrive outputs)")
    ap.add_argument("--control-port", type=int, help="porta del canale di controllo Godot → tracker")
    ap.add_argument("--model", choices=["lite", "full", "heavy"], help="modello della pose")
    ap.add_argument("--players", type=int, help="numero massimo di giocatori")
    ap.add_argument("--assign", choices=["zones", "arrival"], help="regola di assegnazione degli id")
    ap.add_argument("--synthetic", type=int, nargs="?", const=2, metavar="N",
                    help="niente camera: N persone finte (default 2), per provare Godot")
    ap.add_argument("--synthetic-kind", choices=["body", "contacts"], default="body",
                    help="con --synthetic: 'body' = scheletri, 'contacts' = solo punti di contatto (come un LiDAR)")
    ap.add_argument("--source", help="tipo di sorgente (plugin in tracker/sources/), es. camera, video, synthetic")
    ap.add_argument("--detectors", help="rilevatori da usare, separati da virgola (plugin in tracker/detectors/)")
    ap.add_argument("--record", type=Path, help="registra ogni frame (grezzo + pacchetto) in un file .jsonl")
    ap.add_argument("--list-plugins", action="store_true", help="elenca sorgenti, rilevatori, uscite ed esci")
    ap.add_argument("--max-frames", type=int, default=0, help="fermati dopo N frame (0 = mai)")
    ap.add_argument("--calibrate", action="store_true",
                    help="calibra con la scena Godot res://tools/calibration/calibration.tscn, poi continua a tracciare")
    ap.add_argument("--calibrate-only", action="store_true", help="come --calibrate, ma esce dopo aver salvato")
    ap.add_argument("--calibration-timeout", type=float, default=0.0, help="secondi massimi di calibrazione (0 = nessuno)")
    ap.add_argument("--uncalibrated", action="store_true", help="ignora calibration.json")
    ap.add_argument("--mapping", choices=["auto", "body_zone", "mirror", "stretch", "homography"],
                    help="come il sensore si mappa sullo schermo (default da config: auto)")
    ap.add_argument("--list-cameras", action="store_true", help="elenca le camere ed esci")
    ap.add_argument("-v", "--verbose", action="store_true")
    return ap.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO, format="%(levelname)s %(name)s: %(message)s")

    if args.list_cameras:
        for c in list_cameras():
            print(f"/dev/video{c['index']}: {c['name']}  {'immagini' if c['capture'] else 'solo metadati / non utilizzabile'}")
        return 0

    if args.list_plugins:
        from .detectors import DETECTORS
        from .identity import ASSIGNERS
        from .sinks import SINKS
        from .sources import SOURCES

        for reg, extra in ((SOURCES, "produces"), (DETECTORS, "accepts"), (SINKS, None), (ASSIGNERS, None)):
            print(f"{reg.kind}:")
            for name in reg.names():
                cls = reg.get(name)
                info = ""
                if extra == "produces":
                    info = f"produce '{cls.produces}'"
                elif extra == "accepts":
                    info = f"accetta {list(cls.accepts)}, fornisce {list(cls.provides)}"
                print(f"  {name:20s} {info}")
        return 0

    cfg = load_config(args.config)
    if args.device is not None:
        cfg["source"]["device"] = args.device
    if args.video is not None:
        cfg["source"].update(type="video", path=str(args.video))
    if args.port is not None:
        for o in cfg["outputs"]:
            if o.get("type", "udp") == "udp":
                o["port"] = args.port
    if args.control_port is not None:
        cfg["control"]["port"] = args.control_port
    if args.model is not None:
        cfg["detectors"].setdefault("pose", {})["model"] = args.model
    if args.players is not None:
        cfg["identity"]["max_players"] = args.players
        cfg["detectors"].setdefault("pose", {})["num_poses"] = args.players
    if args.assign is not None:
        cfg["identity"]["assign"] = args.assign
    if args.synthetic is not None:
        det = "synthetic" if args.synthetic_kind == "body" else "synthetic_contacts"
        cfg["source"] = {"type": "synthetic", "fps": 30}
        cfg["detectors"] = {det: {"enabled": True, "count": args.synthetic}}
        cfg["identity"]["max_players"] = max(cfg["identity"]["max_players"], args.synthetic)
    if args.source is not None:
        cfg["source"]["type"] = args.source
    if args.detectors is not None:
        names = [n.strip() for n in args.detectors.split(",") if n.strip()]
        cfg["detectors"] = {n: {**cfg["detectors"].get(n, {}), "enabled": True} for n in names}

    if args.uncalibrated:
        cfg["projection"]["calibration_file"] = "/dev/null/nessuna-calibrazione"
    if args.record is not None:
        cfg["outputs"].append({"type": "jsonl", "path": str(args.record)})
    if args.mapping is not None:
        cfg["projection"]["mode"] = args.mapping

    if args.calibrate or args.calibrate_only:
        from .calibration import run_calibration

        ok = run_calibration(cfg, debug=args.debug, timeout=args.calibration_timeout)
        if args.calibrate_only:
            return 0 if ok else 1
        if not ok:
            logging.getLogger("tracker").warning("calibrazione non riuscita: continuo con la calibrazione precedente (se c'è)")

    from .pipeline import build_pipeline  # importa MediaPipe: dopo il parsing, così --help è veloce

    pipeline = build_pipeline(cfg)
    stop = {"flag": False}
    signal.signal(signal.SIGINT, lambda *_: stop.update(flag=True))
    signal.signal(signal.SIGTERM, lambda *_: stop.update(flag=True))

    view = None
    if args.debug:
        from .debug_view import DebugView

        view = DebugView(mirror=bool(cfg["projection"].get("mirror", True)), projection=pipeline.projection)

    log = logging.getLogger("tracker")
    log.info("in esecuzione: invio a %s", ", ".join(f"{o.get('host')}:{o.get('port')}" for o in cfg["outputs"]))

    def on_result(result, packet) -> bool:
        if stop["flag"]:
            return False
        if view is not None:
            return view.show(result, packet, pipeline.fps)
        if result.frame.index % 150 == 0:
            log.info("%.1f fps, giocatori: %s", pipeline.fps, [p["id"] for p in packet["players"]])
        return True

    try:
        n = pipeline.run(on_result, args.max_frames)
        log.info("fermato dopo %d frame (%.1f fps)", n, pipeline.fps)
    finally:
        pipeline.close()
        if view is not None:
            view.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
