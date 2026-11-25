class_name PlayerState
extends RefCounted
## Stato filtrato di un giocatore (docs/SPEC.md §6.1).
## Internamente i punti sono normalizzati (0..1); point() li restituisce in pixel.
##
## Nomi dei punti: "marker", nomi della pose ("wrist_r", "shoulder_l"...),
## "hand_r.wrist", "hand_r.index_tip"..., "face", "effector.<nome>" (punti di contatto
## dati dal sensore, es. un LiDAR; vedi BodyMetrics.effectors).
## Nomi dei valori: "marker.area", "hand_r.open", "hand_r.pinch", "face.yaw",
## "face.pitch", "face.roll", "face.mouth_open"...
##
## Fluidità: il sensore manda ~30 campioni/s, lo schermo ne mostra 60. Per non far
## muovere i punti "a scalini", point() restituisce una posizione continua:
## - tra un campione e l'altro il punto prosegue con la sua velocità (al massimo per
##   extrapolation_limit secondi);
## - quando arriva un campione nuovo, la differenza con ciò che era a schermo non
##   scatta ma si assorbe in ~correction_time secondi.
## point_filtered() dà invece l'ultimo campione filtrato, senza questi accorgimenti.

## Previsione e correzione dolce attive (BodyInput.display_smoothing).
var display_smoothing: bool = true
var extrapolation_limit: float = 0.05
var correction_time: float = 0.06
## Oltre questa distanza (normalizzata) un salto è considerato un teletrasporto: niente correzione dolce.
const MAX_CORRECTION := 0.15
## Velocità massima credibile, in schermi al secondo (oltre: rumore).
const MAX_SPEED := 6.0

var id: StringName
var screen_size: Vector2 = Vector2(1152, 648)
var last_seen: float = 0.0

## StringName -> {pos, vel, corr: Vector2; conf, t (arrivo), ts (scatto): float; filter}
var _points: Dictionary = {}
## StringName -> {v: float, t: float}
var _values: Dictionary = {}

# Parametri del campione in corso di applicazione (vedi apply).
var _t: float = 0.0
var _ts: float = 0.0
var _min_cutoff: float = 1.0
var _beta: float = 10.0


func _init(player_id: StringName) -> void:
	id = player_id


func has_point(point_name: StringName) -> bool:
	return _points.has(point_name)


## Posizione in pixel della viewport, fluida (Vector2.ZERO se assente).
func point(point_name: StringName) -> Vector2:
	return point_normalized(point_name) * screen_size


## Posizione normalizzata 0..1, fluida (Vector2.ZERO se assente).
func point_normalized(point_name: StringName) -> Vector2:
	var e: Dictionary = _points.get(point_name, {})
	if e.is_empty():
		return Vector2.ZERO
	if not display_smoothing:
		return e["pos"]
	return _display(e, Time.get_ticks_usec() / 1000000.0)


## Ultimo campione filtrato (normalizzato), senza previsione né correzione dolce.
func point_filtered(point_name: StringName) -> Vector2:
	var e: Dictionary = _points.get(point_name, {})
	return Vector2.ZERO if e.is_empty() else e["pos"]


## Velocità stimata in schermi al secondo (normalizzata).
func velocity_normalized(point_name: StringName) -> Vector2:
	var e: Dictionary = _points.get(point_name, {})
	return Vector2.ZERO if e.is_empty() else e["vel"]


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
## t = istante di arrivo (orologio di BodyInput: scadenze e previsione);
## sample_t = istante di scatto del sensore (campo "t" del pacchetto: filtro e velocità),
## se manca si usa t.
func apply(p: Dictionary, t: float, min_cutoff: float, beta: float, sample_t: float = NAN) -> void:
	last_seen = t
	_t = t
	_ts = t if is_nan(sample_t) else sample_t
	_min_cutoff = min_cutoff
	_beta = beta
	var marker: Variant = p.get("marker")
	if marker is Dictionary:
		_apply_xy_group(marker, &"marker")

	var pose: Variant = p.get("pose")
	if pose is Dictionary:
		for k: Variant in pose:
			_apply_array_point(StringName(str(k)), pose[k])

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
					_apply_array_point(key, v)
				elif _is_num(v):
					_values[key] = {"v": float(v), "t": t}

	var effectors: Variant = p.get("effectors")
	if effectors is Dictionary:
		for k: Variant in effectors:
			_apply_array_point(StringName("effector." + str(k)), effectors[k])

	var face: Variant = p.get("face")
	if face is Dictionary:
		_apply_xy_group(face, &"face")


## Rimuove punti e valori non aggiornati da più di `timeout` secondi.
func expire(t: float, timeout: float) -> void:
	for k: StringName in _points.keys():
		if t - float(_points[k]["t"]) > timeout:
			_points.erase(k)
	for k: StringName in _values.keys():
		if t - float(_values[k]["t"]) > timeout:
			_values.erase(k)


## Posizione mostrata all'istante `at` (orologio di arrivo).
func _display(e: Dictionary, at: float) -> Vector2:
	var elapsed := maxf(at - float(e["t"]), 0.0)
	var pos: Vector2 = e["pos"]
	var vel: Vector2 = e["vel"]
	var corr: Vector2 = e["corr"]
	return pos + vel * minf(elapsed, extrapolation_limit) + corr * exp(-elapsed / maxf(correction_time, 0.001))


## Gruppo con x/y (punto `group`) + altri campi numerici (valori "group.campo").
func _apply_xy_group(g: Dictionary, group: StringName) -> void:
	var x: Variant = g.get("x")
	var y: Variant = g.get("y")
	if _is_num(x) and _is_num(y):
		_set_point(group, Vector2(float(x), float(y)), 1.0)
	for k: Variant in g:
		if k == "x" or k == "y":
			continue
		var v: Variant = g[k]
		if _is_num(v):
			_values[StringName("%s.%s" % [group, str(k)])] = {"v": float(v), "t": _t}


func _apply_array_point(key: StringName, a: Variant) -> void:
	if not (a is Array) or a.size() < 2 or not _is_num(a[0]) or not _is_num(a[1]):
		return
	var conf := 1.0
	if a.size() > 2 and _is_num(a[2]):
		conf = float(a[2])
	_set_point(key, Vector2(float(a[0]), float(a[1])), conf)


func _set_point(key: StringName, raw: Vector2, conf: float) -> void:
	var e: Dictionary = _points.get(key, {})
	var is_new := e.is_empty()
	if is_new:
		e = {"filter": OneEuroFilter.new(_min_cutoff, _beta), "vel": Vector2.ZERO, "corr": Vector2.ZERO}
		_points[key] = e
	var shown := Vector2.ZERO if is_new else _display(e, _t)
	var f: OneEuroFilter = e["filter"]
	f.min_cutoff = _min_cutoff
	f.beta = _beta
	var pos := f.filter(raw, _ts)
	if not is_new:
		var dt := _ts - float(e["ts"])
		if dt > 0.0001:
			var inst: Vector2 = ((pos - (e["pos"] as Vector2)) / dt).limit_length(MAX_SPEED)
			e["vel"] = (e["vel"] as Vector2).lerp(inst, 0.6)
		var corr := shown - pos
		e["corr"] = corr if corr.length() <= MAX_CORRECTION else Vector2.ZERO
	e["pos"] = pos
	e["conf"] = conf
	e["t"] = _t
	e["ts"] = _ts


static func _is_num(v: Variant) -> bool:
	return v is float or v is int
