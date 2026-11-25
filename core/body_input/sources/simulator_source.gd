extends RefCounted
## Simula il tracker con il mouse, per sviluppare senza camera.
## Il mouse muove polso destro (e marker) del giocatore attivo; il resto del busto resta
## dove il giocatore è comparso (spalle, naso, braccio sinistro a riposo).
## Azioni: sim_next_player (cambia giocatore), sim_hand_close (mano chiusa finché premuta).
## Il giocatore compare con la spalla destra un po' sopra il mouse: alzando il mouse
## sopra la spalla si "alza il braccio".

const IDS: Array[StringName] = [&"red", &"blue", &"yellow"]
const SHOULDER_FROM_MOUSE := Vector2(0.0, -0.2)
const SHOULDER_SPAN := 0.12  # distanza tra le spalle (normalizzata)

var active: int = 0

## id -> {shoulder_r: Vector2, wrist: Vector2, open: float}
var _bodies: Dictionary = {}


func make_packet(mouse: Vector2) -> Dictionary:
	if InputMap.has_action(&"sim_next_player") and Input.is_action_just_pressed(&"sim_next_player"):
		active = (active + 1) % IDS.size()
	var id := IDS[active]
	if not _bodies.has(id):
		_bodies[id] = {"shoulder_r": mouse + SHOULDER_FROM_MOUSE, "wrist": mouse, "open": 1.0}
	var closed := InputMap.has_action(&"sim_hand_close") and Input.is_action_pressed(&"sim_hand_close")
	_bodies[id]["wrist"] = mouse
	_bodies[id]["open"] = 0.0 if closed else 1.0

	var players: Array = []
	for pid: StringName in _bodies:
		players.append(_player(pid, _bodies[pid]))
	return {"v": 1, "space": "screen", "caps": ["effectors", "hands", "markers", "pose"], "players": players}


static func _player(pid: StringName, b: Dictionary) -> Dictionary:
	# Vista a specchio: la destra della persona sta a destra sullo schermo.
	var sr: Vector2 = b["shoulder_r"]
	var sl := sr + Vector2(-SHOULDER_SPAN, 0.0)
	var sc := (sr + sl) * 0.5
	var w: Vector2 = b["wrist"]
	var er := (sr + w) * 0.5 + (w - sr).orthogonal().normalized() * 0.03
	var pose := {
		"nose": sc + Vector2(0.0, -0.12),
		"shoulder_l": sl, "shoulder_r": sr, "shoulder_c": sc,
		"elbow_l": sl + Vector2(-0.02, 0.12), "wrist_l": sl + Vector2(-0.03, 0.24),
		"elbow_r": er, "wrist_r": w,
	}
	var pose_arr := {}
	for k: String in pose:
		var v: Vector2 = pose[k]
		pose_arr[k] = [v.x, v.y, 1.0]
	return {
		"id": String(pid),
		"marker": {"x": w.x, "y": w.y, "area": 0.004},
		"pose": pose_arr,
		"hands": {"r": {"wrist": [w.x, w.y, 1.0], "open": b["open"], "pinch": 0.0}},
	}
