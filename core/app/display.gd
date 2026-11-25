extends Node
## Autoload "Display": schermo intero e scelta del monitor, uguali per tutti i giochi.
## Di default il gioco è a schermo intero (project.godot). Riga di comando, dopo "--":
##   --windowed     in finestra (es. per sviluppare)
##   --screen=N     sul monitor N (es. il proiettore: 1)
## Azione toggle_fullscreen (F11): passa da finestra a schermo intero e viceversa.
## Le scene disegnano in proporzione alla viewport (stretch "canvas_items" + "expand"),
## quindi si adattano a qualsiasi risoluzione e rapporto (16:9, 16:10, 4:3...).


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	# All'avvio la finestra non è ancora pronta: i cambi di modalità si applicano dopo il
	# primo frame, altrimenti vengono sovrascritti dalle impostazioni del progetto.
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--screen="):
			move_to_screen(int(a.get_slice("=", 1)))
	# In finestra se richiesto dopo "--", con l'opzione di Godot (-w / --windowed) o
	# registrando un video (--write-movie): lì le dimensioni devono restare fisse.
	var engine_args := OS.get_cmdline_args()
	var windowed := args.has("--windowed") or engine_args.has("--windowed") or engine_args.has("-w") \
		or engine_args.has("--write-movie")
	set_fullscreen(not windowed)


func is_fullscreen() -> bool:
	var m := DisplayServer.window_get_mode()
	return m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


func set_fullscreen(on: bool) -> void:
	if DisplayServer.get_name() == "headless" or on == is_fullscreen():
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)


## Sposta il gioco sul monitor n (0 = principale), restando a schermo intero se lo era.
func move_to_screen(n: int) -> void:
	if DisplayServer.get_name() == "headless" or n < 0 or n >= DisplayServer.get_screen_count():
		push_warning("Display: monitor %d non disponibile (%d collegati)" % [n, DisplayServer.get_screen_count()])
		return
	var was_full := is_fullscreen()
	if was_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_current_screen(n)
	if was_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_fullscreen") and not event.is_echo():
		set_fullscreen(not is_fullscreen())
		get_viewport().set_input_as_handled()
