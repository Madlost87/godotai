class_name BodyMetrics
extends RefCounted
## Valori derivati dal corpo (SPEC §6.3, F15), calcolati da un PlayerState.
## Funzioni statiche, senza stato. Se mancano i punti necessari restituiscono NAN
## (controlla con is_nan) oppure false nelle funzioni has_*.
## I rapporti sono normalizzati sulla larghezza delle spalle, così non dipendono
## da quanto la persona è lontana dalla camera. Per crouch/jump serve uno stato:
## vedi BodyMetrics.Baseline.

## Polso più in alto della spalla di questa frazione di larghezza spalle = braccio alzato "pieno".
const ARM_RAISED_FULL := 1.0


static func has_shoulders(p: PlayerState) -> bool:
	return p.has_point(&"shoulder_l") and p.has_point(&"shoulder_r")


static func shoulder_width(p: PlayerState) -> float:
	if not has_shoulders(p):
		return NAN
	return p.point(&"shoulder_l").distance_to(p.point(&"shoulder_r"))


## Centro delle spalle (dal tracker, o calcolato). Vector2.ZERO se mancano le spalle.
static func shoulder_center(p: PlayerState) -> Vector2:
	if p.has_point(&"shoulder_c"):
		return p.point(&"shoulder_c")
	if has_shoulders(p):
		return (p.point(&"shoulder_l") + p.point(&"shoulder_r")) * 0.5
	return Vector2.ZERO


static func has_hand(p: PlayerState, side: String) -> bool:
	return p.has_point(StringName("wrist_" + side)) or p.has_point(StringName("hand_%s.wrist" % side))


## Centro della mano: tra polso e indice se ci sono entrambi, altrimenti il polso.
static func hand_center(p: PlayerState, side: String) -> Vector2:
	var wrist := StringName("wrist_" + side)
	var index := StringName("index_" + side)
	if p.has_point(wrist) and p.has_point(index):
		return (p.point(wrist) + p.point(index)) * 0.5
	if p.has_point(wrist):
		return p.point(wrist)
	var hw := StringName("hand_%s.wrist" % side)
	return p.point(hw) if p.has_point(hw) else Vector2.ZERO


## Punti che possono "toccare" gli oggetti di gioco, per nome → posizione in pixel.
## Se il sensore manda effettori espliciti (es. tocchi di un LiDAR) usa quelli
## ("e0", "e1"...); altrimenti le mani ("hand_l", "hand_r"). I giochi che usano gli
## effettori funzionano con qualsiasi sensore che abbia la capacità "effectors".
static func effectors(p: PlayerState) -> Dictionary:
	var out := {}
	for n: StringName in p.point_names():
		var s := String(n)
		if s.begins_with("effector."):
			out[s.trim_prefix("effector.")] = p.point(n)
	if out.is_empty():
		for side in ["l", "r"]:
			if has_hand(p, side):
				out["hand_" + side] = hand_center(p, side)
	return out


## Inclinazione del busto in radianti: 0 = dritto, positivo = verso destra sullo schermo.
## Usa spalle → anche se ci sono, altrimenti la linea delle spalle.
static func torso_lean(p: PlayerState) -> float:
	if p.has_point(&"hip_c") and (p.has_point(&"shoulder_c") or has_shoulders(p)):
		var d := shoulder_center(p) - p.point(&"hip_c")
		return atan2(d.x, -d.y)
	if not has_shoulders(p):
		return NAN
	var a := p.point(&"shoulder_l")
	var b := p.point(&"shoulder_r")
	if a.x > b.x:
		var t := a
		a = b
		b = t
	var d2 := b - a
	return atan2(d2.y, d2.x)


## 0 = polso all'altezza della spalla o sotto, 1 = polso ben sopra la spalla (sopra la testa).
static func arm_raised(p: PlayerState, side: String) -> float:
	var shoulder := StringName("shoulder_" + side)
	var sw := shoulder_width(p)
	if not p.has_point(shoulder) or not has_hand(p, side) or is_nan(sw) or sw <= 0.0:
		return NAN
	var d := (p.point(shoulder).y - hand_center(p, side).y) / sw
	return clampf(d / ARM_RAISED_FULL, 0.0, 1.0)


## Distanza tra le mani / larghezza delle spalle (~1 braccia giù, 3+ braccia aperte).
static func arms_spread(p: PlayerState) -> float:
	var sw := shoulder_width(p)
	if not has_hand(p, "l") or not has_hand(p, "r") or is_nan(sw) or sw <= 0.0:
		return NAN
	return hand_center(p, "l").distance_to(hand_center(p, "r")) / sw


## Angolo spalla → mano in radianti (convenzione Godot: 0 = destra, positivo = verso il basso).
static func arm_angle(p: PlayerState, side: String) -> float:
	var shoulder := StringName("shoulder_" + side)
	if not p.has_point(shoulder) or not has_hand(p, side):
		return NAN
	return (hand_center(p, side) - p.point(shoulder)).angle()


## Spostamento verticale rispetto alla posizione di riposo, per accovacciarsi e saltare.
## Uno per giocatore: chiama update() a ogni frame.
class Baseline:
	## Secondi in cui il riposo "insegue" la posizione attuale (più alto = più lento).
	var time_constant: float = 3.0
	var rest_y: float = NAN
	## Ultimo valore: > 0 sopra il riposo (salto), < 0 sotto (accovacciato), in larghezze spalle.
	var offset: float = 0.0

	func update(p: PlayerState, delta: float) -> float:
		var sw := BodyMetrics.shoulder_width(p)
		if is_nan(sw) or sw <= 0.0:
			return offset
		var y := BodyMetrics.shoulder_center(p).y
		if is_nan(rest_y):
			rest_y = y
		offset = (rest_y - y) / sw
		rest_y = lerpf(rest_y, y, 1.0 - exp(-delta / time_constant))
		return offset

	func crouch() -> float:
		return maxf(-offset, 0.0)

	func jump() -> float:
		return maxf(offset, 0.0)
