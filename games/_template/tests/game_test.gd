extends SceneTree
## Test del gioco: il manifest è valido, la sessione arriva al tracker, toccare il
## bersaglio dà un punto. I dati arrivano come "effettori" (punti di contatto), quindi
## il test vale per qualsiasi sensore. Aggiungi qui i test delle regole del tuo gioco.
## Nota: con "-s" le classi che usano l'autoload BodyInput si caricano con load().

const SCENE := "res://games/_template/game.tscn"
const CONTROL_PORT := 42440

var _fail: int = 0
var _bi: Node


func _check(cond: bool, msg: String) -> void:
	print(("  ok    " if cond else "  FAIL  ") + msg)
	if not cond:
		_fail += 1


## Un giocatore visto solo come un punto di contatto (posizione normalizzata 0..1).
func _feed(hand: Vector2, seconds: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < seconds * 1000.0:
		_bi.ingest_packet({"v": 1, "caps": ["effectors"], "players": [
			{"id": "p1", "effectors": {"e0": [hand.x, hand.y, 1.0]}}]})
		await process_frame


func _initialize() -> void:
	await process_frame
	_bi = root.get_node("BodyInput")
	_bi.simulator_fallback = false
	_bi.control_port = CONTROL_PORT
	var rx := PacketPeerUDP.new()
	rx.bind(CONTROL_PORT, "127.0.0.1")

	var game: Node2D = load(SCENE).instantiate()
	root.add_child(game)
	await process_frame
	_check(game.manifest != null and game.manifest.is_valid(), "game.json valido (%s)" % (
		"; ".join(game.manifest.errors) if game.manifest != null else "manca"))

	var session: Variant = null
	for i in 30:
		if rx.get_available_packet_count() > 0:
			session = JSON.parse_string(rx.get_packet().get_string_from_utf8())
			break
		await process_frame
	_check(session is Dictionary and session.get("type") == "session", "sessione mandata al tracker")

	var vp: Vector2 = root.get_visible_rect().size
	game.move_target(vp * 0.5)
	await _feed(Vector2(0.05, 0.05), 0.3)
	_check(game.score == 0, "mano lontana: nessun punto")
	await _feed(Vector2(0.5, 0.5), 0.3)
	_check(game.score == 1, "mano sul bersaglio: +1")

	game.queue_free()
	rx.close()
	quit(1 if _fail > 0 else 0)
