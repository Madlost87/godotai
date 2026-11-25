class_name Bubble
extends Area2D
## Una bolla che sale ondeggiando. Scoppia quando la tocca una parte del corpo
## (un'area di BodyColliders sul layer "body").

signal popped(bubble: Bubble, player_id: StringName)
signal escaped(bubble: Bubble)

enum Kind { NORMAL, GOLDEN, SPIKY }

const COLORS := {
	Kind.NORMAL: Color(0.55, 0.85, 0.95),
	Kind.GOLDEN: Color(1.0, 0.75, 0.45),
	Kind.SPIKY: Color(0.55, 0.3, 0.6),
}
const POINTS := {Kind.NORMAL: 1, Kind.GOLDEN: 3, Kind.SPIKY: -3}

var kind: Kind = Kind.NORMAL
var radius: float = 50.0
var speed: float = 80.0  # pixel/s verso l'alto
var is_popped: bool = false

var _t: float = 0.0
var _phase: float = 0.0
var _base_x: float = 0.0
var _pop_t: float = -1.0


func setup(p_kind: Kind, pos: Vector2, p_radius: float, p_speed: float) -> Bubble:
	kind = p_kind
	position = pos
	radius = p_radius
	speed = p_speed
	_base_x = pos.x
	_phase = randf() * TAU
	return self


func _ready() -> void:
	collision_layer = 0
	collision_mask = BodyColliders.BODY_LAYER
	monitorable = false
	var cs := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = radius
	cs.shape = shape
	add_child(cs)
	area_entered.connect(_on_area_entered)


func points() -> int:
	return POINTS[kind]


func _physics_process(delta: float) -> void:
	if is_popped:
		return
	_t += delta
	position.y -= speed * delta
	position.x = _base_x + sin(_t * 1.3 + _phase) * radius * 0.3
	if position.y < -radius * 1.5:
		escaped.emit(self)
		queue_free()


func _process(delta: float) -> void:
	if is_popped:
		_pop_t += delta
		if _pop_t >= 0.25:
			queue_free()
	queue_redraw()


func _on_area_entered(area: Area2D) -> void:
	if BodyColliders.is_body_part(area):
		pop(BodyColliders.owner_of(area))


func pop(player_id: StringName) -> void:
	if is_popped:
		return
	is_popped = true
	_pop_t = 0.0
	set_deferred(&"monitoring", false)
	popped.emit(self, player_id)


func _draw() -> void:
	var c: Color = COLORS[kind]
	if is_popped:  # anello che si allarga e svanisce
		var k := clampf(_pop_t / 0.25, 0.0, 1.0)
		draw_arc(Vector2.ZERO, radius * (1.0 + k * 0.6), 0.0, TAU, 40, Color(c, 1.0 - k), 6.0 * (1.0 - k) + 1.0, true)
		return
	if kind == Kind.SPIKY:
		var pts := PackedVector2Array()
		for i in 24:
			var a := TAU * i / 24.0
			var r := radius * (1.15 if i % 2 == 0 else 0.85)
			pts.append(Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(pts, Color(c, 0.85))
		return
	draw_circle(Vector2.ZERO, radius, Color(c, 0.35))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(c, 0.95), 4.0, true)
	draw_circle(Vector2(-radius * 0.35, -radius * 0.35), radius * 0.18, Color(1, 1, 1, 0.6))
