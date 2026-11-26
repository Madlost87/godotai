extends SceneTree
## BodyMetrics, BodyMetrics.Baseline, GestureController, BodyColliders, TrackingQuality.
## Nota: con "-s" lo script di test viene compilato prima che esista l'autoload
## BodyInput, quindi le classi che lo usano (GestureController, BodyColliders) si
## caricano a runtime con load() invece di citarle per nome.

## Dimensione usata per i PlayerState costruiti a mano. La viewport headless invece è
## fissa (64×64), quindi i test che passano da BodyInput lavorano in proporzione.
const SIZE := Vector2i(1152, 648)
const BODY_LAYER := 2
const GestureScript := "res://core/controllers/gesture_controller.gd"
const CollidersScript := "res://core/body/body_colliders.gd"

var _fail: int = 0


func _check(cond: bool, msg: String) -> void:
	print(("  ok    " if cond else "  FAIL  ") + msg)
	if not cond:
		_fail += 1


## PlayerState "fresco" (niente filtro: il primo campione passa invariato).
static func state(pose: Dictionary, id: StringName = &"p1") -> PlayerState:
	var p := PlayerState.new(id)
	p.screen_size = Vector2(SIZE)
	var arr := {}
	for k: String in pose:
		var v: Vector2 = pose[k]
		arr[k] = [v.x, v.y, 1.0]
	p.apply({"id": String(id), "pose": arr}, 0.0, 1.0, 10.0)
	return p


## Busto standard (vista a specchio: destra della persona a destra sullo schermo).
static func body(right_hand: Vector2, left_hand := Vector2(0.4, 0.7), shift := 0.0) -> Dictionary:
	return {
		"id": "p1",
		"pose": {
			"shoulder_l": [0.45 + shift, 0.5, 1.0], "shoulder_r": [0.55 + shift, 0.5, 1.0],
			"elbow_r": [0.58 + shift, 0.4, 1.0], "wrist_r": [right_hand.x, right_hand.y, 1.0],
			"wrist_l": [left_hand.x, left_hand.y, 1.0], "hip_c": [0.5, 0.8, 1.0],
		},
	}


func _initialize() -> void:
	await process_frame
	var bi: Node = root.get_node("BodyInput")
	bi.simulator_fallback = false
	_test_metrics()
	_test_baseline()
	await _test_gesture(bi)
	await _test_colliders(bi)
	await _test_dwell_target(bi)
	quit(1 if _fail > 0 else 0)


