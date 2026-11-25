extends BodyGame
## Taglia il filo: una lancetta gira su un quadrante; si "taglia" portando la mano
## destra sul filo (a destra) quando la lancetta è nella finestra verde. Poi la mano deve
## uscire dal filo per ricaricare.
## - nel verde: +1, +2 se vicino al centro; la finestra si sposta e si stringe, la
##   lancetta accelera; dal livello reverse_from_level a volte inverte il senso;
## - fuori dal verde, o lasciando passare la lancetta max_passes volte: -1 vita.
## Ritardo: il taglio si giudica dove era la lancetta a `now - BodyInput.input_latency`
## (needle_angle_at tiene la storia esatta del movimento).
## Senza la capacità "pose" (es. LiDAR) taglia qualsiasi effettore.

enum State { WAITING, PLAYING, GAME_OVER }
enum Result { HIT, PERFECT, MISS, TIMEOUT }

const BG := Color(0.06, 0.08, 0.1)
const DIAL := Color(0.16, 0.19, 0.24)
const DIAL_EDGE := Color(0.75, 0.8, 0.9, 0.6)
const WINDOW_COLOR := Color(0.35, 0.95, 0.5)
const PERFECT_COLOR := Color(0.75, 1.0, 0.8)
const NEEDLE := Color(0.95, 0.97, 1.0)
const WIRE := Color(0.95, 0.55, 0.85)
const WIRE_ARMED := Color(0.55, 0.9, 1.0)
const BAD := Color(1.0, 0.5, 0.3)
const TEXT := Color(0.92, 0.95, 1.0)

@export var lives_start: int = 3
@export var speed_start: float = 2.0  # rad/s (~115°/s)
@export var speed_growth: float = 1.1
@export var speed_max: float = 6.0
@export var width_start: float = 0.9  # rad (~50°)
@export var width_shrink: float = 0.9
@export var width_min: float = 0.2  # rad (~11°)
## Frazione centrale della finestra che vale "perfetto".
@export var perfect_fraction: float = 0.3
## Passaggi della lancetta sulla finestra senza taglio prima di perdere una vita.
@export var max_passes: int = 3
@export var reverse_from_level: int = 4
@export var reverse_interval: Vector2 = Vector2(1.2, 3.0)
@export var play_part: String = "hand_r"
## Se false la lancetta resta ferma finché non la muove qualcuno (test).
@export var auto_run: bool = true
@export var game_over_cooldown: float = 1.5

var state: State = State.WAITING
var score: int = 0
var best: int = 0
var lives: int = 3
var level: int = 1
var speed: float = 2.0  # con segno: + orario
var window_center: float = 0.0
var window_width: float = 0.9
var passes: int = 0
var armed: bool = false  # il filo si può tagliare (la mano è uscita)
var last_result: int = -1

var _history: Array = []  # [tempo, angolo, velocità]: movimento esatto della lancetta
var _rng := RandomNumberGenerator.new()
var _prev_diff: float = 0.0
var _next_reverse: float = INF
var _flash: float = 0.0
var _over_time: float = 0.0
var _zone_shape := RectangleShape2D.new()

@onready var wire_zone: Area2D = $WireZone
@onready var colliders: BodyColliders = $BodyColliders
@onready var title_label: Label = $HUD/Title


func _game_ready() -> void:
	_rng.randomize()
	var cs := CollisionShape2D.new()
	cs.shape = _zone_shape
	wire_zone.add_child(cs)
	wire_zone.collision_layer = 0
	wire_zone.collision_mask = BodyColliders.BODY_LAYER
	wire_zone.area_entered.connect(_on_zone_entered)
	BodyInput.capabilities_changed.connect(func(_c: PackedStringArray) -> void: _apply_hand_filter())
	get_viewport().size_changed.connect(_layout)
	_apply_hand_filter()
	_layout()
	_set_needle(0.0, 0.0)
	_set_state(State.WAITING)


# --- Lancetta: posizione esatta in ogni istante recente -----------------------

func now() -> float:
	return BodyInput.now()


## Imposta angolo e velocità della lancetta a partire da adesso.
func _set_needle(angle: float, spd: float) -> void:
	var t := now()
	_history.append([t, wrapf(angle, 0.0, TAU), spd])
	while _history.size() > 2 and t - float(_history[1][0]) > 3.0:
		_history.pop_front()
	speed = spd


