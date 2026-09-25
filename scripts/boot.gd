extends Node
## Point d'entrée du jeu. Pour l'instant : vérifie que le projet démarre.

func _ready() -> void:
	print("[Boot] Call of Claude Zombie v%s — Godot %s" % [
		ProjectSettings.get_setting("application/config/version"),
		Engine.get_version_info().string])
