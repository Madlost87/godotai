class_name BodyGame
extends Node2D
## Classe base di tutti i giochi in games/<id>/.
##
## Cosa fa per te:
## - legge il manifest (game.json nella cartella della scena) → `manifest`;
## - chiede al tracker la sessione giusta (giocatori, capacità) e la ritira all'uscita;
## - azione "game_exit" (Esc) → torna al menu (launcher).
##
## Come usarla: lo script della scena principale del gioco fa `extends BodyGame` e
## implementa _game_ready() al posto di _ready(). Se un gioco ridefinisce _ready() o
## _exit_tree() deve chiamare super().

const LAUNCHER_SCENE := "res://launcher/launcher.tscn"

var manifest: GameManifest


func _ready() -> void:
	var folder := scene_file_path.get_base_dir()
	if not folder.is_empty():
		manifest = GameManifest.load_from(folder)
		if manifest.is_valid():
			BodyInput.set_session(manifest.session())
		else:
			push_warning("Manifest non valido per %s: %s" % [folder, "; ".join(manifest.errors)])
	var exit_handler := _ExitHandler.new()
	exit_handler.name = "GameExitHandler"
	exit_handler.game = self
	add_child(exit_handler)
	_game_ready()


## Da implementare nel gioco: inizializzazione (al posto di _ready).
func _game_ready() -> void:
	pass


func _exit_tree() -> void:
	BodyInput.clear_session()


## Capacità richieste dal manifest che il sensore collegato non ha (vuoto = tutto ok).
func missing_capabilities() -> PackedStringArray:
	return manifest.missing_capabilities(BodyInput.capabilities) if manifest != null else PackedStringArray()


## Torna al menu (o chiude, se il menu non c'è).
func exit_game() -> void:
	if ResourceLoader.exists(LAUNCHER_SCENE):
		get_tree().change_scene_to_file.call_deferred(LAUNCHER_SCENE)
	else:
		get_tree().quit()


## Nodo figlio che gestisce l'uscita: così funziona anche se il gioco ridefinisce
## _unhandled_input senza chiamare super().
class _ExitHandler:
	extends Node

	var game: BodyGame

	func _unhandled_input(event: InputEvent) -> void:
		if event.is_action_pressed(&"game_exit") and not event.is_echo():
			get_viewport().set_input_as_handled()
			game.exit_game()
