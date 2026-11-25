extends Node2D
## Menu dei giochi (scena principale). Trova da solo i giochi in games/ (GameRegistry)
## e li mostra come schede. Si sceglie col corpo (mano ferma su una scheda: DwellTarget)
## o con la tastiera (ui_left / ui_right, ui_accept o game_start). game_exit chiude.
## Ogni scheda segnala le capacità che il sensore collegato non ha.

const BG := Color(0.07, 0.08, 0.11)
const CARD_BG := Color(0.13, 0.15, 0.2)
const CARD_FOCUS := Color(0.35, 0.75, 0.95)
const TEXT := Color(0.92, 0.95, 1.0)
const TEXT_DIM := Color(0.65, 0.7, 0.78)
const WARN := Color(1.0, 0.65, 0.35)
const MAX_COLUMNS := 4

var games: Array[GameManifest] = []
var focus: int = 0
var cards: Array[DwellTarget] = []

@onready var cards_root: Node2D = $Cards
@onready var status_label: Label = $HUD/Status


func _ready() -> void:
	BodyInput.set_session({"max_players": 1, "game": "launcher"})
	games = GameRegistry.list_games()
	for m in games:
		var t := DwellTarget.new()
		t.name = "Card_" + m.id
		t.selected.connect(launch.bind(m))
		cards_root.add_child(t)
		cards.append(t)
	get_viewport().size_changed.connect(_layout)
	_layout()


func _exit_tree() -> void:
	BodyInput.clear_session()


func launch(m: GameManifest) -> void:
	get_tree().change_scene_to_file.call_deferred(m.scene_path)


func _unhandled_input(event: InputEvent) -> void:
	if games.is_empty():
		return
	if event.is_action_pressed(&"ui_right"):
		focus = (focus + 1) % games.size()
	elif event.is_action_pressed(&"ui_left"):
		focus = (focus - 1 + games.size()) % games.size()
	elif event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"game_start"):
		launch(games[focus])
	elif event.is_action_pressed(&"game_exit"):
		get_tree().quit()
	else:
		return
	get_viewport().set_input_as_handled()


func card_rect(i: int) -> Rect2:
	var vp := get_viewport_rect().size
	var cols := mini(maxi(games.size(), 1), MAX_COLUMNS)
	var rows := ceili(float(games.size()) / cols)
	var gap := vp.y * 0.04
	var w := minf((vp.x * 0.9 - gap * (cols - 1)) / cols, vp.y * 0.55)
	var h := minf(w * 0.8, (vp.y * 0.62 - gap * (rows - 1)) / maxi(rows, 1))
	var total := Vector2(cols * w + (cols - 1) * gap, rows * h + (rows - 1) * gap)
	var origin := Vector2((vp.x - total.x) / 2.0, vp.y * 0.22 + (vp.y * 0.62 - total.y) / 2.0)
	@warning_ignore("integer_division")
	return Rect2(origin + Vector2((i % cols) * (w + gap), (i / cols) * (h + gap)), Vector2(w, h))


func _layout() -> void:
	for i in cards.size():
		var r := card_rect(i)
		cards[i].position = r.get_center()
		cards[i].set_box_size(r.size)


func _process(_delta: float) -> void:
	for i in cards.size():
		if cards[i].is_hovered():
			focus = i
	var caps := ", ".join(BodyInput.capabilities) if not BodyInput.capabilities.is_empty() else "nessuna"
	status_label.text = "Sensore: %s  ·  %.0f fps  ·  capacità: %s" % [BodyInput.source_name(), BodyInput.tracker_fps, caps]
	queue_redraw()


func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), BG)
	var font := ThemeDB.fallback_font
	var fs := int(vp.y * 0.075)
	draw_string(font, Vector2(0, vp.y * 0.13), "GIOCHI", HORIZONTAL_ALIGNMENT_CENTER, vp.x, fs, TEXT)
	draw_string(font, Vector2(0, vp.y * 0.18), "Tieni la mano su un gioco per sceglierlo  ·  frecce + Invio  ·  Esc esce",
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(vp.y * 0.03), TEXT_DIM)
	if games.is_empty():
		draw_string(font, Vector2(0, vp.y * 0.5), "Nessun gioco. Creane uno con ./new_game.sh <id> \"Titolo\"",
			HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(vp.y * 0.035), WARN)
		return
	for i in games.size():
		_draw_card(i, font)


func _draw_card(i: int, font: Font) -> void:
	var m := games[i]
	var r := card_rect(i)
	var pad := r.size.x * 0.07
	draw_rect(r, CARD_BG)
	draw_rect(r, CARD_FOCUS if i == focus else Color(1, 1, 1, 0.15), false, 4.0 if i == focus else 2.0)
	var y := r.position.y + pad
	var title_fs := int(r.size.y * 0.13)
	y += title_fs
	draw_string(font, Vector2(r.position.x + pad, y), m.title, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - pad * 2.0, title_fs, TEXT)
	var body_fs := int(r.size.y * 0.065)
	y += body_fs * 1.6
	draw_multiline_string(font, Vector2(r.position.x + pad, y), m.description, HORIZONTAL_ALIGNMENT_LEFT,
		r.size.x - pad * 2.0, body_fs, 5, TEXT_DIM)
	var players := "%d giocatore" % m.max_players if m.max_players == 1 else "%d–%d giocatori" % [m.min_players, m.max_players]
	var bottom := r.end.y - pad
	draw_string(font, Vector2(r.position.x + pad, bottom), players, HORIZONTAL_ALIGNMENT_LEFT, -1, body_fs, TEXT_DIM)
	var missing := m.missing_capabilities(BodyInput.capabilities)
	if not missing.is_empty() and not BodyInput.capabilities.is_empty():
		draw_string(font, Vector2(r.position.x + pad, bottom - body_fs * 1.4), "Il sensore non ha: " + ", ".join(missing),
			HORIZONTAL_ALIGNMENT_LEFT, r.size.x - pad * 2.0, body_fs, WARN)
