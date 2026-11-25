extends SceneTree
## Framework dei giochi: regole che OGNI gioco in games/ deve rispettare, il menu
## (launcher), BodyGame (sessione, uscita al menu) e il cambio di sensore (un sensore
## che dà solo punti di contatto, come un LiDAR, deve far funzionare i giochi).
## Nota: con "-s" le classi che usano l'autoload BodyInput si caricano con load().

const LAUNCHER := "res://launcher/launcher.tscn"

var _fail: int = 0
var _bi: Node


func _check(cond: bool, msg: String) -> void:
	print(("  ok    " if cond else "  FAIL  ") + msg)
	if not cond:
		_fail += 1


func _initialize() -> void:
	await process_frame
	_bi = root.get_node("BodyInput")
	_bi.simulator_fallback = false
	_bi.control_port = 42430
	_test_every_game_follows_the_rules()
	await _test_sensor_without_skeleton()
	await _test_launcher_and_body_game()
	quit(1 if _fail > 0 else 0)


func _test_every_game_follows_the_rules() -> void:
	print("-- regole per ogni gioco in games/")
	var registry: GDScript = load("res://core/game/game_registry.gd")
	var manifest_script: GDScript = load("res://core/game/game_manifest.gd")
	var folders: PackedStringArray = registry.game_folders()
	_check(not folders.is_empty(), "almeno un gioco (%s)" % ", ".join(folders))
	_check(not folders.has("res://games/_template"), "il modello _template non è un gioco")
	for folder in folders + PackedStringArray(["res://games/_template"]):
		var m: RefCounted = manifest_script.load_from(folder)
		_check(m.is_valid(), "%s: game.json valido %s" % [folder.get_file(), m.errors])
		var scene: PackedScene = load(m.scene_path) if ResourceLoader.exists(m.scene_path) else null
		var root_script: Script = null
		if scene != null:
			var inst := scene.instantiate()
			root_script = inst.get_script()
			inst.free()
		var base_ok := false
		while root_script != null:
			if root_script.resource_path == "res://core/game/body_game.gd":
				base_ok = true
				break
			root_script = root_script.get_base_script()
		_check(base_ok, "%s: la scena principale estende BodyGame" % folder.get_file())
		var tests := DirAccess.get_files_at(folder + "/tests") if DirAccess.dir_exists_absolute(folder + "/tests") else PackedStringArray()
		_check(Array(tests).any(func(f: String) -> bool: return f.ends_with("_test.gd")), "%s: ha almeno un test in tests/" % folder.get_file())
	var games: Array = registry.list_games()
	_check(games.any(func(g: RefCounted) -> bool: return g.id == "bubbles"), "il registro trova Bolle")
	var bad: RefCounted = manifest_script.load_from("res://tests")  # cartella senza game.json
	_check(not bad.is_valid(), "manifest mancante → non valido")


func _feed(players: Array, seconds: float, caps: Variant = null) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < seconds * 1000.0:
		var pkt := {"v": 1, "players": players}
		if caps != null:
			pkt["caps"] = caps
		_bi.ingest_packet(pkt)
		await process_frame


