class_name PlayerState
extends RefCounted
## Stato filtrato di un giocatore (docs/SPEC.md §6.1).
## Internamente i punti sono normalizzati (0..1); point() li restituisce in pixel.
##
## Nomi dei punti: "marker", nomi della pose ("wrist_r", "shoulder_l"...),
## "hand_r.wrist", "hand_r.index_tip"..., "face".
## Nomi dei valori: "marker.area", "hand_r.open", "hand_r.pinch", "face.yaw",
## "face.pitch", "face.roll", "face.mouth_open"...

var id: StringName
var screen_size: Vector2 = Vector2(1152, 648)
var last_seen: float = 0.0

## StringName -> {pos: Vector2, conf: float, t: float, filter: OneEuroFilter}
var _points: Dictionary = {}
## StringName -> {v: float, t: float}
var _values: Dictionary = {}


func _init(player_id: StringName) -> void:
	id = player_id


func has_point(point_name: StringName) -> bool:
	return _points.has(point_name)


## Posizione filtrata in pixel della viewport (Vector2.ZERO se assente).
func point(point_name: StringName) -> Vector2:
	return point_normalized(point_name) * screen_size


## Posizione filtrata normalizzata 0..1 (Vector2.ZERO se assente).
func point_normalized(point_name: StringName) -> Vector2:
	var e: Dictionary = _points.get(point_name, {})
	if e.is_empty():
		return Vector2.ZERO
	return e["pos"]


func confidence(point_name: StringName) -> float:
	var e: Dictionary = _points.get(point_name, {})
	return 0.0 if e.is_empty() else float(e["conf"])


func has_value(value_name: StringName) -> bool:
	return _values.has(value_name)


func value(value_name: StringName, default: float = 0.0) -> float:
	var e: Dictionary = _values.get(value_name, {})
	return default if e.is_empty() else float(e["v"])


func point_names() -> Array[StringName]:
	var out: Array[StringName] = []
	for k: StringName in _points.keys():
		out.append(k)
	return out


func value_names() -> Array[StringName]:
	var out: Array[StringName] = []
	for k: StringName in _values.keys():
		out.append(k)
	return out


func is_empty() -> bool:
	return _points.is_empty() and _values.is_empty()


## Applica la voce di un giocatore di un pacchetto v1. Campi malformati ignorati.
func apply(p: Dictionary, t: float, min_cutoff: float, beta: float) -> void:
	last_seen = t
	var marker: Variant = p.get("marker")
	if marker is Dictionary:
		_apply_xy_group(marker, &"marker", t, min_cutoff, beta)

	var pose: Variant = p.get("pose")
	if pose is Dictionary:
		for k: Variant in pose:
			_apply_array_point(StringName(str(k)), pose[k], t, min_cutoff, beta)

	var hands: Variant = p.get("hands")
	if hands is Dictionary:
		for side: Variant in hands:
			var h: Variant = hands[side]
			if not (h is Dictionary):
				continue
			var prefix := "hand_%s." % str(side)
			for k: Variant in h:
				var v: Variant = h[k]
				var key := StringName(prefix + str(k))
				if v is Array:
					_apply_array_point(key, v, t, min_cutoff, beta)
				elif _is_num(v):
					_values[key] = {"v": float(v), "t": t}

	var face: Variant = p.get("face")
	if face is Dictionary:
		_apply_xy_group(face, &"face", t, min_cutoff, beta)


## Rimuove punti e valori non aggiornati da più di `timeout` secondi.
func expire(t: float, timeout: float) -> void:
	for k: StringName in _points.keys():
		if t - float(_points[k]["t"]) > timeout:
			_points.erase(k)
	for k: StringName in _values.keys():
		if t - float(_values[k]["t"]) > timeout:
			_values.erase(k)


## Gruppo con x/y (punto `group`) + altri campi numerici (valori "group.campo").
func _apply_xy_group(g: Dictionary, group: StringName, t: float, min_cutoff: float, beta: float) -> void:
	var x: Variant = g.get("x")
	var y: Variant = g.get("y")
	if _is_num(x) and _is_num(y):
		_set_point(group, Vector2(float(x), float(y)), 1.0, t, min_cutoff, beta)
	for k: Variant in g:
		if k == "x" or k == "y":
			continue
		var v: Variant = g[k]
		if _is_num(v):
			_values[StringName("%s.%s" % [group, str(k)])] = {"v": float(v), "t": t}


func _apply_array_point(key: StringName, a: Variant, t: float, min_cutoff: float, beta: float) -> void:
	if not (a is Array) or a.size() < 2 or not _is_num(a[0]) or not _is_num(a[1]):
		return
	var conf := 1.0
	if a.size() > 2 and _is_num(a[2]):
		conf = float(a[2])
	_set_point(key, Vector2(float(a[0]), float(a[1])), conf, t, min_cutoff, beta)


func _set_point(key: StringName, pos: Vector2, conf: float, t: float, min_cutoff: float, beta: float) -> void:
	var e: Dictionary = _points.get(key, {})
	if e.is_empty():
		e = {"filter": OneEuroFilter.new(min_cutoff, beta)}
		_points[key] = e
	var f: OneEuroFilter = e["filter"]
	f.min_cutoff = min_cutoff
	f.beta = beta
	e["pos"] = f.filter(pos, t)
	e["conf"] = conf
	e["t"] = t


static func _is_num(v: Variant) -> bool:
	return v is float or v is int
