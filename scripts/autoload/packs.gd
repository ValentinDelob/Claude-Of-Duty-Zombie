extends Node
## Packs — paquets de contenu supplémentaires (docs/RELEASE.md) : le lanceur
## démarre le jeu avec `--main-pack <core>.pck` puis, après `--`, la liste des
## autres paquets à monter (répliques d'une langue…) :
##   engine.exe --main-pack store/<core>.pck -- --packs=<vox-fr>.pck,<vox-en>.pck
## Premier autoload, montage dans _init() : avant que quoi que ce soit ne soit
## chargé (la documentation de Godot le demande pour les paquets remplaçant
## des fichiers). Les chemins res:// ne changent pas (CharacterDB charge les
## répliques par chemin). Sans --packs (éditeur, tests, exécutable complet
## des anciens lanceurs) : rien à faire, tout est déjà dans le paquet principal.

## Paquets montés (chemins), pour les journaux et les rapports de plantage.
var mounted := PackedStringArray()


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--packs="):
			for p in a.substr(8).split(",", false):
				_mount(p)


func _mount(path: String) -> void:
	# Seulement des fichiers .pck existants (le lanceur a vérifié leur somme).
	if path.get_extension().to_lower() != "pck" or not FileAccess.file_exists(path):
		push_warning("[Packs] paquet ignoré (introuvable ou non .pck) : " + path)
		return
	if ProjectSettings.load_resource_pack(path, true):
		mounted.append(path)
		print("[Packs] paquet monté : " + path.get_file())
	else:
		push_error("[Packs] paquet illisible : " + path)
