class_name GestureController
extends Node
## Trasforma un gesto del corpo in un'azione dell'Input Map (SPEC §6.3).
## Isteresi (soglia di attivazione > soglia di rilascio) e tempo minimo evitano falsi
## positivi. L'azione resta premuta finché almeno un giocatore fa il gesto.
## Gira prima degli altri nodi (process_priority negativa), così nello stesso frame
## Input.is_action_just_pressed() vede già il gesto.

signal activated(player_id: StringName)
signal deactivated(player_id: StringName)

enum Gesture {
	ANY_ARM_RAISED,  ## almeno un braccio alzato (BodyMetrics.arm_raised)
	BOTH_ARMS_RAISED,  ## entrambe le braccia alzate
	ARMS_SPREAD,  ## braccia aperte: arms_spread / 3
}

@export var gesture: Gesture = Gesture.ANY_ARM_RAISED
@export var action: StringName = &"game_start"
## Vuoto = qualsiasi giocatore.
@export var player_id: StringName = &""
@export_range(0.0, 1.0) var threshold_on: float = 0.7
@export_range(0.0, 1.0) var threshold_off: float = 0.4
## Secondi sopra la soglia prima di attivare.
@export var hold_time: float = 0.4

var _held: Dictionary = {}  # id -> secondi sopra soglia
var _active: Dictionary = {}  # id -> true


func _ready() -> void:
	process_priority = -10
	if not InputMap.has_action(action):
		push_warning("GestureController: l'azione '%s' non esiste nell'Input Map" % action)


func _exit_tree() -> void:
	if not _active.is_empty() and InputMap.has_action(action):
		Input.action_release(action)


func is_active(id: StringName = &"") -> bool:
	return _active.has(id) if id != &"" else not _active.is_empty()


func value_for(p: PlayerState) -> float:
	var v: float
	match gesture:
		Gesture.ANY_ARM_RAISED:
			v = maxf(_nz(BodyMetrics.arm_raised(p, "l")), _nz(BodyMetrics.arm_raised(p, "r")))
		Gesture.BOTH_ARMS_RAISED:
			v = minf(_nz(BodyMetrics.arm_raised(p, "l")), _nz(BodyMetrics.arm_raised(p, "r")))
		Gesture.ARMS_SPREAD:
			v = clampf(_nz(BodyMetrics.arms_spread(p)) / 3.0, 0.0, 1.0)
	return v


func _process(delta: float) -> void:
	var seen := {}
	for p in BodyInput.get_players():
		if player_id != &"" and p.id != player_id:
			continue
		seen[p.id] = true
		var v := value_for(p)
		if _active.has(p.id):
			if v < threshold_off:
				_set_active(p.id, false)
		elif v >= threshold_on:
			_held[p.id] = float(_held.get(p.id, 0.0)) + delta
			if _held[p.id] >= hold_time:
				_set_active(p.id, true)
		else:
			_held[p.id] = 0.0
	for id: StringName in _active.keys():
		if not seen.has(id):
			_set_active(id, false)
	for id: StringName in _held.keys():
		if not seen.has(id):
			_held.erase(id)


func _set_active(id: StringName, on: bool) -> void:
	var was_any := not _active.is_empty()
	if on:
		_active[id] = true
		activated.emit(id)
	else:
		_active.erase(id)
		_held[id] = 0.0
		deactivated.emit(id)
	var now_any := not _active.is_empty()
	if now_any != was_any and InputMap.has_action(action):
		if now_any:
			Input.action_press(action)
		else:
			Input.action_release(action)


static func _nz(v: float) -> float:
	return 0.0 if is_nan(v) else v