func needle_angle_at(t: float) -> float:
	var e: Array = _history[0]
	for h: Array in _history:
		if float(h[0]) <= t:
			e = h
		else:
			break
	return wrapf(float(e[1]) + float(e[2]) * (t - float(e[0])), 0.0, TAU)


func needle_angle() -> float:
	return needle_angle_at(now())


## Distanza con segno tra un angolo e il centro della finestra (-PI..PI).
func diff_to_window(angle: float) -> float:
	return wrapf(angle - window_center, -PI, PI)


# --- Regole ----------------------------------------------------------------------

func start_game() -> void:
	score = 0
	lives = lives_start
	level = 1
	window_width = width_start
	last_result = -1
	_set_needle(needle_angle(), speed_start if auto_run else 0.0)
	_new_window()
	_schedule_reverse()
	armed = not _hand_in_zone()
	_set_state(State.PLAYING)


## Giudica un taglio avvenuto (per il giocatore) all'istante t.
func judge(t: float) -> int:
	var d := absf(diff_to_window(needle_angle_at(t)))
	if d <= window_width * 0.5 * perfect_fraction:
		return Result.PERFECT
	if d <= window_width * 0.5:
		return Result.HIT
	return Result.MISS


## Taglio: la mano è entrata nel filo adesso; la si è mossa input_latency prima.
func cut() -> int:
	if state != State.PLAYING or not armed:
		return -1
	armed = false
	var r := judge(now() - BodyInput.input_latency)
	_apply_result(r)
	return r


func _apply_result(r: int) -> void:
	last_result = r
	_flash = 0.5
	match r:
		Result.HIT, Result.PERFECT:
			score += 2 if r == Result.PERFECT else 1
			level += 1
			window_width = maxf(window_width * width_shrink, width_min)
			var s := minf(absf(speed) * speed_growth, speed_max)
			_set_needle(needle_angle(), s * signf(speed) if speed != 0.0 else 0.0)
		Result.MISS, Result.TIMEOUT:
			lives -= 1
	if lives <= 0:
		_game_over()
		return
	_new_window()
	_schedule_reverse()


func _new_window() -> void:
	# lontana dalla lancetta (almeno 100°), così c'è il tempo di prepararsi
	var a := needle_angle()
	window_center = wrapf(a + _rng.randf_range(deg_to_rad(100.0), deg_to_rad(260.0)), 0.0, TAU)
	passes = 0
	_prev_diff = diff_to_window(a)


func _schedule_reverse() -> void:
	_next_reverse = now() + _rng.randf_range(reverse_interval.x, reverse_interval.y) if level >= reverse_from_level else INF


func _game_over() -> void:
	best = maxi(best, score)
	_over_time = 0.0
	_set_state(State.GAME_OVER)


func _process(delta: float) -> void:
	_flash = maxf(_flash - delta, 0.0)
	match state:
		State.WAITING:
			if Input.is_action_just_pressed(&"game_start"):
				start_game()
		State.PLAYING:
			_track_passes()
			if now() >= _next_reverse:
				_set_needle(needle_angle(), -speed)
				_schedule_reverse()
		State.GAME_OVER:
			_over_time += delta
			if _over_time >= game_over_cooldown and Input.is_action_just_pressed(&"game_start"):
				start_game()
	if not armed and not _hand_in_zone():
		armed = true
	_update_title()
	queue_redraw()


## Conta i passaggi della lancetta sul centro della finestra: troppi → vita persa.
func _track_passes() -> void:
	var d := diff_to_window(needle_angle())
	if signf(d) != signf(_prev_diff) and absf(d) < PI / 2.0 and absf(_prev_diff) < PI / 2.0:
		passes += 1
		if passes >= max_passes:
			_apply_result(Result.TIMEOUT)
			return
	_prev_diff = d


# --- Filo e mano -------------------------------------------------------------------

func _on_zone_entered(area: Area2D) -> void:
	if not BodyColliders.is_body_part(area) or not _accepts(area):
		return
	match state:
		State.PLAYING:
			cut()
		State.WAITING:
			start_game()
		State.GAME_OVER:
			if _over_time >= game_over_cooldown:
				start_game()


func _accepts(area: Area2D) -> bool:
	return colliders.part_filter.is_empty() or colliders.part_filter.has(str(area.get_meta(&"part", "")))


