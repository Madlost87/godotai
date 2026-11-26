extends SceneTree
## Minigioco Bolle: partenza col braccio alzato, scoppio con la mano, punteggi, fine partita.
## Bubble non è citata per nome (dipende dall'autoload, vedi body_controls_test.gd).

enum Kind { NORMAL, GOLDEN, SPIKY }  # = Bubble.Kind

var _fail: int = 0
var _bi: Node
var _hand := Vector2(0.6, 0.7)  # mano destra di p1 (normalizzata)


func _check(cond: bool, msg: String) -> void:
	print(("  ok    " if cond else "  FAIL  ") + msg)
	if not cond:
		_fail += 1


## Una bolla scoppiata viene liberata dopo l'animazione: liberata = scoppiata.
static func _popped(b: Variant) -> bool:
	return not is_instance_valid(b) or b.is_popped


func _packet() -> Dictionary:
	return {"v": 1, "players": [{
		"id": "p1",
		"pose": {
			"shoulder_l": [0.45, 0.5, 1.0], "shoulder_r": [0.55, 0.5, 1.0],
			"wrist_r": [_hand.x, _hand.y, 1.0], "wrist_l": [0.4, 0.75, 1.0],
		},
	}]}


func _run(seconds: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < seconds * 1000.0:
		_bi.ingest_packet(_packet())
		await process_frame


func _initialize() -> void:
	await process_frame
	var vp: Vector2 = root.get_visible_rect().size  # headless: 64×64, si lavora in proporzione
	var r := vp.y * 0.08
	_bi = root.get_node("BodyInput")
	_bi.simulator_fallback = false
	_bi.control_port = 42427
	var rx := PacketPeerUDP.new()
	rx.bind(42427, "127.0.0.1")
	var game: Node2D = load("res://games/bubbles/bubbles.tscn").instantiate()
	game.auto_spawn = false
	game.round_time = 2.0
	game.results_cooldown = 0.3
	root.add_child(game)
	var title: Label = game.get_node("HUD/Title")

	await process_frame
	_check(title.text.contains("Mettiti davanti"), "nessuno davanti alla camera: invito a mettersi davanti")
	var session: Variant = null
	for i in 30:
		if rx.get_available_packet_count() > 0:
			session = JSON.parse_string(rx.get_packet().get_string_from_utf8())
			break
		await process_frame
	_check(session is Dictionary and session["type"] == "session" and int(session["max_players"]) == 1, "chiede al tracker 1 giocatore")
	await _run(0.3)
	_check(game.state == 0 and title.text.contains("Alza un braccio"), "in attesa, con istruzioni")
	_hand = Vector2(0.6, 0.1)
	await _run(0.7)
	_check(game.state == 1, "braccio alzato: la partita parte")

	# Una bolla ferma lontano dalla mano, poi la mano ci va sopra.
	var b: Variant = game.spawn_bubble(Vector2(0.3, 0.6) * vp, Kind.NORMAL, r, 0.0)
	await _run(0.2)
	_check(not _popped(b), "bolla non toccata: intatta")
	_hand = Vector2(0.3, 0.6)
	await _run(0.3)
	_check(_popped(b) and game.score == 1, "mano sulla bolla: scoppia, +1")

	var spiky: Variant = game.spawn_bubble(Vector2(0.3, 0.6) * vp, Kind.SPIKY, r, 0.0)
	await _run(0.3)
	_check(_popped(spiky) and game.score == -2, "bolla spinosa: -3")

	var golden: Variant = game.spawn_bubble(Vector2(0.8, 0.2) * vp, Kind.GOLDEN, r, 0.0)
	_hand = Vector2(0.8, 0.2)
	await _run(0.3)
	_check(_popped(golden) and game.score == 1, "bolla dorata: +3")

	# Si gioca con la sola mano destra: una bolla sotto la mano sinistra resta intatta.
	var under_left: Variant = game.spawn_bubble(Vector2(0.4, 0.75) * vp, Kind.NORMAL, r, 0.0)
	await _run(0.3)
	_check(not _popped(under_left) and game.score == 1, "bolla sotto la mano sinistra: ignorata")
	_check(game.get_node("BodyColliders").get_part(&"p1", "hand_l") == null, "nessuna area sulla mano sinistra")
	under_left.queue_free()

	var rising: Variant = game.spawn_bubble(Vector2(0.1, 0.5) * vp, Kind.NORMAL, r * 0.6, vp.y * 4.0)
	var escaped: Array[bool] = [false]
	rising.escaped.connect(func(_b: Area2D) -> void: escaped[0] = true)
	await _run(0.4)
	_check(escaped[0], "bolla veloce esce dall'alto senza punti")

	_hand = Vector2(0.6, 0.75)  # braccio giù
	var t0 := Time.get_ticks_msec()
	while game.state == 1 and Time.get_ticks_msec() - t0 < 4000:
		await _run(0.1)
	_check(game.state == 2 and title.text.contains("Tempo scaduto"), "fine partita: risultati")
	_check(game.get_bubbles().is_empty(), "bolle rimosse a fine partita")
	_check(game.best == 1 and title.text.contains("1 punti") and title.text.contains("record"), "record della sessione")
	await _run(0.5)
	_check(title.text.contains("giocare ancora"), "dopo la pausa: invito a rigiocare")
	_hand = Vector2(0.6, 0.1)
	await _run(0.7)
	_check(game.state == 1 and game.score == 0, "braccio alzato: nuova partita, punteggio azzerato")

	game.queue_free()
	await process_frame
	_check(_bi.get_session().is_empty(), "uscendo dal gioco la sessione viene tolta")
	rx.close()
	quit(1 if _fail > 0 else 0)
