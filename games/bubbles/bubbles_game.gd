extends Node2D
## Minigioco "Bolle" (un giocatore): le bolle salgono dal basso, si scoppiano
## toccandole con le mani. Normale +1, dorata +3, spinosa -3. Partita di round_time
## secondi, con record della sessione.
## Si parte (e si riparte) con l'azione "game_start": braccio alzato (GestureController)
## oppure Invio.
## All'avvio chiede al tracker un solo giocatore (BodyInput.set_session).

enum State { WAITING, PLAYING, RESULTS }

const BG_TOP := Color(0.05, 0.1, 0.16)
const BG_BOTTOM := Color(0.08, 0.2, 0.26)
const TEXT_COLOR := Color(0.92, 0.97, 1.0)

## Giocatori chiesti al tracker. Con la webcam del portatile bisogna stare vicini: 1.
@export var max_players: int = 1
@export var round_time: float = 60.0
## Se false le bolle non nascono da sole (test).
@export var auto_spawn: bool = true
@export var spawn_interval_start: float = 0.9
@export var spawn_interval_end: float = 0.4
@export var golden_chance: float = 0.08
@export var spiky_chance: float = 0.12
## Raggio delle bolle, in frazione dell'altezza dello schermo.
@export var radius_min_ratio: float = 0.07
@export var radius_max_ratio: float = 0.11
## Velocità di salita, in altezze dello schermo al secondo (inizio → fine partita).
@export var speed_start_ratio: float = 0.12
@export var speed_end_ratio: float = 0.22
## Secondi sui risultati prima di poter ripartire.
@export var results_cooldown: float = 3.0

var state: State = State.WAITING
var score: int = 0
## Miglior punteggio da quando il gioco è aperto.
var best: int = 0
var new_record: bool = false
var time_left: float = 0.0

var _spawn_timer: float = 0.0
var _results_time: float = 0.0
var _rng := RandomNumberGenerator.new()

@onready var bubbles_root: Node2D = $Bubbles
@onready var title_label: Label = $HUD/Title
@onready var timer_label: Label = $HUD/Timer
@onready var score_label: Label = $HUD/Score


func _ready() -> void:
	_rng.randomize()
	BodyInput.set_session({"max_players": max_players})
	_set_state(State.WAITING)


func _exit_tree() -> void:
	BodyInput.clear_session()


func _process(delta: float) -> void:
	match state:
		State.WAITING:
			if Input.is_action_just_pressed(&"game_start"):
				start_round()
		State.PLAYING:
			time_left -= delta
			if auto_spawn:
				_spawn_timer -= delta
				if _spawn_timer <= 0.0:
					_spawn_random()
					_spawn_timer = lerpf(spawn_interval_end, spawn_interval_start, _remaining_fraction())
			if time_left <= 0.0:
				end_round()
		State.RESULTS:
			_results_time += delta
			if _results_time >= results_cooldown and Input.is_action_just_pressed(&"game_start"):
				start_round()
	_update_hud()
	queue_redraw()


func start_round() -> void:
	score = 0
	new_record = false
	_clear_bubbles()
	time_left = round_time
	_spawn_timer = 0.0
	_set_state(State.PLAYING)


func end_round() -> void:
	time_left = 0.0
	_clear_bubbles()
	_results_time = 0.0
	new_record = score > best
	best = maxi(best, score)
	_set_state(State.RESULTS)


func spawn_bubble(pos: Vector2, kind: Bubble.Kind = Bubble.Kind.NORMAL, radius: float = -1.0, speed: float = -1.0) -> Bubble:
	var h := get_viewport_rect().size.y
	if radius < 0.0:
		radius = h * _rng.randf_range(radius_min_ratio, radius_max_ratio)
	if speed < 0.0:
		speed = h * lerpf(speed_end_ratio, speed_start_ratio, _remaining_fraction()) * _rng.randf_range(0.85, 1.15)
	var b := Bubble.new().setup(kind, pos, radius, speed)
	b.popped.connect(_on_bubble_popped)
	bubbles_root.add_child(b)
	return b


func get_bubbles() -> Array[Bubble]:
	var out: Array[Bubble] = []
	for c in bubbles_root.get_children():
		if c is Bubble and not (c as Bubble).is_popped:
			out.append(c)
	return out


func _spawn_random() -> void:
	var size := get_viewport_rect().size
	var r := size.y * _rng.randf_range(radius_min_ratio, radius_max_ratio)
	var kind := Bubble.Kind.NORMAL
	var roll := _rng.randf()
	if roll < spiky_chance:
		kind = Bubble.Kind.SPIKY
	elif roll < spiky_chance + golden_chance:
		kind = Bubble.Kind.GOLDEN
	spawn_bubble(Vector2(_rng.randf_range(r * 1.5, size.x - r * 1.5), size.y + r), kind, r)


func _on_bubble_popped(bubble: Bubble, _player_id: StringName) -> void:
	if state == State.PLAYING:
		score += bubble.points()


func _clear_bubbles() -> void:
	for c in bubbles_root.get_children():
		c.queue_free()


func _remaining_fraction() -> float:
	return clampf(time_left / round_time, 0.0, 1.0) if round_time > 0.0 else 0.0


func _set_state(s: State) -> void:
	state = s
	match s:
		State.WAITING:
			title_label.text = "BOLLE\nAlza un braccio per iniziare"
		State.PLAYING:
			title_label.text = ""
		State.RESULTS:
			title_label.text = _results_text()


func _results_text() -> String:
	var s := "Tempo scaduto!\n%d punti" % score
	if new_record and score > 0:
		s += " — nuovo record!"
	return s


func _update_hud() -> void:
	timer_label.text = "%d" % ceili(time_left) if state == State.PLAYING else ""
	score_label.text = "Punti  %d\nRecord  %d" % [score, best]
	if state == State.RESULTS and _results_time >= results_cooldown and not title_label.text.ends_with("ancora"):
		title_label.text = _results_text() + "\n\nAlza un braccio per giocare ancora"
	elif state == State.WAITING:
		var someone := not BodyInput.get_players().is_empty()
		title_label.text = "BOLLE\n" + ("Alza un braccio per iniziare" if someone else "Mettiti davanti alla camera")


func _draw() -> void:
	var size := get_viewport_rect().size
	var steps := 12
	for i in steps:
		var y0 := size.y * i / steps
		draw_rect(Rect2(0, y0, size.x, size.y / steps + 1.0), BG_TOP.lerp(BG_BOTTOM, float(i) / (steps - 1)))