func _test_metrics() -> void:
	print("-- BodyMetrics")
	var p := state({
		"shoulder_l": Vector2(0.45, 0.5), "shoulder_r": Vector2(0.55, 0.5), "hip_c": Vector2(0.5, 0.8),
		"wrist_r": Vector2(0.6, 0.2), "index_r": Vector2(0.62, 0.16), "wrist_l": Vector2(0.4, 0.7),
	})
	_check(is_equal_approx(BodyMetrics.shoulder_width(p), 115.2), "larghezza spalle in pixel")
	_check(BodyMetrics.hand_center(p, "r").is_equal_approx(Vector2(0.61, 0.18) * Vector2(SIZE)), "senza gomito: centro mano tra polso e indice")
	var with_elbow := state({"elbow_r": Vector2(0.5, 0.5), "wrist_r": Vector2(0.6, 0.3), "index_r": Vector2(0.7, 0.3)})
	_check(BodyMetrics.hand_center(with_elbow, "r").is_equal_approx(Vector2(0.63, 0.24) * Vector2(SIZE)),
		"con il gomito: avambraccio prolungato del 30%% oltre il polso (stabile anche se l'indice va e viene)")
	_check(absf(BodyMetrics.torso_lean(p)) < 0.001, "busto dritto → lean 0")
	_check(BodyMetrics.arm_raised(p, "r") == 1.0, "braccio destro alzato → 1")
	_check(BodyMetrics.arm_raised(p, "l") == 0.0, "braccio sinistro giù → 0")
	_check(absf(BodyMetrics.arms_spread(p) - 3.6) < 0.05, "braccia aperte ~3.6 larghezze spalle")
	_check(BodyMetrics.arm_angle(p, "r") < -PI / 3.0, "angolo braccio destro verso l'alto")

	var leaning := state({"shoulder_l": Vector2(0.55, 0.5), "shoulder_r": Vector2(0.65, 0.5), "hip_c": Vector2(0.5, 0.8)})
	_check(BodyMetrics.torso_lean(leaning) > 0.2, "spalle spostate a destra → lean positivo")
	var no_hips := state({"shoulder_l": Vector2(0.45, 0.5), "shoulder_r": Vector2(0.55, 0.55)})
	_check(BodyMetrics.torso_lean(no_hips) > 0.2, "senza anche: spalla destra più bassa → lean positivo")
	var head_only := state({"nose": Vector2(0.5, 0.3)})
	_check(is_nan(BodyMetrics.arm_raised(head_only, "r")) and is_nan(BodyMetrics.torso_lean(head_only)), "punti mancanti → NAN")
	_check(not BodyMetrics.has_hand(head_only, "l"), "has_hand falso senza polso")
	var index_only := state({"index_r": Vector2(0.7, 0.3)})
	_check(BodyMetrics.has_hand(index_only, "r") and BodyMetrics.hand_center(index_only, "r").is_equal_approx(Vector2(0.7, 0.3) * Vector2(SIZE)),
		"solo l'indice: la mano c'è ed è sull'indice")
	_check(BodyMetrics.effectors(index_only).has("hand_r"), "solo l'indice: effettore hand_r presente")

	_test_tracking_quality()


func _test_tracking_quality() -> void:
	print("-- TrackingQuality")
	var good := state({"shoulder_l": Vector2(0.45, 0.5), "elbow_r": Vector2(0.6, 0.5), "wrist_r": Vector2(0.6, 0.3)})
	var close := state({"shoulder_l": Vector2(0.45, 0.5), "wrist_r": Vector2(0.6, 0.3)})
	var no_hands := state({"shoulder_l": Vector2(0.45, 0.5), "nose": Vector2(0.5, 0.3)})
	var q := TrackingQuality.new()
	q.sample(no_hands, 0.0)
	_check(q.hint() == "", "appena partito: nessun consiglio")
	for i in 120:  # 4 s a 30 Hz: mani visibili solo un frame su due
		q.sample(no_hands if i % 2 == 0 else good, i / 30.0)
	_check(q.hint() == TrackingQuality.HINT_HANDS, "mani spesso perse → consiglio su luce e distanza")
	q = TrackingQuality.new()
	for i in 120:
		q.sample(close, i / 30.0)
	_check(q.hint() == TrackingQuality.HINT_TOO_CLOSE, "mani viste ma mai i gomiti → troppo vicino")
	q.uses_pose = false
	_check(q.hint() == "", "senza scheletro (es. solo contatti) niente consiglio sui gomiti")
	q = TrackingQuality.new()
	for i in 120:
		q.sample(good, i / 30.0)
	_check(q.hint() == "", "mani e gomiti visibili: nessun consiglio")
	q = TrackingQuality.new()
	for i in 120:
		q.sample(null, i / 30.0)
	_check(q.hint() == "", "nessuno davanti alla camera: nessun consiglio")