func _hand_in_zone() -> bool:
	for a in wire_zone.get_overlapping_areas():
		if BodyColliders.is_body_part(a) and _accepts(a):
			return true
	return false


func _apply_hand_filter() -> void:
	colliders.part_filter = PackedStringArray([play_part]) if BodyInput.has_capability("pose") else PackedStringArray()


# --- Disegno -------------------------------------------------------------------------

func dial_center() -> Vector2:
	var vp := get_viewport_rect().size
	return Vector2(vp.x * 0.42, vp.y * 0.5)


func dial_radius() -> float:
	return get_viewport_rect().size.y * 0.3


func wire_rect() -> Rect2:
	var vp := get_viewport_rect().size
	var w := vp.y * 0.16
	var x := minf(vp.x * 0.8, vp.x - w - vp.y * 0.04)
	x = maxf(x, dial_center().x + dial_radius() + vp.y * 0.05)
	return Rect2(Vector2(x, vp.y * 0.18), Vector2(w, vp.y * 0.52))


func _layout() -> void:
	var r := wire_rect()
	wire_zone.position = r.get_center()
	_zone_shape.size = r.size


func _set_state(s: State) -> void:
	state = s
	_update_title()


func _update_title() -> void:
	match state:
		State.WAITING:
			title_label.text = "Porta la mano destra sul filo per iniziare"
		State.PLAYING:
			title_label.text = "Punti %d   ·   Livello %d   ·   Vite %d" % [score, level, lives]
		State.GAME_OVER:
			var again := "\nMano sul filo per rigiocare" if _over_time >= game_over_cooldown else ""
			title_label.text = "Filo sbagliato! %d punti (record %d)%s" % [score, best, again]


func _draw() -> void:
	var vp := get_viewport_rect().size
	var bg := BG.lerp(BAD, _flash * 0.35) if last_result in [Result.MISS, Result.TIMEOUT] else BG
	draw_rect(Rect2(Vector2.ZERO, vp), bg)
	var c := dial_center()
	var r := dial_radius()
	var w := maxf(vp.y * 0.01, 2.0)
	draw_circle(c, r, DIAL)
	draw_arc(c, r, 0.0, TAU, 96, DIAL_EDGE, w * 0.5, true)
	# finestra verde (e parte "perfetta") — angoli con 0 in alto, orario
	if state == State.PLAYING:
		var a0 := window_center - window_width * 0.5 - PI / 2.0
		draw_arc(c, r * 0.86, a0, a0 + window_width, 32, WINDOW_COLOR, r * 0.22, true)
		var pw := window_width * perfect_fraction
		var p0 := window_center - pw * 0.5 - PI / 2.0
		draw_arc(c, r * 0.86, p0, p0 + pw, 16, PERFECT_COLOR, r * 0.22, true)
		# passaggi rimasti
		for i in max_passes:
			var col := DIAL_EDGE if i < max_passes - passes else Color(DIAL_EDGE, 0.15)
			draw_circle(c + Vector2(-r * 0.2 + i * r * 0.2, r * 0.45), r * 0.05, col)
	# lancetta
	var ang := needle_angle()
	var tip := c + Vector2(sin(ang), -cos(ang)) * r * 0.95
	draw_line(c, tip, NEEDLE, w, true)
	draw_circle(c, w * 1.5, NEEDLE)
	if _flash > 0.0 and last_result in [Result.HIT, Result.PERFECT]:
		draw_arc(c, r * (1.0 + (0.5 - _flash) * 0.4), 0.0, TAU, 64, Color(WINDOW_COLOR, _flash * 2.0), w, true)
	# filo
	var z := wire_rect()
	var col_wire := WIRE_ARMED if armed else Color(WIRE, 0.5)
	draw_rect(z, Color(col_wire, 0.08))
	var x := z.get_center().x
	var pts := PackedVector2Array()
	for i in 13:
		pts.append(Vector2(x + (z.size.x * 0.12 if i % 2 == 0 else -z.size.x * 0.12), z.position.y + z.size.y * i / 12.0))
	draw_polyline(pts, col_wire, w, true)
	draw_string(ThemeDB.fallback_font, Vector2(z.position.x, z.end.y + vp.y * 0.06), "TAGLIA" if armed else "...",
		HORIZONTAL_ALIGNMENT_CENTER, z.size.x, maxi(int(vp.y * 0.04), 8), col_wire)
