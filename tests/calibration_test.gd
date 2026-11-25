extends SceneTree
## Scena di calibrazione: layout dei marker, invio al tracker, stati, cambio vista.

const CONTROL_PORT := 42426

var _fail: int = 0


func _check(cond: bool, msg: String) -> void:
	print(("  ok    " if cond else "  FAIL  ") + msg)
	if not cond:
		_fail += 1


func _initialize() -> void:
	await process_frame
	var bi: Node = root.get_node("BodyInput")
	bi.simulator_fallback = false
	bi.control_port = CONTROL_PORT
	var rx := PacketPeerUDP.new()
	_check(rx.bind(CONTROL_PORT, "127.0.0.1") == OK, "porta di controllo di test in ascolto")

	var scene: Node = load("res://tools/calibration/calibration.tscn").instantiate()
	root.add_child(scene)
	await process_frame

	# Pattern condivisi con Python
	_check(scene.patterns.size() == 4, "4 pattern ArUco caricati")
	for id: int in scene.patterns:
		var rows: PackedStringArray = scene.patterns[id]
		_check(rows.size() == 6 and rows[0] == "000000" and rows[5] == "000000", "marker %d: 6 righe con bordo nero" % id)

	# Layout in pixel
	var size: Vector2 = root.get_visible_rect().size
	var lay: Dictionary = scene.compute_layout(Vector2(1280, 720))
	var tl: PackedVector2Array = lay[0]
	var br: PackedVector2Array = lay[2]
	_check(tl[0].is_equal_approx(Vector2(28.8, 28.8)), "marker 0 in alto a sinistra col margine")
	_check(is_equal_approx(tl[1].x - tl[0].x, 158.4) and is_equal_approx(tl[3].y - tl[0].y, 158.4), "marker quadrati (lato 22% del lato corto)")
	_check(br[2].is_equal_approx(Vector2(1280 - 28.8, 720 - 28.8)), "marker 2 in basso a destra")

	# Messaggio al tracker
	var msg: Variant = null
	for i in 120:
		await process_frame
		if rx.get_available_packet_count() > 0:
			msg = JSON.parse_string(rx.get_packet().get_string_from_utf8())
			break
	_check(msg is Dictionary and msg["type"] == "calibration_layout", "layout inviato sul canale di controllo")
	if msg is Dictionary:
		var m: Dictionary = msg["markers"]
		_check(m.size() == 4 and (m["0"] as Array).size() == 4, "4 marker con 4 angoli")
		var c0: Array = m["0"][0]
		_check(is_equal_approx(float(c0[0]), scene.layout[0][0].x / size.x), "angoli normalizzati sullo schermo")
		var c2: Array = m["2"][2]
		_check(float(c2[0]) > 0.9 and float(c2[1]) > 0.9, "marker 2 vicino all'angolo in basso a destra")

	# Stati mandati dal tracker
	var label: Label = scene.get_node("HUD/Status")
	_check(label.text.contains("--calibrate"), "senza tracker: istruzioni per avviarlo")
	bi.ingest_packet({"v": 1, "players": [], "calibration": {"state": "searching", "found": [0, 3]}})
	_check(label.text.contains("0, 3"), "searching: mostra i marker visti")
	bi.ingest_packet({"v": 1, "players": [], "calibration": {"state": "collecting", "found": [0, 1, 2, 3], "progress": 0.5}})
	_check(label.text.contains("50%"), "collecting: percentuale")
	_check(scene.view == 0 and not scene.get_node("Players").visible, "ancora in vista marker")
	bi.ingest_packet({"v": 1, "players": [], "calibration": {"state": "done", "error": 0.0042}})
	_check(scene.view == 1 and scene.get_node("Players").visible, "done: passa da sola alla verifica")
	_check(label.text.contains("0.42%"), "done: mostra l'errore")

	# Cambio vista con l'azione
	var ev := InputEventAction.new()
	ev.action = &"calibration_toggle_view"
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	await process_frame
	_check(scene.view == 0, "azione calibration_toggle_view torna ai marker")

	rx.close()
	quit(1 if _fail > 0 else 0)
