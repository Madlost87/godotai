extends SceneTree
func _initialize() -> void:
	var main: Node = load("res://examples/counter/counter.tscn").instantiate()
	root.add_child(main)
	await process_frame
	for i in 3:
		var ev := InputEventAction.new(); ev.action = "increment_counter"; ev.pressed = true
		Input.parse_input_event(ev); await process_frame
		var up := InputEventAction.new(); up.action = "increment_counter"; up.pressed = false
		Input.parse_input_event(up); await process_frame
	print("COUNTER=", main.counter, " LABEL=", main.get_node("HUD/CounterLabel").text)
	var p: Node2D = main.get_node("Player"); var x0 := p.position.x
	Input.action_press("ui_right")
	for i in 180: await physics_frame
	Input.action_release("ui_right")
	print("PLAYER_X from ", x0, " to ", p.position.x, " (obstacle left edge 560, expect ~536)")
	quit(0 if main.counter == 3 and p.position.x > x0 and p.position.x < 560 else 1)
