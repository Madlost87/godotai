extends RefCounted
## Rilegge una sessione registrata (.jsonl: una riga {"dt": secondi, "p": pacchetto}).

var loop: bool = false

var _entries: Array[Dictionary] = []
var _start: float = 0.0
var _index: int = 0


func load_file(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("BodyInput: impossibile aprire la registrazione %s" % path)
		return false
	var json := JSON.new()
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.is_empty() or json.parse(line) != OK:
			continue
		var d: Variant = json.data
		if d is Dictionary and d.get("p") is Dictionary and (d.get("dt") is float or d.get("dt") is int):
			_entries.append({"dt": float(d["dt"]), "p": d["p"]})
	return not _entries.is_empty()


func start(t: float) -> void:
	_start = t
	_index = 0


## Pacchetti il cui momento è arrivato, in ordine.
func poll(t: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	while _index < _entries.size() and float(_entries[_index]["dt"]) <= t - _start:
		out.append(_entries[_index]["p"])
		_index += 1
	if loop and _index >= _entries.size():
		start(t)
	return out


func is_finished() -> bool:
	return not loop and _index >= _entries.size()