func _test_baseline() -> void:
	print("-- BodyMetrics.Baseline")
	var b := BodyMetrics.Baseline.new()
	for i in 30:
		b.update(state({"shoulder_l": Vector2(0.45, 0.5), "shoulder_r": Vector2(0.55, 0.5)}), 1.0 / 30.0)
	_check(absf(b.offset) < 0.001, "a riposo offset 0")
	b.update(state({"shoulder_l": Vector2(0.45, 0.4), "shoulder_r": Vector2(0.55, 0.4)}), 1.0 / 30.0)
	_check(b.jump() > 0.5 and b.crouch() == 0.0, "spalle più in alto → jump (%.2f)" % b.jump())
	var b2 := BodyMetrics.Baseline.new()
	b2.update(state({"shoulder_l": Vector2(0.45, 0.5), "shoulder_r": Vector2(0.55, 0.5)}), 1.0 / 30.0)
	b2.update(state({"shoulder_l": Vector2(0.45, 0.65), "shoulder_r": Vector2(0.55, 0.65)}), 1.0 / 30.0)
	_check(b2.crouch() > 0.8, "spalle più in basso → crouch (%.2f)" % b2.crouch())
	for i in 600:  # 20 s accovacciato: il riposo si adatta
		b2.update(state({"shoulder_l": Vector2(0.45, 0.65), "shoulder_r": Vector2(0.55, 0.65)}), 1.0 / 30.0)
	_check(b2.crouch() < 0.01, "il riposo si adatta lentamente alla nuova posizione")


func _feed_for(bi: Node, seconds: float, players: Array) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < seconds * 1000.0:
		bi.ingest_packet({"v": 1, "players": players})
		await process_frame


func _test_gesture(bi: Node) -> void:
	print("-- GestureController")
	var g: Node = load(GestureScript).new()
	g.hold_time = 0.3
	var events: Array[String] = []
	g.activated.connect(func(id: StringName) -> void: events.append("on:" + id))
	g.deactivated.connect(func(id: StringName) -> void: events.append("off:" + id))
	root.add_child(g)
	await _feed_for(bi, 0.3, [body(Vector2(0.6, 0.7))])
	_check(not g.is_active() and not Input.is_action_pressed(&"game_start"), "braccia giù: niente gesto")
	await _feed_for(bi, 0.15, [body(Vector2(0.6, 0.1))])
	_check(not g.is_active(), "braccio alzato per meno di hold_time: niente")
	await _feed_for(bi, 0.1, [body(Vector2(0.6, 0.7))])
	await _feed_for(bi, 0.6, [body(Vector2(0.6, 0.1))])
	_check(g.is_active(&"p1") and Input.is_action_pressed(&"game_start"), "braccio alzato a lungo: azione game_start premuta")
	await _feed_for(bi, 0.3, [body(Vector2(0.6, 0.42))])  # appena sopra la spalla: isteresi, resta attivo
	_check(g.is_active(), "isteresi: sotto la soglia di attivazione ma sopra quella di rilascio")
	await _feed_for(bi, 0.3, [body(Vector2(0.6, 0.7))])
	_check(not g.is_active() and not Input.is_action_pressed(&"game_start"), "braccio giù: azione rilasciata")
	_check(events == ["on:p1", "off:p1"], "segnali activated/deactivated (%s)" % str(events))
	await _feed_for(bi, 0.5, [body(Vector2(0.6, 0.1))])
	_check(g.is_active(), "di nuovo attivo")
	for i in 30:  # il giocatore sparisce
		await process_frame
	await create_timer(0.4).timeout
	_check(not g.is_active() and not Input.is_action_pressed(&"game_start"), "giocatore perso: azione rilasciata")
	g.queue_free()


