extends BodyGame
## Nuovo gioco — creato da games/_template con ./new_game.sh. Modifica pure tutto.
##
## Cosa c'è già pronto:
## - BodyGame (classe base): legge game.json, chiede al tracker giocatori e capacità,
##   Esc torna al menu. Inizializza in _game_ready(), non in _ready().
## - BodyColliders: aree di collisione sugli effettori (mani con la camera, punti di
##   contatto con un LiDAR...) sul layer fisico "body". Gli oggetti di gioco che devono
##   sentirle mettono BodyColliders.BODY_LAYER nella collision_mask.
## - BodyDebugDraw: scheletri in trasparenza, per vedere cosa vede il sensore.
## - Un bersaglio (Area2D) che, toccato, dà un punto e si sposta.
##
## Altri pezzi del framework (core/): BodyMetrics (braccio alzato, busto inclinato...),
## GestureController (gesto → azione dell'Input Map), DwellTarget (selezione tenendo
## ferma la mano). Vedi docs/GUIDA_NUOVO_GIOCO.md.

const BG := Color(0.08, 0.1, 0.14)
const TARGET_COLOR := Color(0.95, 0.7, 0.35)

## Raggio del bersaglio in frazione dell'altezza dello schermo.
@export var target_radius_ratio: float = 0.08

var score: int = 0
var _rng := RandomNumberGenerator.new()
var _shape := CircleShape2D.new()

@onready var target: Area2D = $Target
@onready var score_label: Label = $HUD/Score


func _game_ready() -> void:
	_rng.randomize()
	var cs := CollisionShape2D.new()
	cs.shape = _shape
	target.add_child(cs)
	target.collision_layer = 0
	target.collision_mask = BodyColliders.BODY_LAYER
	target.area_entered.connect(_on_target_touched)
	move_target()


## Sposta il bersaglio (posizione casuale se non indicata).
func move_target(pos: Vector2 = Vector2(-1, -1)) -> void:
	var vp := get_viewport_rect().size
	var r := vp.y * target_radius_ratio
	_shape.radius = r
	if pos.x < 0.0:
		pos = Vector2(_rng.randf_range(r, vp.x - r), _rng.randf_range(r * 2.0, vp.y - r))
	target.position = pos


func _on_target_touched(area: Area2D) -> void:
	if not BodyColliders.is_body_part(area):
		return
	score += 1
	move_target()


func _process(_delta: float) -> void:
	score_label.text = "Punti  %d" % score
	queue_redraw()


func _draw() -> void:
	draw_rect(get_viewport_rect(), BG)
	draw_circle(target.position, _shape.radius, Color(TARGET_COLOR, 0.35))
	draw_arc(target.position, _shape.radius, 0.0, TAU, 48, TARGET_COLOR, 5.0, true)
