#!/bin/sh
# Verifica headless (senza finestra): import, avvio breve della scena, test.
# Esce con codice != 0 se qualcosa fallisce.
cd "$(dirname "$0")" || exit 1
fail=0

echo "== 1/4 Import =="
out=$(godot --headless --editor --quit --path . 2>&1)
echo "$out" | grep -E "ERROR|SCRIPT ERROR|Parse Error|WARNING" && fail=1

echo "== 2/4 Avvio breve della scena principale =="
out=$(godot --headless --path . --quit-after 120 2>&1)
echo "$out" | grep -E "ERROR|SCRIPT ERROR|Parse Error" && fail=1

echo "== 3/4 Test Godot (tests/, games/*/tests/, tools/*/tests/, examples/*/tests/) =="
for t in tests/*.gd games/*/tests/*.gd tools/*/tests/*.gd examples/*/tests/*.gd; do
	[ -e "$t" ] || continue
	echo "-- $t"
	out=$(timeout 120 godot --headless --path . -s "res://$t" 2>&1); st=$?
	[ "$st" -eq 124 ] && echo "TEMPO SCADUTO (120 s): $t"
	echo "$out" | grep -v -E "^Godot Engine|^$"
	[ "$st" -eq 0 ] || { echo "FALLITO: $t"; fail=1; }
	echo "$out" | grep -q -E "SCRIPT ERROR|Parse Error" && { echo "ERRORI DI SCRIPT: $t"; fail=1; }
done

echo "== 4/4 Test tracker Python (tracker/tests) =="
if [ -x tracker/.venv/bin/python ]; then
	out=$(tracker/.venv/bin/python -m pytest -q tracker/tests 2>&1); st=$?
	echo "$out" | tail -3
	[ "$st" -eq 0 ] || { echo "$out" | grep -E "^(FAILED|ERROR)"; echo "FALLITO: tracker/tests"; fail=1; }
else
	echo "saltato: tracker/.venv non presente"
fi

[ "$fail" -eq 0 ] && echo "== OK ==" || echo "== CI SONO ERRORI =="
exit "$fail"
