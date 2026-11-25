extends Node2D
## Demo del ponte BodyInput: sfondo + overlay dei giocatori (nodo figlio BodyDebugDraw).
## Senza tracker usa il simulatore (mouse).

const BG_COLOR := Color(0.12, 0.13, 0.17)

@onready var info_label: Label = $HUD/Info


func _process(_delta: float) -> void:
	queue_redraw()
	_update_info()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("body_record_toggle") and not event.is_echo():
		if BodyInput.is_recording():
			BodyInput.stop_recording()
		else:
			var stamp := Time.get_datetime_string_from_system().replace(":", "-")
			BodyInput.start_recording("res://recordings/session_%s.jsonl" % stamp)
		get_viewport().set_input_as_handled()


func _update_info() -> void:
	var ids: PackedStringArray = []
	for p in BodyInput.get_players():
		ids.append(String(p.id))
	info_label.text = "Sorgente: %s   |   tracker: %.0f fps   |   giocatori: %s%s" % [
		BodyInput.source_name(),
		BodyInput.tracker_fps,
		", ".join(ids) if not ids.is_empty() else "nessuno",
		"   |   ● REC" if BodyInput.is_recording() else "",
	]


func _draw() -> void:
	draw_rect(get_viewport_rect(), BG_COLOR)
