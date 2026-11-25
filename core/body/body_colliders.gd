class_name BodyColliders
extends Node2D
## Mette un'Area2D sugli effettori (BodyMetrics.effectors: le mani, o i punti di contatto
## di sensori senza scheletro) e, a richiesta, sugli avambracci di ogni giocatore, così i
## giochi usano le normali collisioni di Godot senza sapere niente del sensore.
## Le aree stanno sul layer fisico "body" (layer 2): gli oggetti di gioco che devono
## sentirle mettono quel layer nella loro collision_mask.
##
## Ogni area ha i metadati "player_id" (StringName), "part" ("hand_l", "forearm_r"...)
## e "velocity" (Vector2, pixel/s). "part" è il nome dell'effettore: "hand_l"/"hand_r"
## con la pose, "e0", "e1"... con sensori a contatto. Usa BodyColliders.owner_of(area) per sapere di chi è.
## Il nodo va lasciato all'origine (posizioni in pixel della viewport).

signal part_added(area: Area2D)
signal part_removed(area: Area2D)

const BODY_LAYER := 2  # bit del layer 2 "body"

## Aree sugli effettori (mani o punti di contatto).
@export var effectors: bool = true
## Solo questi effettori (es. ["hand_r"] per giocare con la mano destra); vuoto = tutti.
@export var part_filter: PackedStringArray = []
## Avambracci (gomito → mano) come bastoni: per i giochi "braccio come bastone".
@export var forearms: bool = false
## Raggio delle aree sugli effettori, in frazione dell'altezza dello schermo.
@export var hand_radius_ratio: float = 0.06
@export var forearm_thickness_ratio: float = 0.035
@export_flags_2d_physics var layer: int = BODY_LAYER
## Disegna le aree (cerchi colorati sulle mani): utile come "cursore" per i giocatori.
@export var show_parts: bool = true

var _parts: Dictionary = {}  # "id/part" -> Area2D


static func is_body_part(area: Area2D) -> bool:
	return area != null and area.has_meta(&"player_id")


static func owner_of(area: Area2D) -> StringName:
	return area.get_meta(&"player_id", &"") if area != null else &""


func get_parts() -> Array[Area2D]:
	var out: Array[Area2D] = []
	for a: Area2D in _parts.values():
		out.append(a)
	return out


func get_part(player_id: StringName, part: String) -> Area2D:
	return _parts.get("%s/%s" % [player_id, part])


func _physics_process(delta: float) -> void:
	var h := get_viewport_rect().size.y
	var alive := {}
	for p in BodyInput.get_players():
		if effectors:
			var eff := BodyMetrics.effectors(p)
			for part: String in eff:
				if not part_filter.is_empty() and not part_filter.has(part):
					continue
				var key := _place_circle(p.id, part, eff[part], h * hand_radius_ratio, delta)
				alive[key] = true
		if forearms:
			for side in ["l", "r"]:
				var elbow := StringName("elbow_" + side)
				if p.has_point(elbow) and BodyMetrics.has_hand(p, side):
					var key := _place_segment(p.id, "forearm_" + side, p.point(elbow), BodyMetrics.hand_center(p, side), h * forearm_thickness_ratio, delta)
					alive[key] = true
	for key: String in _parts.keys():
		if not alive.has(key):
			var a: Area2D = _parts[key]
			_parts.erase(key)
			part_removed.emit(a)
			a.queue_free()
	queue_redraw()


func _get_area(player_id: StringName, part: String, circle: bool) -> Area2D:
	var key := "%s/%s" % [player_id, part]
	if _parts.has(key):
		return _parts[key]
	var a := Area2D.new()
	a.name = key.replace("/", "_")
	a.collision_layer = layer
	a.collision_mask = 0
	a.monitoring = false
	a.monitorable = true
	a.set_meta(&"player_id", player_id)
	a.set_meta(&"part", part)
	a.set_meta(&"velocity", Vector2.ZERO)
	var cs := CollisionShape2D.new()
	cs.shape = CircleShape2D.new() if circle else RectangleShape2D.new()
	a.add_child(cs)
	add_child(a)
	_parts[key] = a
	part_added.emit(a)
	return a


func _place_circle(player_id: StringName, part: String, pos: Vector2, radius: float, delta: float) -> String:
	var a := _get_area(player_id, part, true)
	var cs: CollisionShape2D = a.get_child(0)
	(cs.shape as CircleShape2D).radius = radius
	_move(a, pos, 0.0, delta)
	return "%s/%s" % [player_id, part]


func _place_segment(player_id: StringName, part: String, from: Vector2, to: Vector2, thickness: float, delta: float) -> String:
	var a := _get_area(player_id, part, false)
	var cs: CollisionShape2D = a.get_child(0)
	(cs.shape as RectangleShape2D).size = Vector2(maxf(from.distance_to(to), 1.0), thickness)
	_move(a, (from + to) * 0.5, (to - from).angle(), delta)
	return "%s/%s" % [player_id, part]


func _move(a: Area2D, pos: Vector2, angle: float, delta: float) -> void:
	if delta > 0.0 and a.has_meta(&"placed"):
		a.set_meta(&"velocity", (pos - a.global_position) / delta)
	a.global_position = pos
	a.rotation = angle
	a.set_meta(&"placed", true)


func _draw() -> void:
	if not show_parts:
		return
	for a: Area2D in _parts.values():
		var c := BodyDebugDraw.color_for(owner_of(a))
		var cs: CollisionShape2D = a.get_child(0)
		if cs.shape is CircleShape2D:
			var r := (cs.shape as CircleShape2D).radius
			draw_circle(a.position, r, Color(c, 0.25))
			draw_arc(a.position, r, 0.0, TAU, 40, c, 4.0, true)
		elif cs.shape is RectangleShape2D:
			var s := (cs.shape as RectangleShape2D).size
			draw_set_transform(a.position, a.rotation)
			draw_rect(Rect2(-s * 0.5, s), Color(c, 0.6))
			draw_set_transform(Vector2.ZERO)