func _test_colliders(bi: Node) -> void:
	print("-- BodyColliders")
	var bc: Node2D = load(CollidersScript).new()
	bc.forearms = true
	root.add_child(bc)
	await _feed_for(bi, 0.3, [body(Vector2(0.7, 0.3))])
	var vp: Vector2 = root.get_visible_rect().size
	var hand: Area2D = bc.get_part(&"p1", "hand_r")
	_check(hand != null and hand.get_meta(&"player_id") == &"p1", "area sulla mano destra di p1")
	var expected: Vector2 = load("res://core/body/body_metrics.gd").hand_center(bi.get_player(&"p1"), "r")
	_check(hand != null and hand.global_position.distance_to(expected) < vp.y * 0.01, "area nel centro della mano")
	_check(hand != null and hand.collision_layer == BODY_LAYER, "sul layer body")
	_check(bc.get_part(&"p1", "forearm_r") != null and bc.get_part(&"p1", "forearm_l") == null, "avambraccio destro (c'è il gomito), sinistro no")

	# Un'area di prova sul layer body deve sentire la mano.
	var probe := Area2D.new()
	probe.collision_layer = 0
	probe.collision_mask = BODY_LAYER
	var cs := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = vp.y * 0.02
	cs.shape = shape
	probe.add_child(cs)
	probe.position = Vector2(0.7, 0.3) * vp
	var hits: Array[StringName] = []
	probe.area_entered.connect(func(a: Area2D) -> void: hits.append(a.get_meta(&"player_id", &"")))
	root.add_child(probe)
	await _feed_for(bi, 0.2, [body(Vector2(0.7, 0.3))])
	_check(hits.has(&"p1"), "collisione mano → area di gioco")

	await create_timer(0.5).timeout  # nessun dato: il giocatore si perde
	await physics_frame
	await physics_frame
	_check(bc.get_parts().is_empty(), "giocatore perso: aree rimosse")
	probe.queue_free()
	bc.queue_free()


func _test_dwell_target(bi: Node) -> void:
	print("-- DwellTarget")
	var vp: Vector2 = root.get_visible_rect().size
	var bc: Node2D = load(CollidersScript).new()
	root.add_child(bc)
	var t: Area2D = load("res://core/controllers/dwell_target.gd").new()
	t.size = vp * 0.3
	t.position = vp * 0.5
	t.dwell_time = 0.25
	var who: Array = []
	t.selected_by.connect(func(pid: StringName, part: String) -> void: who.append([pid, part]))
	root.add_child(t)
	var on_target := [{"id": "p1", "effectors": {"e0": [0.5, 0.5, 1.0]}}, {"id": "p2", "effectors": {"e0": [0.9, 0.9, 1.0]}}]
	t.accept_players = PackedStringArray(["p2"])
	await _feed_for(bi, 0.5, on_target)
	_check(who.is_empty() and t.progress == 0.0, "filtro giocatori: p1 sopra, ma si accetta solo p2")
	t.accept_players = PackedStringArray()
	t.accept_parts = PackedStringArray(["hand_r"])
	await _feed_for(bi, 0.5, on_target)
	_check(who.is_empty(), "filtro parti: e0 non è hand_r")
	t.accept_parts = PackedStringArray()
	t.enabled = false
	await _feed_for(bi, 0.5, on_target)
	_check(who.is_empty() and t.progress == 0.0, "disattivato: non reagisce")
	t.enabled = true
	await _feed_for(bi, 0.5, on_target)
	_check(who.size() == 1 and who[0] == [&"p1", "e0"], "attivo e senza filtri: selected_by(p1, e0) una volta sola (%s)" % str(who))
	t.queue_free()
	# Due bersagli che la stessa mano tocca entrambi: senza gruppo scattano tutti e due,
	# con un gruppo esclusivo solo il più vicino al centro della mano.
	var script: GDScript = load("res://core/controllers/dwell_target.gd")
	for group: StringName in [&"", &"griglia"]:
		var fired: Array[String] = []
		var pair: Array[Area2D] = []
		for k in 2:
			var d: Area2D = script.new()
			d.size = vp * 0.3
			d.position = vp * Vector2(0.4 + 0.25 * k, 0.5)  # si sovrappongono al centro
			d.dwell_time = 0.25
			d.exclusive_group = group
			d.selected.connect(func() -> void: fired.append("AB"[k]))
			root.add_child(d)
			pair.append(d)
		await _feed_for(bi, 0.6, [{"id": "p1", "effectors": {"e0": [0.5, 0.5, 1.0]}}])  # più vicina ad A
		if group == &"":
			_check(fired.size() == 2, "senza gruppo: la mano su due bersagli li attiva entrambi (%s)" % str(fired))
		else:
			_check(fired == ["A"], "gruppo esclusivo: solo il più vicino (%s)" % str(fired))
		for d in pair:
			d.queue_free()
		await process_frame
	bc.queue_free()
