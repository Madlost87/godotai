extends SceneTree
## Tris: regole (vittoria, pareggio, caselle occupate), segno con la mano destra ferma,
## mano sinistra ignorata, nuova partita, e funzionamento con un sensore senza
## destra/sinistra (solo effettori).
## Nota: con "-s" le classi che usano l'autoload BodyInput si caricano con load().

const SCENE := "res://games/tris/tris.tscn"
const CONTROL_PORT := 42444
const DWELL := 0.3

var _fail: int = 0
var _bi: Node
var _game: Node2D
var _vp: Vector2


func _check(cond: bool, msg: String) -> void:
	print(("  ok    " if cond else "  FAIL  ") + msg)
	if not cond:
		_fail += 1


## Centro della casella i, normalizzato.
func _cell(i: int) -> Vector2:
	return _game.cell_rect(i).get_center() / _vp


## Pose con solo i polsi (centro mano = polso). null = mano non vista.
func _feed_hands(right: Variant, left: Variant, seconds: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < seconds * 1000.0:
		var pose := {}
		if right != null:
			pose["wrist_r"] = [right.x, right.y, 1.0]
		if left != null:
			pose["wrist_l"] = [left.x, left.y, 1.0]
		_bi.ingest_packet({"v": 1, "caps": ["effectors", "pose"], "players": [{"id": "p1", "pose": pose}]})
		await process_frame


func _initialize() -> void:
	await process_frame
	_bi = root.get_node("BodyInput")
	_bi.simulator_fallback = false
	_bi.control_port = CONTROL_PORT
	_vp = root.get_visible_rect().size
	_test_rules()
	_game = load(SCENE).instantiate()
	_game.dwell_time = DWELL
	root.add_child(_game)
	await process_frame
	_check(_game.manifest != null and _game.manifest.is_valid(), "game.json valido")
	await _test_right_hand_plays()
	await _test_contacts_sensor()
	_game.queue_free()
	quit(1 if _fail > 0 else 0)


func _test_rules() -> void:
	print("-- regole")
	var script: GDScript = load("res://games/tris/tris_game.gd")
	_check(script.check_winner([1, 1, 1, 0, 2, 2, 0, 0, 0])["winner"] == 1, "riga")
	_check(script.check_winner([2, 1, 0, 2, 1, 0, 2, 0, 0])["line"] == [0, 3, 6], "colonna, con la linea vincente")
	_check(script.check_winner([2, 1, 1, 0, 2, 1, 0, 0, 2])["winner"] == 2, "diagonale")
	_check(script.check_winner([1, 2, 1, 1, 2, 2, 2, 1, 1])["winner"] == 0, "nessun vincitore")


func _test_right_hand_plays() -> void:
	print("-- mano destra")
	var g := _game
	var away := Vector2(0.05, 0.95)
	await _feed_hands(away, _cell(4), DWELL * 2.0)
	_check(g.board[4] == 0, "mano sinistra ferma su una casella: ignorata")
	_check(g.colliders.get_part(&"p1", "hand_l") == null, "nessuna area sulla mano sinistra")
	await _feed_hands(_cell(4), away, DWELL * 0.4)
	_check(g.board[4] == 0, "mano destra passata di sfuggita: niente")
	await _feed_hands(_cell(4), away, DWELL * 2.5)
	_check(g.board[4] == 1 and g.turn == 2, "mano destra ferma: X al centro, tocca a O")
	await _feed_hands(_cell(4), away, DWELL * 2.0)
	_check(g.board.count(2) == 0, "restando sulla casella occupata non succede altro")
	await _feed_hands(_cell(0), away, DWELL * 2.5)
	_check(g.board[0] == 2 and g.turn == 1, "O in alto a sinistra, tocca a X")
	_check(not g.place(4), "casella occupata: rifiutata")
	# X vince sulla colonna centrale: 1, 7 (con O in 2 in mezzo)
	g.place(1)
	g.place(2)
	await _feed_hands(_cell(7), away, DWELL * 2.5)
	_check(g.state == 1 and g.winner == 1 and g.win_line == [1, 4, 7], "X vince sulla colonna centrale")
	_check(g.status_label.text.contains("Vince X"), "messaggio di vittoria")
	await _feed_hands(_cell(8), away, DWELL * 2.0)
	_check(g.board[8] == 0, "a partita finita le caselle non si segnano")
	var b: Vector2 = g.button_rect().get_center() / _vp
	await _feed_hands(b, away, DWELL * 2.5)
	_check(g.state == 0 and not g.board.has(1) and g.turn == 1, "mano su «Nuova partita»: si ricomincia con X")
	_check(not g.button_rect().intersects(g.grid_rect()), "il pulsante non copre mai la griglia")
	# pareggio
	for i in [0, 1, 2, 4, 3, 5, 7, 6, 8]:
		g.place(i)
	_check(g.state == 1 and g.winner == 0 and g.status_label.text.contains("Pareggio"), "pareggio")
	g.new_game()
	await _feed_hands(null, null, 0.4)  # il giocatore scade


func _test_contacts_sensor() -> void:
	print("-- sensore senza destra/sinistra (solo effettori)")
	var g := _game
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < DWELL * 2500.0:
		var c := _cell(2)
		_bi.ingest_packet({"v": 1, "caps": ["effectors"], "players": [{"id": "p1", "effectors": {"e0": [c.x, c.y, 1.0]}}]})
		await process_frame
	_check(g.board[2] == 1, "un punto di contatto fermo segna la casella")
