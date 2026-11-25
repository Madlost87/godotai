extends SceneTree
## Fluidità a schermo: una mano si muove a velocità costante; il "sensore" manda 30
## campioni/s con il tempo di scatto esatto ("t"), ma arrivano con ritardi irregolari
## (a volte due nello stesso frame). Si misura il movimento visto frame per frame con
## e senza BodyInput.display_smoothing.

const SPEED := 0.6  # schermi al secondo
const RATE := 30.0
const DURATION := 1.6

var _fail: int = 0


func _check(cond: bool, msg: String) -> void:
	print(("  ok    " if cond else "  FAIL  ") + msg)
	if not cond:
		_fail += 1


func _run(bi: Node, smoothing: bool, id: String) -> Dictionary:
	bi.display_smoothing = smoothing
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var start: float = bi.now()
	var k := 0
	var next_arrival := start
	var xs: Array[float] = []
	var ts: Array[float] = []
	var errs: Array[float] = []
	while bi.now() - start < DURATION:
		var now: float = bi.now()
		while next_arrival <= now:  # consegna tutti i campioni "arrivati"
			var sample_t := k / RATE
			bi.ingest_packet({"v": 1, "t": 1000.0 + sample_t, "players": [
				{"id": id, "pose": {"wrist_r": [0.1 + SPEED * sample_t, 0.5, 1.0]}}]}, next_arrival)
			k += 1
			next_arrival = start + k / RATE + rng.randf_range(0.0, 0.025)  # ritardo irregolare 0–25 ms
		var p: RefCounted = bi.get_player(StringName(id))
		if p != null and now - start > 0.4:  # dopo l'avvio del filtro
			var x: float = p.point_normalized(&"wrist_r").x
			xs.append(x)
			ts.append(now)
			errs.append(absf(x - (0.1 + SPEED * (now - start))))
		await process_frame
	# Velocità vista tra frame consecutivi
	var speeds: Array[float] = []
	var stalls := 0
	for i in range(1, xs.size()):
		var dt := ts[i] - ts[i - 1]
		if dt <= 0.0:
			continue
		var v := (xs[i] - xs[i - 1]) / dt
		speeds.append(v)
		if absf(v) < SPEED * 0.05:
			stalls += 1
	var mean := 0.0
	for v in speeds:
		mean += v
	mean /= speeds.size()
	var var_sum := 0.0
	for v in speeds:
		var_sum += (v - mean) * (v - mean)
	var cv := sqrt(var_sum / speeds.size()) / absf(mean)
	var err_mean := 0.0
	for e in errs:
		err_mean += e
	err_mean /= errs.size()
	bi.update_timeouts(bi.now() + 10.0)
	return {"cv": cv, "stalls": float(stalls) / speeds.size(), "lag_ms": err_mean / SPEED * 1000.0, "frames": speeds.size()}


## La mano si muove e poi si ferma di colpo: quanto il punto va oltre, e se si assesta.
func _run_stop(bi: Node) -> Dictionary:
	bi.display_smoothing = true
	var start: float = bi.now()
	var k := 0
	var stop_x := 0.1 + SPEED * 0.6
	var overshoot := 0.0
	var final_err := 1.0
	while bi.now() - start < 1.4:
		var now: float = bi.now()
		while start + k / RATE <= now:
			var st := k / RATE
			var x := 0.1 + SPEED * minf(st, 0.6)  # si ferma a 0.6 s
			bi.ingest_packet({"v": 1, "t": 2000.0 + st, "players": [{"id": "c", "pose": {"wrist_r": [x, 0.5, 1.0]}}]}, start + st)
			k += 1
		var p: RefCounted = bi.get_player(&"c")
		if p != null and now - start > 0.6:
			var shown: float = p.point_normalized(&"wrist_r").x
			overshoot = maxf(overshoot, shown - stop_x)
			final_err = absf(shown - stop_x)
		await process_frame
	bi.update_timeouts(bi.now() + 10.0)
	return {"overshoot": overshoot, "final_err": final_err}


func _initialize() -> void:
	await process_frame
	var bi: Node = root.get_node("BodyInput")
	bi.simulator_fallback = false
	var off: Dictionary = await _run(bi, false, "a")
	var on: Dictionary = await _run(bi, true, "b")
	for r: Array in [["senza", off], ["con", on]]:
		var d: Dictionary = r[1]
		print("  %s fluidità: variazione della velocità %.0f%%, frame fermi %.0f%%, ritardo medio %.0f ms (%d frame)" % [
			r[0], d["cv"] * 100.0, d["stalls"] * 100.0, d["lag_ms"], d["frames"]])
	_check(on["cv"] < 0.35, "con fluidità: velocità a schermo regolare (variazione %.0f%% < 35%%)" % (on["cv"] * 100.0))
	_check(on["cv"] < off["cv"] * 0.5, "almeno il doppio più regolare che senza")
	_check(on["stalls"] < 0.05, "con fluidità: quasi nessun frame fermo (%.0f%%)" % (on["stalls"] * 100.0))
	_check(on["lag_ms"] <= off["lag_ms"] + 5.0, "nessun ritardo in più rispetto a senza")
	var stop: Dictionary = await _run_stop(bi)
	print("  arresto improvviso: oltre il punto di arrivo di %.1f%% dello schermo, errore finale %.2f%%" % [
		stop["overshoot"] * 100.0, stop["final_err"] * 100.0])
	_check(stop["overshoot"] < 0.025, "arresto: va oltre di meno del 2,5% dello schermo")
	_check(stop["final_err"] < 0.003, "arresto: poi si ferma nel punto giusto")
	bi.display_smoothing = true
	quit(1 if _fail > 0 else 0)
