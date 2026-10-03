extends AutotestScenario
## Éditeur de cartes silencieux (bug signalé le 03/10/2026 : la musique du
## menu principal s'entendait dans l'éditeur). Menu principal (musique) ->
## bouton ÉDITEUR DE CARTES : le menu est entièrement libéré (scène, fond 3D,
## écrans, SubViewports), aucune musique ni son du menu ne joue, même après
## quelques secondes -> retour au menu : la musique reprend -> réouverture de
## l'éditeur : silence -> fin d'une partie lancée par TESTER (musique de la
## carte, retour dans l'éditeur par Router.back_to_menu) : silence.

var _autoloads: Array[String] = []


func run() -> void:
	timeout_sec = 90
	for p in ProjectSettings.get_property_list():
		var n := String(p.name)
		if n.begins_with("autoload/"):
			_autoloads.append(n.substr(9))
	if not await _menu("menu principal"):
		return
	at.check(Audio.music_name() == MainMenu.MUSIC and Audio.music_playing(), "menu : musique du menu (%s)" % Audio.music_name())
	for i in 2:
		var menu: MainMenu = tree().current_scene
		# Sons du menu en cours au moment de partir (silhouette du fond).
		Audio.play_ui("menu_presence", -9.0)
		var screen := menu.current
		at.check(screen.has_method("_editor"), "écran principal du menu")
		screen.call("_editor")
		if not await until(func(): return tree().current_scene is MapEditor, 6.0, "éditeur ouvert (%d)" % (i + 1)):
			return
		await frames(3)
		_check_silent("éditeur ouvert depuis le menu (%d)" % (i + 1))
		at.check(not is_instance_valid(menu), "le menu principal est libéré (%d)" % (i + 1))
		_check_no_menu_left("éditeur (%d)" % (i + 1))
		await seconds(2.0)
		_check_silent("éditeur, 2 s plus tard (%d)" % (i + 1))
		# Retour au menu : la musique reprend.
		(tree().current_scene as MapEditor).quit_to_menu()
		if not await _menu("retour au menu (%d)" % (i + 1)):
			return
		await until(func(): return Audio.music_playing(), 3.0, "musique du menu relancée")
		at.check(Audio.music_name() == MainMenu.MUSIC and Audio.music_playing(), "retour au menu : la musique reprend (%d)" % (i + 1))
	# Fin d'une partie lancée par TESTER : retour dans l'éditeur, sans la
	# musique de la carte (simulée : la partie elle-même est couverte par
	# map_editor_play).
	tree().change_scene_to_file(MapEditor.SCENE)
	if not await until(func(): return tree().current_scene is MapEditor, 6.0, "éditeur ouvert (TESTER)"):
		return
	await frames(3)
	Router.return_scene = MapEditor.SCENE
	Audio.play_music("ambience_bunker", -6.0, 3.0)
	var before := tree().current_scene.get_instance_id()
	Router.back_to_menu()
	if not await until(func(): return tree().current_scene is MapEditor and tree().current_scene.get_instance_id() != before, 6.0, "retour dans l'éditeur après TESTER"):
		return
	await frames(3)
	_check_silent("retour dans l'éditeur après TESTER")
	await seconds(1.5)
	_check_silent("retour après TESTER, 1,5 s plus tard")
	(tree().current_scene as MapEditor).quit_to_menu()
	await _menu("menu final")


func _menu(what: String) -> bool:
	if not await until(func(): return tree().current_scene is MainMenu and (tree().current_scene as MainMenu).current != null, 6.0, what):
		return false
	await frames(5)
	return true


## Aucune musique en lecture (ni fondu de sortie) ni son du menu.
func _check_silent(what: String) -> void:
	at.check(not Audio.music_playing() and Audio.music_name() == "", "%s : aucune musique (%s)" % [what, Audio.music_name()])
	var menu_sounds := []
	for p: AudioStreamPlayer in Audio._pool_2d:
		if p.playing and p.stream != null and p.stream.resource_path.get_file().begins_with("menu_"):
			menu_sounds.append(p.stream.resource_path.get_file())
	at.check(menu_sounds.is_empty(), "%s : aucun son du menu (%s)" % [what, menu_sounds])
	# Aucun lecteur audio hors de l'autoload Audio ne joue de musique.
	var players := []
	_players(tree().root, players)
	at.check(players.is_empty(), "%s : aucun autre lecteur sur le bus Music (%s)" % [what, players])


func _players(n: Node, out: Array) -> void:
	if n == Audio:
		return
	if n is AudioStreamPlayer and (n as AudioStreamPlayer).playing and (n as AudioStreamPlayer).bus == "Music":
		out.append(n.get_path())
	for c in n.get_children():
		_players(c, out)


## Rien du menu ne reste dans l'arbre : à la racine, seulement les autoloads
## et l'éditeur ; aucun nœud du menu (fond 3D, écrans, scène) nulle part.
func _check_no_menu_left(what: String) -> void:
	var extra := []
	for c in tree().root.get_children():
		if c != tree().current_scene and not (String(c.name) in _autoloads):
			extra.append(String(c.name))
	at.check(extra.is_empty(), "%s : rien d'autre que l'éditeur à la racine (%s)" % [what, extra])
	var left := []
	_menu_nodes(tree().root, left)
	at.check(left.is_empty(), "%s : aucun nœud du menu restant (%s)" % [what, left])


func _menu_nodes(n: Node, out: Array) -> void:
	if n is MainMenu or n is MenuBackdrop or n is MenuScreen or n.scene_file_path == Router.MENU_SCENE:
		out.append(n.get_path())
		return
	for c in n.get_children():
		_menu_nodes(c, out)
