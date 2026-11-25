extends SceneTree
## La scena demo disegna i giocatori ricevuti da BodyInput senza errori.

func _initialize() -> void:
	await process_frame
	var bi: Node = root.get_node("BodyInput")
	bi.simulator_fallback = false
	var demo: Node = load("res://tools/body_demo/body_demo.tscn").instantiate()
	root.add_child(demo)
	var label: Label = demo.get_node("HUD/Info")
	var ok := true
	for i in 10:
		bi.ingest_packet({"v": 1, "fps": 30.0, "players": [{
			"id": "red",
			"marker": {"x": 0.4, "y": 0.5},
			"pose": {"shoulder_r": [0.3, 0.3, 1.0], "elbow_r": [0.35, 0.4, 1.0], "wrist_r": [0.4, 0.5, 1.0], "nose": [0.3, 0.15, 1.0]},
			"hands": {"r": {"wrist": [0.4, 0.5, 1.0], "open": 0.1}},
			"face": {"x": 0.3, "y": 0.15, "yaw": 20.0},
		}, {"id": "anon0", "marker": {"x": 0.8, "y": 0.5}}]})
		await process_frame
	print("INFO=", label.text)
	ok = label.text.contains("red") and label.text.contains("anon0") and label.text.contains("UDP")
	quit(0 if ok else 1)
