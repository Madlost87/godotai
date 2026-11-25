class_name GameManifest
extends RefCounted
## Descrizione di un gioco, letta da games/<id>/game.json. Esempio:
## {
##   "id": "bubbles", "title": "Bolle", "description": "Scoppia le bolle con le mani.",
##   "scene": "bubbles.tscn", "players": {"min": 1, "max": 1},
##   "requires": ["effectors"], "optional": ["pose"],
##   "controls": "Tocca le bolle. Alza un braccio per iniziare."
## }
## "requires" / "optional" sono capacità del sensore (BodyInput.capabilities):
## "pose", "hands", "face", "markers", "effectors".

const KNOWN_CAPABILITIES: PackedStringArray = ["effectors", "face", "hands", "markers", "pose"]

var id: String = ""
var title: String = ""
var description: String = ""
var controls: String = ""
var folder: String = ""
var scene_path: String = ""
var min_players: int = 1
var max_players: int = 1
var requires: PackedStringArray = []
var optional: PackedStringArray = []
## Problemi trovati leggendo il file (vuoto = valido).
var errors: PackedStringArray = []


static func load_from(game_folder: String) -> GameManifest:
	var m := GameManifest.new()
	m.folder = game_folder.trim_suffix("/")
	var path := m.folder + "/game.json"
	if not FileAccess.file_exists(path):
		m.errors.append("manca %s" % path)
		return m
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Dictionary):
		m.errors.append("%s non è un oggetto JSON valido" % path)
		return m
	m.id = str(data.get("id", ""))
	m.title = str(data.get("title", m.id))
	m.description = str(data.get("description", ""))
	m.controls = str(data.get("controls", ""))
	m.scene_path = m.folder + "/" + str(data.get("scene", ""))
	var players: Variant = data.get("players", {})
	if players is Dictionary:
		m.min_players = int(players.get("min", 1))
		m.max_players = int(players.get("max", m.min_players))
	m.requires = PackedStringArray(data.get("requires", []))
	m.optional = PackedStringArray(data.get("optional", []))
	m._validate()
	return m


func is_valid() -> bool:
	return errors.is_empty()


## Richiesta per il tracker (BodyInput.set_session).
func session() -> Dictionary:
	return {"max_players": max_players, "requires": Array(requires), "game": id}


## Capacità richieste che il sensore collegato non ha.
func missing_capabilities(available: PackedStringArray) -> PackedStringArray:
	var out: PackedStringArray = []
	for c in requires:
		if not available.has(c):
			out.append(c)
	return out


func _validate() -> void:
	if id.is_empty() or not id.is_valid_ascii_identifier() or id != id.to_lower():
		errors.append("id non valido: '%s' (minuscole, cifre, _)" % id)
	elif id != folder.get_file():
		errors.append("id '%s' diverso dal nome della cartella '%s'" % [id, folder.get_file()])
	if not ResourceLoader.exists(scene_path):
		errors.append("scena non trovata: %s" % scene_path)
	if min_players < 1 or max_players < min_players or max_players > 8:
		errors.append("players non valido: min %d, max %d" % [min_players, max_players])
	for c in requires + optional:
		if not KNOWN_CAPABILITIES.has(c):
			errors.append("capacità sconosciuta: '%s' (note: %s)" % [c, ", ".join(KNOWN_CAPABILITIES)])
