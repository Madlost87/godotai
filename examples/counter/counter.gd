extends Node2D
## Scena principale: gestisce il contatore incrementato dall'azione "increment_counter"
## (Spazio di default; rimappabile in Project Settings > Input Map).

var counter: int = 0

@onready var counter_label: Label = $HUD/CounterLabel


func _ready() -> void:
	_update_label()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("increment_counter") and not event.is_echo():
		counter += 1
		_update_label()
		get_viewport().set_input_as_handled()


func _update_label() -> void:
	counter_label.text = "Contatore: %d" % counter
