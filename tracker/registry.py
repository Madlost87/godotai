"""Registro generico nome → classe, usato da sorgenti, rilevatori, assegnatori e uscite."""
from __future__ import annotations

from typing import Callable, Generic, TypeVar

T = TypeVar("T")


class Registry(Generic[T]):
    def __init__(self, kind: str) -> None:
        self.kind = kind
        self._items: dict[str, T] = {}

    def register(self, name: str) -> Callable[[T], T]:
        def deco(obj: T) -> T:
            if name in self._items:
                raise ValueError(f"{self.kind} '{name}' registrato due volte")
            self._items[name] = obj
            return obj

        return deco

    def get(self, name: str) -> T:
        try:
            return self._items[name]
        except KeyError:
            raise ValueError(
                f"{self.kind} sconosciuto: '{name}'. Disponibili: {', '.join(sorted(self._items)) or 'nessuno'}"
            ) from None

    def names(self) -> list[str]:
        return sorted(self._items)

    def __contains__(self, name: str) -> bool:
        return name in self._items
