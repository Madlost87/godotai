extends Node2D
## Scena di calibrazione (SPEC §7). Da aprire sul proiettore a schermo intero.
##
## Vista MARKERS: sfondo bianco con 4 marker ArUco (DICT_4X4_50, id 0–3) agli angoli;
## ogni LAYOUT_INTERVAL secondi manda al tracker (canale di controllo) dove si trovano.
## Vista VERIFY: sfondo scuro, griglia e scheletri dei giocatori, per controllare che
## stiano sopra le persone reali. Si passa a VERIFY da soli quando il tracker ha finito.

enum View { MARKERS, VERIFY }

const ARUCO_FILE := "res://data/aruco_4x4_50.json"
## Lato del marker e margine dal bordo, in frazione del lato corto dello schermo.
## La stessa regola è usata nei test Python (tracker/tests/test_calibration.py).
const MARKER_SIZE := 0.22
const MARGIN := 0.04
const LAYOUT_INTERVAL := 0.5
const VERIFY_BG := Color(0.08, 0.09, 0.12)
const GRID_COLOR := Color(1, 1, 1, 0.15)

var view: View = View.MARKERS
var patterns: Dictionary = {}  # int -> PackedStringArray (6 righe di "0"/"1")
var layout: Dictionary = {}  # int -> PackedVector2Array: angoli in px (TL, TR, BR, BL)
var last_status: Dictionary = {}

var _since_layout: float = LAYOUT_INTERVAL

@onready var players_draw: Node2D = $Players
@onready var status_label: Label = $HUD/Status
@onready var help_label: Label = $HUD/Help


func _ready() -> void:
	patterns = load_patterns(ARUCO_FILE)
	# Schermo intero sul proiettore; "-- --windowed" sulla riga di comando lo evita.
	if DisplayServer.get_name() != "headless" and not OS.get_cmdline_user_args().has("--windowed"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	get_viewport().size_changed.connect(_on_size_changed)
	BodyInput.packet_received.connect(_on_packet)
	_on_size_changed()
	_set_view(View.MARKERS)


static func load_patterns(path: String) -> Dictionary:
	var out := {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Dictionary) or not (data.get("markers") is Dictionary):
		push_error("Calibrazione: file dei marker non valido: %s" % path)
		return out
	for key: String in data["markers"]:
		out[int(key)] = PackedStringArray(data["markers"][key])
	return out


## Angoli (TL, TR, BR, BL) in pixel dei marker 0 (alto sx), 1 (alto dx), 2 (basso dx), 3 (basso sx).
static func compute_layout(size: Vector2) -> Dictionary:
	var s := minf(size.x, size.y)
	var side := MARKER_SIZE * s
	var m := MARGIN * s
	var origins := {
		0: Vector2(m, m),
		1: Vector2(size.x - m - side, m),
		2: Vector2(size.x - m - side, size.y - m - side),
		3: Vector2(m, size.y - m - side),
	}
	var out := {}
	for id: int in origins:
		var o: Vector2 = origins[id]
		out[id] = PackedVector2Array([o, o + Vector2(side, 0), o + Vector2(side, side), o + Vector2(0, side)])
	return out


func layout_message() -> Dictionary:
	var size := get_viewport_rect().size
	var markers := {}
	for id: int in layout:
		var corners: Array = []
		for c: Vector2 in layout[id]:
			corners.append([c.x / size.x, c.y / size.y])
		markers[str(id)] = corners
	return {"type": "calibration_layout", "dictionary": "DICT_4X4_50", "screen": [size.x, size.y], "markers": markers}


func _process(delta: float) -> void:
	if view == View.MARKERS:
		_since_layout += delta
		if _since_layout >= LAYOUT_INTERVAL:
			_since_layout = 0.0
			BodyInput.send_control(layout_message())
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("calibration_toggle_view") and not event.is_echo():
		_set_view(View.VERIFY if view == View.MARKERS else View.MARKERS)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		get_tree().quit()


func _on_size_changed() -> void:
	layout = compute_layout(get_viewport_rect().size)
	_since_layout = LAYOUT_INTERVAL  # rimanda subito il nuovo layout


func _on_packet(packet: Dictionary) -> void:
	var cal: Variant = packet.get("calibration")
	if not (cal is Dictionary):
		return
	last_status = cal
	if cal.get("state") == "done" and view == View.MARKERS:
		_set_view(View.VERIFY)
	_update_labels()


func _set_view(v: View) -> void:
	view = v
	players_draw.visible = v == View.VERIFY
	var text_color := Color.BLACK if v == View.MARKERS else Color.WHITE
	status_label.add_theme_color_override("font_color", text_color)
	help_label.add_theme_color_override("font_color", text_color.lerp(Color(0.5, 0.5, 0.5), 0.4))
	_update_labels()


func status_text() -> String:
	if view == View.VERIFY:
		var s := "Verifica: lo scheletro deve cadere sopra la persona, come un'ombra."
		if last_status.get("state") == "done":
			s = "Calibrazione riuscita (errore %.2f%% dello schermo).\n" % (float(last_status.get("error", 0.0)) * 100.0) + s
		return s
	match last_status.get("state", ""):
		"":
			return "Calibrazione: avvia nel terminale\n./tracker.sh --calibrate --debug"
		"waiting_layout":
			return "Il tracker è pronto, sto inviando la posizione dei marker…"
		"searching":
			return "Cerco i marker… visti: %s di 4.\nLa camera deve inquadrare tutto lo schermo proiettato." % [
				str(last_status.get("found", [])).trim_prefix("[").trim_suffix("]")]
		"collecting":
			return "Marker trovati, non muovere la camera… %d%%" % int(float(last_status.get("progress", 0.0)) * 100.0)
		"failed":
			return "Calibrazione non riuscita: %s\nRiprovo…" % last_status.get("message", "")
		"done":
			return "Calibrazione riuscita."
	return str(last_status)


func _update_labels() -> void:
	status_label.text = status_text()
	help_label.text = "C: marker / verifica   |   Esc: esci"


func _draw() -> void:
	var rect := get_viewport_rect()
	if view == View.MARKERS:
		draw_rect(rect, Color.WHITE)
		for id: int in layout:
			_draw_marker(id)
	else:
		draw_rect(rect, VERIFY_BG)
		for i in range(1, 10):
			var x := rect.size.x * i / 10.0
			var y := rect.size.y * i / 10.0
			draw_line(Vector2(x, 0), Vector2(x, rect.size.y), GRID_COLOR, 1.0)
			draw_line(Vector2(0, y), Vector2(rect.size.x, y), GRID_COLOR, 1.0)
		for id: int in layout:  # dove erano i marker: utile per vedere se la proiezione è spostata
			var c: PackedVector2Array = layout[id]
			draw_polyline(PackedVector2Array([c[0], c[1], c[2], c[3], c[0]]), GRID_COLOR * 2.0, 2.0)


func _draw_marker(id: int) -> void:
	if not patterns.has(id):
		return
	var corners: PackedVector2Array = layout[id]
	var cell := (corners[1].x - corners[0].x) / 6.0
	var rows: PackedStringArray = patterns[id]
	for r in rows.size():
		for c in rows[r].length():
			if rows[r][c] == "0":
				draw_rect(Rect2(corners[0] + Vector2(c, r) * cell, Vector2(cell, cell)), Color.BLACK)