func _test_sensor_without_skeleton() -> void:
	print("-- sensore senza scheletro (es. LiDAR): solo effettori")
	var contacts := [{"id": "p1", "effectors": {"e0": [0.3, 0.4, 1.0], "e1": [0.7, 0.6, 1.0]}}]
	await _feed(contacts, 0.2)  # niente "caps": dedotte dai campi
	_check(Array(_bi.capabilities) == ["effectors"], "capacità dedotte: %s" % str(_bi.capabilities))
	var colliders: Node2D = load("res://core/body/body_colliders.gd").new()
	root.add_child(colliders)
	await _feed(contacts, 0.2, ["effectors"])
	_check(colliders.get_part(&"p1", "e0") != null and colliders.get_part(&"p1", "e1") != null, "aree sugli effettori e0, e1")
	var metrics: GDScript = load("res://core/body/body_metrics.gd")
	var p: RefCounted = _bi.get_player(&"p1")
	_check(metrics.effectors(p).size() == 2 and is_nan(metrics.arm_raised(p, "r")), "effettori sì, metriche della pose no (NAN)")

	# Il gioco Bolle funziona anche così: una bolla sotto un punto di contatto scoppia.
	var bubbles: Node2D = load("res://games/bubbles/bubbles.tscn").instantiate()
	bubbles.auto_spawn = false
	root.add_child(bubbles)
	await process_frame
	bubbles.start_round()
	var vp: Vector2 = root.get_visible_rect().size
	var b: Variant = bubbles.spawn_bubble(Vector2(0.3, 0.4) * vp, 0, vp.y * 0.08, 0.0)
	await _feed(contacts, 0.3, ["effectors"])
	_check(bubbles.score == 1, "Bolle con un sensore a contatto: la bolla scoppia (+1)")
	_check(bubbles.missing_capabilities().is_empty(), "Bolle non segnala capacità mancanti (le richiede: effectors)")
	bubbles.queue_free()
	colliders.queue_free()
	await create_timer(0.4).timeout  # il giocatore scade


func _test_launcher_and_body_game() -> void:
	print("-- menu e BodyGame")
	change_scene_to_file(LAUNCHER)
	await process_frame
	await process_frame
	var launcher: Node = current_scene
	_check(launcher != null and launcher.scene_file_path == LAUNCHER, "il menu si apre")
	var registry: GDScript = load("res://core/game/game_registry.gd")
	_check(launcher.games.size() == registry.list_games().size() and launcher.cards.size() == launcher.games.size(),
		"una scheda per ogni gioco (%d)" % launcher.games.size())
	_check(_bi.get_session().get("game") == "launcher", "il menu chiede la sua sessione al tracker")
	var rx := PacketPeerUDP.new()
	rx.bind(42430, "127.0.0.1")
	var sent: Variant = null
	for i in 120:
		await process_frame
		if rx.get_available_packet_count() > 0:
			sent = JSON.parse_string(rx.get_packet().get_string_from_utf8())
			break
	rx.close()
	var vp: Vector2 = root.get_visible_rect().size
	_check(sent is Dictionary and sent.get("screen") is Array and is_equal_approx(float(sent["screen"][0]) / float(sent["screen"][1]), vp.x / vp.y),
		"la sessione porta le proporzioni dello schermo (%s)" % str(sent.get("screen") if sent is Dictionary else null))

	# Con un sensore che ha solo la pose (niente effettori), il menu segnala cosa manca.
	await _feed([{"id": "p1", "pose": {"nose": [0.5, 0.2, 1.0]}}], 0.1, ["pose"])
	var bub_idx := -1
	for i in launcher.games.size():
		if launcher.games[i].id == "bubbles":
			bub_idx = i
	_check(Array(launcher.games[bub_idx].missing_capabilities(_bi.capabilities)) == ["effectors"], "Bolle senza effettori: segnalato")

	# Scelta col corpo: un effettore fermo sulla scheda di Bolle → parte Bolle.
	var r: Rect2 = launcher.card_rect(bub_idx)
	var c: Vector2 = r.get_center() / root.get_visible_rect().size
	launcher.cards[bub_idx].dwell_time = 0.3
	await _feed([{"id": "p1", "effectors": {"e0": [c.x, c.y, 1.0]}}], 0.8, ["effectors"])
	await process_frame
	_check(current_scene != null and current_scene.scene_file_path.ends_with("bubbles.tscn"), "mano ferma sulla scheda → parte il gioco")
	_check(_bi.get_session().get("game") == "bubbles" and int(_bi.get_session().get("max_players")) == 1,
		"il gioco manda la sua sessione (da game.json)")

	# Esc (game_exit) → di nuovo il menu.
	var ev := InputEventAction.new()
	ev.action = &"game_exit"
	ev.pressed = true
	Input.parse_input_event(ev)
	for i in 5:
		await process_frame
	_check(current_scene != null and current_scene.scene_file_path == LAUNCHER, "game_exit torna al menu")
