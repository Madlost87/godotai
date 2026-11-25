class_name GameRegistry
extends RefCounted
## Trova i giochi: ogni cartella games/<id>/ con un game.json è un gioco.
## Le cartelle che iniziano con "_" o "." (es. games/_template) vengono ignorate.
## Nessun elenco da aggiornare: un gioco nuovo compare nel menu da solo.

const GAMES_DIR := "res://games"


static func game_folders(games_dir: String = GAMES_DIR) -> PackedStringArray:
	var out: PackedStringArray = []
	for d in DirAccess.get_directories_at(games_dir):
		if not d.begins_with("_") and not d.begins_with("."):
			out.append(games_dir.path_join(d))
	out.sort()
	return out


## Tutti i giochi validi, ordinati per titolo. I manifest non validi vengono segnalati.
static func list_games(games_dir: String = GAMES_DIR) -> Array[GameManifest]:
	var out: Array[GameManifest] = []
	for folder in game_folders(games_dir):
		var m := GameManifest.load_from(folder)
		if m.is_valid():
			out.append(m)
		else:
			push_warning("Gioco ignorato (%s): %s" % [folder, "; ".join(m.errors)])
	out.sort_custom(func(a: GameManifest, b: GameManifest) -> bool: return a.title.naturalnocasecmp_to(b.title) < 0)
	return out


static func find(id: String, games_dir: String = GAMES_DIR) -> GameManifest:
	for m in list_games(games_dir):
		if m.id == id:
			return m
	return null
