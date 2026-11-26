extends SceneTree
## Taglia il filo: giudizio del taglio (perfetto / nel verde / fuori), compensazione del
## ritardo, taglio con la mano destra e ricarica, mano sinistra ignorata, passaggi
## mancati, inversione della lancetta, fine partita e ripartenza.
## Nota: con "-s" le classi che usano l'autoload BodyInput si caricano con load().

const SCENE := "res://games/taglia_filo/taglia_filo.tscn"
const CONTROL_PORT := 42445
enum Result { HIT, PERFECT, MISS, TIMEOUT }  # = taglia_filo_game.gd

var _fail: int = 0
var _bi: Node
var _g: Node2D
var _vp: Vector2


func _check(cond: bool, msg: String) -> void:
	print(("  ok    " if cond else "  FAIL  ") + msg)
	if not cond:
		_fail += 1


func _wire() -> Vector2:
	return _g.wire_rect().get_center() / _vp


## Pose con solo i polsi (centro mano = polso). null = mano non vista.
func _hands(right: Variant, left: Variant, seconds: float) -> void:
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
	_g = load(SCENE).instantiate()
	_g.auto_run = false
	root.add_child(_g)
	await process_frame
	_check(_g.manifest != null and _g.manifest.is_valid(), "game.json valido")
	_check(not _g.wire_rect().intersects(Rect2(_g.dial_center() - Vector2.ONE * _g.dial_radius(), Vector2.ONE * _g.dial_radius() * 2.0)),
		"il filo non copre il quadrante")
	_test_judge()
	await _test_latency_compensation()
	await _test_hand_flow()
	await _test_passes_and_reverse()
	await _test_game_over()
	_g.queue_free()
	quit(1 if _fail > 0 else 0)


func _test_judge() -> void:
	print("-- giudizio")
	var g := _g
	g.start_game()
	g.window_center = 1.0
	g.window_width = 0.6
	g._set_needle(1.0, 0.0)
	_check(g.judge(g.now()) == Result.PERFECT, "lancetta al centro: perfetto")
	g._set_needle(1.0 + 0.25, 0.0)
	_check(g.judge(g.now()) == Result.HIT, "nel verde ma non al centro: preso")
	g._set_needle(1.0 + 0.4, 0.0)
	_check(g.judge(g.now()) == Result.MISS, "fuori dal verde: mancato")
	g.window_center = 0.1
	g._set_needle(TAU - 0.1, 0.0)
	_check(g.judge(g.now()) == Result.HIT, "finestra a cavallo dello zero: funziona")


func _test_latency_compensation() -> void:
	print("-- compensazione del ritardo")
	var g := _g
	var latency_before: float = _bi.input_latency
	g.start_game()
	g.window_center = 2.0
	g.window_width = 0.4
	var t0: float = g.now()
	g._set_needle(2.0, 2.0)  # parte dal centro a 2 rad/s
	await create_timer(0.15).timeout
	var elapsed: float = g.now() - t0
	var now_angle: float = g.needle_angle()
	_check(absf(g.diff_to_window(now_angle)) > 0.2, "adesso la lancetta è già oltre il verde (%.2f rad)" % g.diff_to_window(now_angle))
	_bi.input_latency = elapsed - 0.03  # il gesto è avvenuto 30 ms dopo la partenza dal centro
	g.armed = true
	var r: int = g.cut()
	_check(r == Result.PERFECT or r == Result.HIT, "ma il gesto è avvenuto %.0f ms fa, quando era nel verde: preso (%d)" % [_bi.input_latency * 1000.0, r])
	_bi.input_latency = 0.0
	g.armed = true
	g.window_center = 2.0
	g._set_needle(2.0, 2.0)
	await create_timer(0.15).timeout
	_check(g.cut() == Result.MISS, "senza compensazione lo stesso taglio sarebbe mancato")
	_bi.input_latency = latency_before


func _test_hand_flow() -> void:
	print("-- mano sul filo")
	var g := _g
	var rest := Vector2(0.3, 0.95)
	await _hands(rest, null, 0.3)
	g.start_game()
	g.window_center = 1.0
	g.window_width = 0.6
	g._set_needle(1.0, 0.0)  # ferma nel verde
	_check(g.armed, "mano a riposo: filo carico")
	await _hands(null, _wire(), 0.3)
	_check(g.score == 0 and g.armed, "mano sinistra sul filo: ignorata")
	await _hands(_wire(), null, 0.3)
	_check(g.score == 2 and g.level == 2 and not g.armed, "mano destra sul filo con la lancetta nel verde: +2, livello 2")
	g._set_needle(g.window_center, 0.0)
	await _hands(_wire(), null, 0.3)
	_check(g.score == 2, "restando sul filo non si taglia di nuovo")
	await _hands(rest, null, 0.3)
	_check(g.armed, "mano tolta: filo di nuovo carico")
	g._set_needle(g.window_center + PI, 0.0)  # dall'altra parte
	await _hands(rest, null, 0.2)  # oltre input_latency: il gesto avviene dopo lo spostamento
	await _hands(_wire(), null, 0.3)
	_check(g.lives == 2 and g.score == 2, "taglio con la lancetta fuori: -1 vita")
	await _hands(rest, null, 0.3)


func _test_passes_and_reverse() -> void:
	print("-- passaggi e inversioni")
	var g := _g
	g.start_game()
	g.max_passes = 3
	g._set_needle(g.needle_angle(), 12.0)  # quasi 2 giri al secondo
	var lives_before: int = g.lives
	await _hands(Vector2(0.3, 0.95), null, 2.2)
	_check(g.lives < lives_before, "la lancetta passa 3 volte senza taglio: -1 vita (vite %d)" % g.lives)
	g.start_game()
	g.level = g.reverse_from_level
	g.reverse_interval = Vector2(0.1, 0.15)
	g._set_needle(g.needle_angle(), 1.0)
	g._schedule_reverse()
	await _hands(Vector2(0.3, 0.95), null, 0.3)
	_check(g.speed < 0.0 or g._history.size() > 2, "dal livello %d la lancetta inverte il senso" % g.reverse_from_level)
	g.reverse_interval = Vector2(1.2, 3.0)


func _test_game_over() -> void:
	print("-- fine partita")
	var g := _g
	g.start_game()
	g.game_over_cooldown = 0.2
	# tagli giudicati adesso: con la compensazione si guarderebbe la lancetta di prima
	# di _set_needle, ancora in movimento (risultato a caso)
	var latency_before: float = _bi.input_latency
	_bi.input_latency = 0.0
	for i in g.lives_start:
		g.window_center = 1.0
		g._set_needle(1.0 + PI, 0.0)
		g.armed = true
		g.cut()
	_bi.input_latency = latency_before
	_check(g.state == 2 and g.lives == 0, "3 tagli fuori: partita finita")
	_check(g.title_label.text.contains("record"), "mostra punti e record")
	await _hands(Vector2(0.3, 0.95), null, 0.4)
	await _hands(_wire(), null, 0.3)
	_check(g.state == 1 and g.lives == g.lives_start and g.score == 0, "mano sul filo dopo la pausa: nuova partita")
