"""Tracker del corpo per giochi proiettati (docs/SPEC.md).

Pipeline: sorgente (camera/video) → rilevatori → proiezione → identità → protocollo v1 → uscite.
Ogni famiglia di componenti ha un registro (vedi `registry.py`): per aggiungere una
sorgente, un rilevatore, una regola di assegnazione o un'uscita basta un nuovo modulo
che si registra con un nome, poi lo si attiva da `config.json`.
"""
