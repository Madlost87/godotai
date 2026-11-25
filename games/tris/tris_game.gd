extends BodyGame
## Tris giocato con la mano destra, che segna a turno X e O (da soli o in due che si
## alternano). Si tiene la mano ferma su una casella libera per dwell_time secondi: compare
## il simbolo del turno. La mano sinistra è ignorata (niente segni involontari).
## Con un sensore senza destra/sinistra (nessuna capacità "pose", es. un LiDAR) vale
## qualsiasi effettore. La griglia sta in alto: le mani a riposo non la toccano.

enum State { PLAYING, ENDED }

const EMPTY := 0
const X := 1
const O := 2
const LINES: Array = [[0, 1, 2], [3, 4, 5], [6, 7, 8], [0, 3, 6], [1, 4, 7], [2, 5, 8], [0, 4, 8], [2, 4, 6]]

const BG := Color(0.07, 0.09, 0.12)
const GRID_COLOR := Color(0.8, 0.85, 0.95, 0.55)
const X_COLOR := Color(0.35, 0.9, 0.75)
const O_COLOR := Color(0.95, 0.6, 0.85)
const TEXT_COLOR := Color(0.92, 0.95, 1.0)

## Secondi di mano ferma su una casella per segnarla.
@export var dwell_time: float = 1.2
## Effettore che gioca (con la pose): la mano destra.
@export var play_part: String = "hand_r"
## Lato della griglia e distanza dall'alto, in frazione dell'altezza dello schermo.
@export var grid_ratio: float = 0.62
@export var grid_top_ratio: float = 0.16

var board: Array[int] = []
var turn: int = X
var state: State = State.PLAYING
var winner: int = EMPTY
var win_line: Array = []
var cells: Array[DwellTarget] = []
var new_game_button: DwellTarget

@onready var cells_root: Node2D = $Cells
@onready var colliders: BodyColliders = $BodyColliders
@onready var status_label: Label = $HUD/Status


func _game_ready() -> void:
	for i in 9:
		var c := DwellTarget.new()
		c.name = "Cell%d" % i
		c.dwell_time = dwell_time
		c.exclusive_group = &"tris_cells"  # a cavallo di due caselle conta solo la più vicina
		c.selected.connect(_on_cell_selected.bind(i))
		cells_root.add_child(c)
		cells.append(c)
	new_game_button = DwellTarget.new()
	new_game_button.name = "NewGame"
	new_game_button.dwell_time = dwell_time
	new_game_button.selected.connect(new_game)
	cells_root.add_child(new_game_button)
	BodyInput.capabilities_changed.connect(func(_c: PackedStringArray) -> void: _apply_hand_filter())
	get_viewport().size_changed.connect(_layout)
	_apply_hand_filter()
	_layout()
	new_game()


func new_game() -> void:
	board.clear()
	board.resize(9)
	board.fill(EMPTY)
	turn = X
	state = State.PLAYING
	winner = EMPTY
	win_line = []
	_reset_targets()
	_refresh()


## Segna la casella i per il giocatore di turno. false se non si può.
func place(i: int) -> bool:
	if state != State.PLAYING or i < 0 or i > 8 or board[i] != EMPTY:
		return false
	board[i] = turn
	var result := check_winner(board)
	if result["winner"] != EMPTY:
		winner = result["winner"]
		win_line = result["line"]
		state = State.ENDED
	elif not board.has(EMPTY):
		state = State.ENDED  # pareggio
	else:
		turn = O if turn == X else X
	_reset_targets()  # l'avanzamento non passa da un turno all'altro
	_refresh()
	return true


static func check_winner(b: Array) -> Dictionary:
	for line: Array in LINES:
		var v: int = b[line[0]]
		if v != EMPTY and b[line[1]] == v and b[line[2]] == v:
			return {"winner": v, "line": line}
	return {"winner": EMPTY, "line": []}


static func symbol(player: int) -> String:
	return "X" if player == X else ("O" if player == O else "")


func grid_rect() -> Rect2:
	var vp := get_viewport_rect().size
	var side := vp.y * grid_ratio
	return Rect2(Vector2((vp.x - side) / 2.0, vp.y * grid_top_ratio), Vector2(side, side))


func cell_rect(i: int) -> Rect2:
	var g := grid_rect()
	var s := g.size.x / 3.0
	@warning_ignore("integer_division")
	return Rect2(g.position + Vector2(i % 3, i / 3) * s, Vector2(s, s))


