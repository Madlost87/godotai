class_name DwellTarget
extends Area2D
## Bersaglio "a sosta": si attiva quando un effettore (mano, punto di contatto) ci resta
## sopra per dwell_time secondi. È il "clic" dei menu e dei giochi comandati col corpo.
## Disegna un anello che si riempie. Rettangolare, centrato sulla posizione del nodo.

signal selected
## Come `selected`, con chi l'ha attivato (giocatore e parte, es. &"p1", "hand_r").
signal selected_by(player_id: StringName, part: String)
signal progress_changed(progress: float)

@export var size: Vector2 = Vector2(200, 200)
@export var dwell_time: float = 1.2
## Velocità con cui l'avanzamento torna a zero quando l'effettore esce (x dwell_time).
@export var decay: float = 2.0
@export var ring_color: Color = Color(1, 1, 1, 0.9)
@export var show_ring: bool = true
## Se false il bersaglio non reagisce (es. casella già occupata) e l'anello si azzera.
@export var enabled: bool = true
## Solo queste parti attivano il bersaglio (es. ["hand_r"]); vuoto = tutte.
@export var accept_parts: PackedStringArray = []
## Solo questi giocatori (es. ["p1"]); vuoto = tutti.
@export var accept_players: PackedStringArray = []
## Bersagli con lo stesso gruppo si escludono: una mano conta solo per il bersaglio del
## gruppo più vicino al suo centro, anche se ne tocca più di uno (es. a cavallo di due
## caselle di una griglia). Vuoto = nessuna esclusione.
@export var exclusive_group: StringName = &""

static var _groups: Dictionary = {}  # StringName -> Array (DwellTarget)

var progress: float = 0.0
var _inside: Dictionary = {}  # Area2D -> true
var _fired: bool = false
var _shape := RectangleShape2D.new()


func _ready() -> void:
	collision_layer = 0
	collision_mask = BodyColliders.BODY_LAYER
	monitorable = false
	var cs := CollisionShape2D.new()
	_shape.size = size
	cs.shape = _shape
	add_child(cs)
	area_entered.connect(func(a: Area2D) -> void:
		if BodyColliders.is_body_part(a):
			_inside[a] = true)
	area_exited.connect(func(a: Area2D) -> void: _inside.erase(a))


func _enter_tree() -> void:
	if exclusive_group != &"":
		if not _groups.has(exclusive_group):
			_groups[exclusive_group] = []
		_groups[exclusive_group].append(self)


func _exit_tree() -> void:
	if _groups.has(exclusive_group):
		_groups[exclusive_group].erase(self)
		if _groups[exclusive_group].is_empty():
			_groups.erase(exclusive_group)


## Cambia la dimensione anche dopo che il nodo è nella scena.
func set_box_size(v: Vector2) -> void:
	size = v
	_shape.size = v
	queue_redraw()


func is_hovered() -> bool:
	return not hovering_parts().is_empty()


## Aree del corpo accettate (filtri) che ora sono sopra il bersaglio.
func hovering_parts() -> Array[Area2D]:
	var out: Array[Area2D] = []
	for a: Area2D in _inside.keys():
		if not is_instance_valid(a):
			_inside.erase(a)
		elif accepts(a) and _owns(a):
			out.append(a)
	return out


## Con un gruppo esclusivo: questa mano "punta" proprio questo bersaglio?
## (è il più vicino al centro della mano tra quelli del gruppo che la stanno toccando;
## conta anche se è disattivato: puntare una casella occupata non segna la vicina)
func _owns(a: Area2D) -> bool:
	if exclusive_group == &"" or not _groups.has(exclusive_group):
		return true
	var my_d := a.global_position.distance_squared_to(global_position)
	for t: DwellTarget in _groups[exclusive_group]:
		if t == self or not is_instance_valid(t) or not t._inside.has(a) or not t.accepts(a):
			continue
		var d := a.global_position.distance_squared_to(t.global_position)
		if d < my_d or (d == my_d and t.get_instance_id() < get_instance_id()):
			return false
	return true


func accepts(a: Area2D) -> bool:
	if not accept_parts.is_empty() and not accept_parts.has(str(a.get_meta(&"part", ""))):
		return false
	if not accept_players.is_empty() and not accept_players.has(String(BodyColliders.owner_of(a))):
		return false
	return true


func reset() -> void:
	progress = 0.0
	_fired = false


func _physics_process(delta: float) -> void:
	var old := progress
	var parts := hovering_parts() if enabled else ([] as Array[Area2D])
	if not enabled:
		progress = 0.0
		_fired = false
	elif not parts.is_empty():
		progress = minf(progress + delta / dwell_time, 1.0)
		if progress >= 1.0 and not _fired:
			_fired = true
			var who: Area2D = parts[0]
			selected.emit()
			selected_by.emit(BodyColliders.owner_of(who), str(who.get_meta(&"part", "")))
	else:
		progress = maxf(progress - delta * decay / dwell_time, 0.0)
		if progress <= 0.0:
			_fired = false
	if progress != old:
		progress_changed.emit(progress)
		queue_redraw()


func _draw() -> void:
	if not show_ring or progress <= 0.0:
		return
	var r := minf(size.x, size.y) * 0.25
	draw_arc(Vector2.ZERO, r, -PI / 2.0, -PI / 2.0 + TAU * progress, 48, ring_color, 8.0, true)
