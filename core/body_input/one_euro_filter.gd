class_name OneEuroFilter
extends RefCounted
## Filtro One Euro (Casiez et al., 2012) per Vector2.
## Da fermo taglia il tremolio (cutoff basso), nei movimenti veloci alza il cutoff
## e resta reattivo. min_cutoff in Hz; beta = quanto la velocità alza il cutoff.

var min_cutoff: float
var beta: float
var d_cutoff: float = 1.0

var _initialized: bool = false
var _x_prev: Vector2 = Vector2.ZERO
var _dx_prev: Vector2 = Vector2.ZERO
var _t_prev: float = 0.0


func _init(p_min_cutoff: float = 1.0, p_beta: float = 10.0) -> void:
	min_cutoff = p_min_cutoff
	beta = p_beta


func reset() -> void:
	_initialized = false
	_dx_prev = Vector2.ZERO


func filter(x: Vector2, t: float) -> Vector2:
	if not _initialized:
		_initialized = true
		_x_prev = x
		_t_prev = t
		return x
	var dt := maxf(t - _t_prev, 1.0 / 120.0)
	_t_prev = t
	var dx := (x - _x_prev) / dt
	_dx_prev = _dx_prev.lerp(dx, _alpha(dt, d_cutoff))
	var cutoff := min_cutoff + beta * _dx_prev.length()
	_x_prev = _x_prev.lerp(x, _alpha(dt, cutoff))
	return _x_prev


static func _alpha(dt: float, cutoff: float) -> float:
	var tau := 1.0 / (TAU * cutoff)
	return 1.0 / (1.0 + tau / dt)
