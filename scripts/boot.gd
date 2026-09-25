extends Node
## Point d'entrée : affiche la version puis ouvre le menu principal.
## (Les scénarios d'autotest prennent la main eux-mêmes ensuite.)

func _ready() -> void:
	print("[Boot] Call of Claude Zombie v%s — Godot %s" % [
		ProjectSettings.get_setting("application/config/version"),
		Engine.get_version_info().string])
	get_tree().change_scene_to_file.call_deferred(Router.MENU_SCENE)
