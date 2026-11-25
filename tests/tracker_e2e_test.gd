extends SceneTree
## End-to-end: il tracker Python (modalità sintetica, senza camera) manda pacchetti
## UDP e BodyInput li riceve con id stabili. Saltato se l'ambiente Python manca.

const PORT := 42425
const CONTROL_PORT := 42428


func _initialize() -> void:
	await process_frame
	var script_path := ProjectSettings.globalize_path("res://tracker.sh")
	if not FileAccess.file_exists(ProjectSettings.globalize_path("res://tracker/.venv/bin/python")):
		print("SALTATO: tracker/.venv non presente")
		quit(0)
		return
	var bi: Node = root.get_node("BodyInput")
	bi.simulator_fallback = false
	bi.listen(PORT)
	var pid := OS.create_process(script_path, ["--synthetic", "2", "--port", str(PORT), "--control-port", str(CONTROL_PORT), "--max-frames", "300"])
	var seen := {}
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 15000:
		await process_frame
		for p in bi.get_players():
			seen[p.id] = p.has_point(&"wrist_l") and p.has_point(&"shoulder_c")
		if seen.size() >= 2 and Time.get_ticks_msec() - start > 1500:
			break
	print("GIOCATORI=", seen, "  fps tracker=", bi.tracker_fps)
	var ok: bool = seen.get(&"p1", false) and seen.get(&"p2", false) and seen.size() == 2
	# Il gioco chiede 1 giocatore: il tracker deve smettere di mandare p2.
	bi.control_port = CONTROL_PORT
	bi.set_session({"max_players": 1})
	var only_p1 := false
	start = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 5000:
		await process_frame
		var ids: Array = bi.get_players().map(func(p: PlayerState) -> StringName: return p.id)
		if ids == [&"p1"]:
			only_p1 = true
			break
	print("SESSIONE 1 giocatore → solo p1: ", only_p1)
	bi.clear_session()
	OS.kill(pid)
	ok = ok and only_p1
	quit(0 if ok else 1)
