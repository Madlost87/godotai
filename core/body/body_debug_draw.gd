class_name BodyDebugDraw
extends Node2D
## Disegna tutti i giocatori di BodyInput: scheletro, punti, marker, mani, faccia, id.
## Da aggiungere a qualsiasi scena come overlay di debug (SPEC §6.2).

const PLAYER_COLORS := {
	&"red": Color(0.95, 0.3, 0.3),
	&"blue": Color(0.3, 0.55, 1.0),
	&"yellow": Color(1.0, 0.85, 0.25),
	&"p1": Color(0.35, 0.9, 0.55),
	&"p2": Color(0.85, 0.45, 1.0),
	&"p3": Color(0.3, 0.9, 0.9),
}
const OTHER_COLOR := Color(0.7, 0.7, 0.7)
const BONES: Array = [
	[&"shoulder_l", &"shoulder_r"], [&"shoulder_l", &"elbow_l"], [&"elbow_l", &"wrist_l"],
	[&"shoulder_r", &"elbow_r"], [&"elbow_r", &"wrist_r"], [&"shoulder_l", &"hip_l"],
	[&"shoulder_r", &"hip_r"], [&"hip_l", &"hip_r"], [&"nose", &"face"],
	[&"wrist_l", &"index_l"], [&"wrist_r", &"index_r"],
	[&"hip_l", &"knee_l"], [&"knee_l", &"ankle_l"], [&"ankle_l", &"heel_l"], [&"heel_l", &"foot_l"],
	[&"hip_r", &"knee_r"], [&"knee_r", &"ankle_r"], [&"ankle_r", &"heel_r"], [&"heel_r", &"foot_r"],
	[&"ear_l", &"eye_l"], [&"eye_l", &"nose"], [&"nose", &"eye_r"], [&"eye_r", &"ear_r"],
	[&"mouth_l", &"mouth_r"],
]

@export var line_width: float = 6.0
@export var show_labels: bool = true
## Giochi a una mano: il braccio di questo lato ("l" o "r") si disegna grigio e tenue,
## per far capire che non conta. Vuoto = tutto a colori.
@export var dim_side: String = ""

const DIM_COLOR := Color(0.6, 0.6, 0.6, 0.25)


## Vero se il punto appartiene al braccio attenuato (gomito, polso, mano).
func is_dimmed(point_name: StringName) -> bool:
	if dim_side.is_empty():
		return false
	var n := String(point_name)
	for part in ["elbow_", "wrist_", "index_", "pinky_", "thumb_"]:
		if n == part + dim_side:
			return true
	return n.begins_with("hand_%s." % dim_side)


static func color_for(id: StringName) -> Color:
	return PLAYER_COLORS.get(id, OTHER_COLOR)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	for p in BodyInput.get_players():
		_draw_player(p)


func _draw_player(p: PlayerState) -> void:
	var c := color_for(p.id)
	for bone: Array in BONES:
		if p.has_point(bone[0]) and p.has_point(bone[1]):
			var dim: bool = is_dimmed(bone[0]) or is_dimmed(bone[1])
			draw_line(p.point(bone[0]), p.point(bone[1]), DIM_COLOR if dim else c.darkened(0.2), line_width, true)
	for n in p.point_names():
		if n != &"marker" and n != &"face":
			draw_circle(p.point(n), line_width, DIM_COLOR if is_dimmed(n) else c.lightened(0.3))
	for side in ["l", "r"]:
		var key := StringName("hand_%s.wrist" % side)
		var open_key := StringName("hand_%s.open" % side)
		if p.has_point(key) and p.has_value(open_key):
			var hc := DIM_COLOR if side == dim_side else Color.WHITE
			if p.value(open_key) > 0.5:
				draw_arc(p.point(key), 22.0, 0.0, TAU, 32, hc, 3.0, true)
			else:
				draw_circle(p.point(key), 16.0, hc)
	if p.has_point(&"face"):
		var f := p.point(&"face")
		draw_arc(f, 40.0, 0.0, TAU, 40, c, 3.0, true)
		var yaw := deg_to_rad(p.value(&"face.yaw"))
		draw_line(f, f + Vector2(sin(yaw), 0.0) * 40.0, c, 3.0, true)
	if p.has_point(&"marker"):
		draw_circle(p.point(&"marker"), 26.0, c)
	if show_labels:
		var anchor := _label_anchor(p)
		draw_string(ThemeDB.fallback_font, anchor + Vector2(-20, -40), String(p.id), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, c)


func _label_anchor(p: PlayerState) -> Vector2:
	for n: StringName in [&"marker", &"nose", &"shoulder_c", &"face"]:
		if p.has_point(n):
			return p.point(n)
	var names := p.point_names()
	return p.point(names[0]) if not names.is_empty() else Vector2.ZERO
