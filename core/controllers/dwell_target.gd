class_name DwellTarget
extends Area2D
## Bersaglio "a sosta": si attiva quando un effettore (mano, punto di contatto) ci resta
## sopra per dwell_time secondi. È il "clic" dei menu e dei giochi comandati col corpo.
## Disegna un anello che si riempie. Rettangolare, centrato sulla posizione del nodo.

signal selected
signal progress_changed(progress: float)

@export var size: Vector2 = Vector2(200, 200)
@export var dwell_time: float = 1.2
## Velocità con cui l'avanzamento torna a zero quando l'effettore esce (x dwell_time).
@export var decay: float = 2.0
@export var ring_color: Color = Color(1, 1, 1, 0.9)
@export var show_ring: bool = true

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


## Cambia la dimensione anche dopo che il nodo è nella scena.
func set_box_size(v: Vector2) -> void:
	size = v
	_shape.size = v
	queue_redraw()


func is_hovered() -> bool:
	for a: Area2D in _inside.keys():
		if not is_instance_valid(a):
			_inside.erase(a)
	return not _inside.is_empty()


func reset() -> void:
	progress = 0.0
	_fired = false


func _physics_process(delta: float) -> void:
	var old := progress
	if is_hovered():
		progress = minf(progress + delta / dwell_time, 1.0)
		if progress >= 1.0 and not _fired:
			_fired = true
			selected.emit()
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