func button_rect() -> Rect2:
	var vp := get_viewport_rect().size
	var g := grid_rect()
	var size := Vector2(vp.y * 0.3, vp.y * 0.16)
	var gap := vp.y * 0.05
	if vp.x - g.end.x >= size.x + gap * 1.5:  # c'è spazio a destra della griglia
		return Rect2(Vector2(g.end.x + gap, g.get_center().y - size.y / 2.0), size)
	# schermo stretto (es. 4:3): sotto la griglia, mai sopra le caselle
	size = Vector2(minf(size.x, vp.x * 0.6), minf(size.y, vp.y - g.end.y - gap * 0.6))
	return Rect2(Vector2((vp.x - size.x) / 2.0, g.end.y + gap * 0.3), size)


func _apply_hand_filter() -> void:
	var f := PackedStringArray([play_part]) if BodyInput.has_capability("pose") else PackedStringArray()
	colliders.part_filter = f
	for c in cells:
		c.accept_parts = f
	new_game_button.accept_parts = f


func _layout() -> void:
	for i in 9:
		var r := cell_rect(i)
		cells[i].position = r.get_center()
		cells[i].set_box_size(r.size * 0.9)
	var b := button_rect()
	new_game_button.position = b.get_center()
	new_game_button.set_box_size(b.size)


func _reset_targets() -> void:
	for c in cells:
		c.reset()
	new_game_button.reset()


func _refresh() -> void:
	var col := X_COLOR if turn == X else O_COLOR
	for i in 9:
		cells[i].enabled = state == State.PLAYING and board[i] == EMPTY
		cells[i].ring_color = col
	new_game_button.enabled = state == State.ENDED
	match state:
		State.PLAYING:
			status_label.text = "Turno: %s" % symbol(turn)
			status_label.add_theme_color_override("font_color", col)
		State.ENDED:
			status_label.text = ("Vince %s!" % symbol(winner)) if winner != EMPTY else "Pareggio!"
			status_label.add_theme_color_override("font_color", TEXT_COLOR)


func _on_cell_selected(i: int) -> void:
	place(i)


func _process(_delta: float) -> void:
	if state == State.ENDED and Input.is_action_just_pressed(&"game_start"):
		new_game()
	queue_redraw()


func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), BG)
	var g := grid_rect()
	var s := g.size.x / 3.0
	var w := maxf(vp.y * 0.008, 2.0)
	# caselle puntate dalla mano di turno
	for i in 9:
		if cells[i].enabled and cells[i].is_hovered():
			draw_rect(cell_rect(i).grow(-w), Color(X_COLOR if turn == X else O_COLOR, 0.15))
	for k in [1, 2]:
		draw_line(g.position + Vector2(s * k, 0), g.position + Vector2(s * k, g.size.y), GRID_COLOR, w, true)
		draw_line(g.position + Vector2(0, s * k), g.position + Vector2(g.size.x, s * k), GRID_COLOR, w, true)
	for i in 9:
		_draw_symbol(board[i], cell_rect(i), w * 1.6)
	if not win_line.is_empty():
		var a := cell_rect(win_line[0]).get_center()
		var b := cell_rect(win_line[2]).get_center()
		var d := (b - a).normalized() * s * 0.35
		draw_line(a - d, b + d, Color(TEXT_COLOR, 0.9), w * 2.0, true)
	if state == State.ENDED:
		var r := button_rect()
		draw_rect(r, Color(0.15, 0.18, 0.24))
		draw_rect(r, Color(TEXT_COLOR, 0.6), false, w * 0.6)
		var fs := int(r.size.y * 0.24)
		draw_string(ThemeDB.fallback_font, Vector2(r.position.x, r.get_center().y + fs * 0.35), "Nuova partita",
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, TEXT_COLOR)


func _draw_symbol(player: int, r: Rect2, width: float) -> void:
	var c := r.get_center()
	var h := r.size.x * 0.28
	if player == X:
		draw_line(c + Vector2(-h, -h), c + Vector2(h, h), X_COLOR, width, true)
		draw_line(c + Vector2(h, -h), c + Vector2(-h, h), X_COLOR, width, true)
	elif player == O:
		draw_arc(c, h * 1.1, 0.0, TAU, 48, O_COLOR, width, true)
