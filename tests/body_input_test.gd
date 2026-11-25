extends SceneTree
## Test headless del ponte BodyInput (docs/SPEC.md §6.1, fase 1).

const TEST_PORT := 42424

var _fail: int = 0
var _entered: Array[StringName] = []
var _lost: Array[StringName] = []


func _check(cond: bool, msg: String) -> void:
	print(("  ok    " if cond else "  FAIL  ") + msg)
	if not cond:
		_fail += 1


func _initialize() -> void:
	await process_frame
	var bi: Node = root.get_node("BodyInput")
	bi.simulator_fallback = false
	bi.player_entered.connect(func(id: StringName) -> void: _entered.append(id))
	bi.player_lost.connect(func(id: StringName) -> void: _lost.append(id))

	_test_packets(bi)
	_test_filter(bi)
	await _test_udp(bi)
	await _test_replay(bi)
	_test_recording(bi)
	quit(1 if _fail > 0 else 0)


func _test_packets(bi: Node) -> void:
	print("-- pacchetti")
	var size: Vector2 = root.get_visible_rect().size
	var t: float = bi.now()
	var ok: bool = bi.ingest_packet({"v": 1, "players": [{
		"id": "red",
		"marker": {"x": 0.5, "y": 0.25, "area": 0.01},
		"pose": {"wrist_r": [0.25, 0.5, 0.9]},
		"hands": {"r": {"index_tip": [0.3, 0.4], "open": 0.8}},
		"face": {"x": 0.1, "y": 0.1, "yaw": -12.0},
	}]}, t)
	_check(ok, "pacchetto valido accettato")
	_check(_entered == [&"red"], "player_entered(red)")
	var p: PlayerState = bi.get_player(&"red")
	_check(p != null, "giocatore red presente")
	_check(p.point(&"marker").is_equal_approx(Vector2(0.5, 0.25) * size), "marker in pixel")
	_check(is_equal_approx(p.confidence(&"wrist_r"), 0.9), "affidabilità del polso")
	_check(p.has_point(&"hand_r.index_tip") and is_equal_approx(p.value(&"hand_r.open"), 0.8), "mano destra")
	_check(p.has_point(&"face") and is_equal_approx(p.value(&"face.yaw"), -12.0), "faccia")
	_check(is_equal_approx(p.value(&"marker.area"), 0.01), "area del marker")
	_check(not p.has_point(&"elbow_r"), "punto assente = non visto")

	_check(not bi.ingest_packet({"v": 2, "players": [{"id": "blue", "marker": {"x": 0.1, "y": 0.1}}]}, t), "versione sconosciuta ignorata")
	_check(not bi.ingest_packet("rotto", t) and not bi.ingest_packet({"v": 1}, t), "pacchetti malformati ignorati")
	bi.ingest_packet({"v": 1, "players": [{"id": "blue", "marker": {"x": "a"}, "pose": {"wrist_r": "x"}}, {"nome": "senza id"}]}, t)
	_check(bi.get_player(&"blue") == null and _entered.size() == 1, "giocatore senza dati validi non creato")

	bi.update_timeouts(t + 1.0)
	_check(_lost == [&"red"] and bi.get_player(&"red") == null, "timeout → player_lost(red)")
	_entered.clear()
	_lost.clear()


func _test_filter(bi: Node) -> void:
	print("-- filtro One Euro")
	var t: float = bi.now() + 10.0
	var max_dev := 0.0
	for i in 60:
		var noise := 0.01 if i % 2 == 0 else -0.01
		bi.ingest_packet({"v": 1, "players": [{"id": "red", "marker": {"x": 0.5 + noise, "y": 0.5}}]}, t + i / 30.0)
		if i >= 20:
			max_dev = maxf(max_dev, absf(bi.get_player(&"red").point_filtered(&"marker").x - 0.5))
	_check(max_dev < 0.004, "tremolio ±0.010 ridotto a ±%.4f" % max_dev)
	for i in 30:
		bi.ingest_packet({"v": 1, "players": [{"id": "red", "marker": {"x": 0.9, "y": 0.5}}]}, t + 2.0 + i / 30.0)
	var x: float = bi.get_player(&"red").point_filtered(&"marker").x
	_check(x > 0.88, "spostamento seguito entro 1 s (x=%.3f)" % x)
	bi.update_timeouts(t + 10.0)
	_entered.clear()
	_lost.clear()


func _test_udp(bi: Node) -> void:
	print("-- UDP")
	_check(bi.listen(TEST_PORT), "in ascolto su %d" % TEST_PORT)
	var peer := PacketPeerUDP.new()
	peer.set_dest_address("127.0.0.1", TEST_PORT)
	peer.put_packet("non json".to_utf8_buffer())
	peer.put_packet(JSON.stringify({"v": 1, "fps": 30.0, "players": [{"id": "yellow", "marker": {"x": 0.2, "y": 0.8}}]}).to_utf8_buffer())
	for i in 60:
		await process_frame
		if bi.get_player(&"yellow") != null:
			break
	_check(bi.get_player(&"yellow") != null, "pacchetto UDP ricevuto (yellow)")
	_check(bi.source_name() == "UDP" and is_equal_approx(bi.tracker_fps, 30.0), "sorgente UDP, fps del tracker")
	await create_timer(0.5).timeout
	_check(bi.get_player(&"yellow") == null, "yellow perso quando il tracker tace")
	_entered.clear()
	_lost.clear()


func _test_replay(bi: Node) -> void:
	print("-- replay")
	var size: Vector2 = root.get_visible_rect().size
	var finished: Array[bool] = [false]
	bi.replay_finished.connect(func() -> void: finished[0] = true)
	_check(bi.play_recording("res://recordings/test_wave.jsonl"), "registrazione caricata")
	_check(bi.source_name() == "REPLAY", "sorgente REPLAY")
	var max_x := 0.0
	var t0 := Time.get_ticks_msec()
	while not finished[0] and Time.get_ticks_msec() - t0 < 3000:
		await process_frame
		var red: PlayerState = bi.get_player(&"red")
		if red != null:
			max_x = maxf(max_x, red.point(&"marker").x)
	_check(finished[0], "replay_finished emesso")
	_check(_entered.has(&"red") and _entered.has(&"blue"), "red e blue entrati")
	_check(max_x > 0.7 * size.x, "red si è mosso verso destra (x max %.0f)" % max_x)
	_check(bi.source_name() == "UDP", "a fine replay si torna a UDP")
	_check(not bi.play_recording("res://recordings/non_esiste.jsonl"), "file mancante rifiutato")
	_entered.clear()
	_lost.clear()


func _test_recording(bi: Node) -> void:
	print("-- registrazione")
	var path := "user://test_rec.jsonl"
	_check(bi.start_recording(path), "registrazione avviata")
	bi.ingest_packet({"v": 1, "players": [{"id": "blue", "marker": {"x": 0.3, "y": 0.3}}]})
	bi.ingest_packet({"v": 1, "players": [{"id": "blue", "marker": {"x": 0.4, "y": 0.3}}]})
	bi.stop_recording()
	var lines := FileAccess.get_file_as_string(path).strip_edges().split("\n")
	_check(lines.size() == 2, "2 righe registrate")
	var first: Variant = JSON.parse_string(lines[0])
	_check(first is Dictionary and first["p"]["players"][0]["id"] == "blue", "contenuto del pacchetto conservato")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
