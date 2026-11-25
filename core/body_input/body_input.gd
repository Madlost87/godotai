extends Node
## Autoload "BodyInput": ponte tra il tracker (Python, UDP) e i giochi.
## Riceve pacchetti del protocollo v1 (docs/SPEC.md §5), li filtra e li espone
## per giocatore. Sorgenti: UDP (tracker), simulatore (mouse) o replay da file.

signal player_entered(id: StringName)
signal player_lost(id: StringName)
signal frame_updated
## Ogni pacchetto valido, così com'è arrivato (anche campi extra, es. "calibration").
signal packet_received(packet: Dictionary)
signal source_changed(source_name: String)
signal replay_finished

enum Source { UDP, SIMULATOR, REPLAY }

const PROTOCOL_VERSION := 1
const DEFAULT_PORT := 4242
const DEFAULT_CONTROL_PORT := 4243
const UdpSource := preload("res://core/body_input/sources/udp_source.gd")
const SimulatorSource := preload("res://core/body_input/sources/simulator_source.gd")
const ReplaySource := preload("res://core/body_input/sources/replay_source.gd")

## Secondi senza dati prima che un punto (e poi il giocatore) sia considerato perso.
var lost_timeout: float = 0.3
## Se il tracker tace per simulator_fallback_after secondi, passa al simulatore.
var simulator_fallback: bool = true
var simulator_fallback_after: float = 2.0
## Filtro One Euro, in coordinate normalizzate.
var filter_min_cutoff: float = 1.0
var filter_beta: float = 10.0

## Porta del canale di controllo Godot → tracker (send_control).
var control_port: int = DEFAULT_CONTROL_PORT

var source: Source = Source.UDP
var tracker_fps: float = 0.0
var last_packet_time: float = -1.0

var _players: Dictionary = {}  # StringName -> PlayerState
var _udp: UdpSource = UdpSource.new()
var _sim: SimulatorSource = SimulatorSource.new()
var _replay: ReplaySource = null
var _last_udp_time: float = 0.0
var _rec_file: FileAccess = null
var _rec_start: float = 0.0
var _control: PacketPeerUDP = PacketPeerUDP.new()
var _session: Dictionary = {}
var _session_timer: float = 0.0

## Ogni quanti secondi si rimanda la sessione al tracker (UDP può perdere messaggi,
## e il tracker può partire dopo il gioco).
const SESSION_RESEND := 1.0


func _ready() -> void:
	_last_udp_time = now()
	listen(DEFAULT_PORT)


func _exit_tree() -> void:
	stop_recording()
	_udp.close()


func now() -> float:
	return Time.get_ticks_usec() / 1000000.0


func listen(port: int) -> bool:
	return _udp.listen(port)


func listening_port() -> int:
	return _udp.port


func source_name() -> String:
	return str(Source.keys()[source])


func get_player(id: StringName) -> PlayerState:
	return _players.get(id)


func get_players() -> Array[PlayerState]:
	var out: Array[PlayerState] = []
	for p: PlayerState in _players.values():
		out.append(p)
	return out


func _process(delta: float) -> void:
	var t := now()
	if not _session.is_empty():
		_session_timer -= delta
		if _session_timer <= 0.0:
			_session_timer = SESSION_RESEND
			send_control(_session)
	if source == Source.REPLAY:
		var due := _replay.poll(t)
		if not due.is_empty():
			ingest_packet(due.back(), t)
		if _replay.is_finished():
			stop_replay()
			replay_finished.emit()
	else:
		var packets := _udp.poll()
		if not packets.is_empty():
			_last_udp_time = t
			_set_source(Source.UDP)
			ingest_packet(packets.back(), t)  # solo il più recente: meno latenza
		elif source == Source.UDP and simulator_fallback and t - _last_udp_time > simulator_fallback_after:
			_set_source(Source.SIMULATOR)
		if source == Source.SIMULATOR:
			ingest_packet(_sim.make_packet(_mouse_normalized()), t)
	update_timeouts(t)


