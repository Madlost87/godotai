class_name TrackingQuality
extends RefCounted
## Quanto bene il sensore vede chi gioca, negli ultimi `window` secondi, e un consiglio
## da mostrare (docs/SPEC.md §10.2): mani spesso perse → cursore che sparisce e scatta;
## gomiti mai visti → persona troppo vicina alla camera (la mano è meno stabile).
## Uso: sample(giocatore_o_null, BodyInput.now()) a ogni frame, poi hint().
## I consigli sui gomiti valgono solo con uno scheletro (capacità "pose").

const HINT_HANDS := "Mani poco visibili: più luce, mani davanti al corpo, un passo indietro dalla camera"
const HINT_TOO_CLOSE := "Troppo vicino alla camera: fai un passo indietro finché si vedono i gomiti"

var window: float = 4.0
## Sotto questa frazione di tempo con una mano visibile, compare il consiglio.
var min_hands: float = 0.7
## Sotto questa frazione (tra i momenti con una mano) senza gomiti: troppo vicino.
var min_elbows: float = 0.3
var uses_pose: bool = true

## [t, persona, mano, gomito]
var _samples: Array[Array] = []


func sample(p: PlayerState, t: float) -> void:
	var person := p != null
	var hand := person and (BodyMetrics.has_hand(p, "l") or BodyMetrics.has_hand(p, "r"))
	var elbow := person and (p.has_point(&"elbow_l") or p.has_point(&"elbow_r"))
	_samples.append([t, person, hand, elbow])
	while not _samples.is_empty() and t - float(_samples[0][0]) > window:
		_samples.pop_front()


## Frazione del tempo con una persona / con una mano (tra i momenti con una persona) /
## con un gomito (tra i momenti con una mano).
func stats() -> Dictionary:
	var n_person := 0
	var n_hand := 0
	var n_elbow := 0
	for s in _samples:
		if s[1]:
			n_person += 1
			if s[2]:
				n_hand += 1
				if s[3]:
					n_elbow += 1
	return {
		"person": float(n_person) / maxi(_samples.size(), 1),
		"hands": float(n_hand) / maxi(n_person, 1),
		"elbows": float(n_elbow) / maxi(n_hand, 1),
	}


## Consiglio da mostrare ("" se va tutto bene o se si è osservato troppo poco).
func hint() -> String:
	if _samples.size() < 2 or float(_samples[-1][0]) - float(_samples[0][0]) < window * 0.75:
		return ""
	var s := stats()
	if s["person"] < 0.5:
		return ""
	if s["hands"] < min_hands:
		return HINT_HANDS
	if uses_pose and s["elbows"] < min_elbows:
		return HINT_TOO_CLOSE
	return ""
