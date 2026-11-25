"""Caricamento automatico dei plugin: ogni modulo dentro un pacchetto (sources/,
detectors/, ...) viene importato, e importandolo si registra nel suo registro.
Per aggiungere un plugin basta creare il file: non serve toccare nessun elenco."""
from __future__ import annotations

import importlib
import pkgutil
from types import ModuleType


def load_plugins(package: ModuleType, skip: tuple[str, ...] = ("base",)) -> list[str]:
    loaded = []
    for info in pkgutil.iter_modules(package.__path__):
        if info.name.startswith("_") or info.name in skip:
            continue
        importlib.import_module(f"{package.__name__}.{info.name}")
        loaded.append(info.name)
    return loaded