## Applica un pacchetto v1. Restituisce false se non è valido (e lo ignora).
func ingest_packet(data: Variant, t: float = -1.0) -> bool:
	if t < 0.0:
		t = now()
	if not (data is Dictionary):
		return false
	var d: Dictionary = data
	var v: Variant = d.get("v")
	if not (v is float or v is int) or int(v) != PROTOCOL_VERSION:
		return false
	var players: Variant = d.get("players")
	if not (players is Array):
		return false
	var fps: Variant = d.get("fps")
	if fps is float or fps is int:
		tracker_fps = float(fps)

	var size := _screen_size()
	for entry: Variant in players:
		if not (entry is Dictionary) or not entry.has("id"):
			continue
		var id := StringName(str(entry["id"]))
		var p: PlayerState = _players.get(id)
		var is_new := p == null
		if is_new:
			p = PlayerState.new(id)
		p.screen_size = size
		p.apply(entry, t, filter_min_cutoff, filter_beta)
		if is_new and not p.is_empty():
			_players[id] = p
			player_entered.emit(id)

	last_packet_time = t
	if _rec_file != null:
		_rec_file.store_line(JSON.stringify({"dt": t - _rec_start, "p": d}))
	packet_received.emit(d)
	frame_updated.emit()
	return true


## Manda un messaggio al tracker sul canale di controllo (JSON con campo "type").
func send_control(message: Dictionary) -> void:
	_control.set_dest_address("127.0.0.1", control_port)
	_control.put_packet(JSON.stringify(message).to_utf8_buffer())


## Il gioco dice al tracker di cosa ha bisogno, es. set_session({"max_players": 1}).
## Viene mandata subito e poi ripetuta ogni SESSION_RESEND secondi finché resta impostata.
func set_session(session: Dictionary) -> void:
	_session = session.duplicate()
	_session["type"] = "session"
	_session_timer = 0.0


func clear_session() -> void:
	_session = {}


func get_session() -> Dictionary:
	return _session.duplicate()


## Fa scadere punti e giocatori non aggiornati da più di lost_timeout.
func update_timeouts(t: float) -> void:
	for id: StringName in _players.keys():
		var p: PlayerState = _players[id]
		p.expire(t, lost_timeout)
		if p.is_empty():
			_players.erase(id)
			player_lost.emit(id)


func start_recording(path: String) -> bool:
	stop_recording()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	_rec_file = FileAccess.open(path, FileAccess.WRITE)
	if _rec_file == null:
		push_warning("BodyInput: impossibile registrare su %s" % path)
		return false
	_rec_start = now()
	return true


func stop_recording() -> void:
	if _rec_file != null:
		_rec_file.close()
		_rec_file = null


func is_recording() -> bool:
	return _rec_file != null


func play_recording(path: String, loop: bool = false) -> bool:
	var r := ReplaySource.new()
	if not r.load_file(path):
		return false
	r.loop = loop
	r.start(now())
	_replay = r
	_set_source(Source.REPLAY)
	return true


func stop_replay() -> void:
	if _replay == null:
		return
	_replay = null
	_last_udp_time = now()
	_set_source(Source.UDP)


## Cambiando sorgente si azzerano i giocatori, così non si mescolano dati diversi.
func _set_source(s: Source) -> void:
	if s == source:
		return
	for id: StringName in _players.keys():
		_players.erase(id)
		player_lost.emit(id)
	source = s
	source_changed.emit(source_name())


func _screen_size() -> Vector2:
	var vp := get_viewport()
	if vp == null:  # non ancora nell'albero
		return Vector2(
			ProjectSettings.get_setting("display/window/size/viewport_width", 1152),
			ProjectSettings.get_setting("display/window/size/viewport_height", 648))
	return vp.get_visible_rect().size


func _mouse_normalized() -> Vector2:
	var vp := get_viewport()
	var size := vp.get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return Vector2(0.5, 0.5)
	return vp.get_mouse_position() / size
