extends "res://tests/autotest/hub2_look.gd"
## @rendu : écrans JOUER et récapitulatif du hub v2 EN COURS DE
## DÉVELOPPEMENT (Partie.dc.html, PartieCoop.dc.html, Recap.dc.html) :
## captures à comparer aux maquettes, avec leur contenu (cartes perso
## « Verrückt », « Quai 13 », « Nouvelle carte 3 », records, salon de trois
## joueurs, partie de la maquette : niveau 23 -> 24, +6 240 XP, butin), en
## français, en anglais et à 130 %. Navigation réelle : START, X (armes de
## départ), Échap, A pour finir l'animation du récapitulatif.
## Captures : tests/_out/shots/hub2_play_look_<écran>_<hauteur>.png.
## Scénario retiré une fois les écrans livrés (captures seulement pour un
## ajout en cours).

const PORT := 17781
const CUSTOM := [["verruckt", "Verrückt"], ["quai_13", "Quai 13"], ["nouvelle_carte_3", "Nouvelle carte 3"]]
const FIXTURE := "res://tests/fixtures/maps/smallest"


## Profil de la maquette, avec un contrat prêt à remettre (Sangles de
## contention : récapitulatif).
static func play_profile() -> PlayerProfile:
	var pr := demo_profile()
	pr.contracts.active.append({"id": "orderly_straps", "accepted": 0})
	pr.add_samples("brancard_strap", 3)
	return pr


func run() -> void:
	timeout_sec = 150
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	menu = tree().current_scene
	await until(_settled, 5.0, "menu titre affiché")
	_saved_name = Settings.player_name
	Settings.player_name = "Valentin"
	Settings.hub_v2 = true
	Settings.last_map = "bunker_k7"
	ProfileStore.save_profile(play_profile())
	_install_custom_maps()
	CareerStats.record_map_best("bunker_k7", 23)
	CareerStats.record_map_best(EditorMapDef.CUSTOM_PREFIX + "verruckt", 14)
	await press("ui_accept")
	await until(_settled, 3.0, "hub v2 affiché")
	hub = menu.current
	# JOUER (START) : vue SOLO.
	await pad(JOY_BUTTON_START)
	at.check(hub.current_id == "play", "START : JOUER (%s)" % hub.current_id)
	var p: Hub2PlayPanel = hub.panels.play
	at.check(p.view == Hub2PlayPanel.SOLO, "vue SOLO")
	at.check(p.map_buttons.size() == 4, "1 carte du jeu + 3 cartes perso (%d)" % p.map_buttons.size())
	await seconds(0.5)
	_check_inside(hub, "JOUER solo")
	await shot("play_solo_pad")
	Settings.using_pad = false
	await key(KEY_TAB, false)
	hub.refresh_prompts()
	await seconds(0.2)
	await shot("play_solo")
	# Carte perso choisie : plan, POUR LE FUN.
	_rm(Hub2MapShot.cache_dir())
	p.select_map(EditorMapDef.CUSTOM_PREFIX + "quai_13")
	await frames(2)
	at.check(p.preview_fun.visible, "carte perso : POUR LE FUN")
	at.check(p.preview_loading.visible and p.preview.fit == Hub2Render.FIT_INTEGER,
			"carte perso : plan net (échelle entière) et APERÇU EN PRÉPARATION")
	await shot("play_custom_loading")
	var rendered := await until(func(): return p.preview.fit == Hub2Render.FIT_COVER and not p.preview_loading.visible, 15.0, "vue en jeu de la carte perso")
	at.check(rendered and FileAccess.file_exists(Hub2MapShot.cache_path(EditorMapDef.CUSTOM_PREFIX + "quai_13")),
			"vue en jeu rendue et gardée (%s)" % Hub2MapShot.cache_path(EditorMapDef.CUSTOM_PREFIX + "quai_13"))
	await seconds(0.5)
	await shot("play_custom")
	# Deuxième choix : relue du cache, tout de suite.
	p.select_map("bunker_k7")
	p.select_map(EditorMapDef.CUSTOM_PREFIX + "quai_13")
	at.check(p.preview.fit == Hub2Render.FIT_COVER and not p.preview_loading.visible, "carte perso : vue relue du cache")
	# Défi de la semaine.
	p.select_map(Hub2PlayPanel.WEEKLY)
	await seconds(0.3)
	await shot("play_weekly")
	p.select_map("bunker_k7")
	# X : armes de départ.
	await key(KEY_X)
	at.check(p.modal != null, "X : choix des armes de départ")
	await seconds(0.3)
	await shot("play_loadout")
	await press("ui_cancel")
	at.check(p.modal == null, "Échap : fenêtre fermée")
	# Salon coop de la maquette (trois joueurs).
	await _lobby_shots(p)
	# Récapitulatif de la maquette.
	await _recap_shots()
	# 130 %.
	Settings.menu_ui_scale = 1.3
	await frames(4)
	hub = menu.current
	hub.open("play")
	await seconds(0.5)
	_check_inside(hub, "JOUER 130 %")
	await shot("play_solo_130")
	Router.last_match = mock_last()
	hub.open("recap")
	await seconds(0.2)
	(hub.panels.recap as Hub2RecapPanel).finish()
	await seconds(0.3)
	_check_inside(hub, "récapitulatif 130 %")
	await shot("recap_end_130")
	hub.open("lab")
	Settings.menu_ui_scale = 1.0
	await frames(3)
	# Anglais.
	Settings.language = "en"
	menu.show_screen("hub2", {"screen": "play"})
	await until(_settled, 3.0, "hub v2 en anglais")
	hub = menu.current
	await seconds(0.5)
	await shot("play_solo_en")
	Router.last_match = mock_last()
	hub.open("recap")
	await seconds(0.2)
	(hub.panels.recap as Hub2RecapPanel).finish()
	await seconds(0.3)
	await shot("recap_end_en")
	Settings.language = "fr"
	Settings.hub_v2 = false
	Settings.player_name = _saved_name
	Router.last_match = {}
	ProfileStore.reset()
	CareerStats.reset()
	_remove_custom_maps()


## Comme hub2_look, sans le contenu d'une liste défilante (coupé par elle).
func _scan_inside(n: Node, screen: Rect2, bad: Array) -> void:
	if n is ScrollContainer:
		var sc := n as ScrollContainer
		if sc.is_visible_in_tree() and not screen.encloses(sc.get_global_rect()):
			bad.append("%s %s" % [sc.name, sc.get_global_rect()])
		return
	super._scan_inside(n, screen, bad)


## Copies de la carte de test SMALLEST dans le dossier des cartes de ce
## scénario (jamais les cartes du joueur), sous les noms de la maquette.
func _install_custom_maps() -> void:
	for c in CUSTOM:
		var dst := EditorMap.map_dir(String(c[0]))
		if dst == "" or not dst.begins_with(ProjectSettings.globalize_path("res://tests/_out")):
			at.fail("dossier des cartes de test : %s" % dst)
			return
		DirAccess.make_dir_recursive_absolute(dst)
		for f in DirAccess.get_files_at(FIXTURE):
			if not f.ends_with(".json"):
				continue
			var txt := FileAccess.get_file_as_string(FIXTURE.path_join(f))
			if f == "carte.json":
				var d: Dictionary = JSON.parse_string(txt)
				d["id"] = c[0]
				d["nom"] = {"fr": c[1], "en": c[1]}
				txt = JSON.stringify(d, " ")
			var out := FileAccess.open(dst.path_join(f), FileAccess.WRITE)
			out.store_string(txt)
			out.close()
	HubPlayView._defs.clear()


func _remove_custom_maps() -> void:
	var root := EditorMap.maps_root()
	if root.begins_with(ProjectSettings.globalize_path("res://tests/_out")):
		_rm(root)


func _rm(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for d in DirAccess.get_directories_at(dir):
		_rm(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _lobby_shots(p: Hub2PlayPanel) -> void:
	p.coop_tab.pressed.emit()
	await seconds(0.3)
	await shot("play_coop_form")
	p.port_edit.text = str(PORT + OS.get_environment("AUTOTEST_PORT_OFFSET").to_int())
	p.host_lobby()
	await frames(3)
	at.check(Net.mode == Net.Mode.HOST and p.view == Hub2PlayPanel.LOBBY, "salon hébergé")
	if p.lobby == null:
		return
	# Joueurs de la maquette (registre local : affichage seulement).
	Net.players[1]["lvl"] = 23
	Net.players[1]["start"] = PackedStringArray(["m1911", "bat"])
	Net.players[5] = {"name": "Mehdi", "slot": 1, "lvl": 31, "start": PackedStringArray(["mp40", "bat", "m1911"]), "ping": 24}
	Net.players[9] = {"name": "Sarah_K", "slot": 2, "lvl": 8, "start": PackedStringArray(["olympia", "m1911"]), "ping": 41}
	Net.players_changed.emit()
	await seconds(0.5)
	at.check(p.lobby.cards.size() == 3, "trois joueurs (%d)" % p.lobby.cards.size())
	at.check(p.lobby.launch_sub.text == "3 joueurs prêts sur 3", "LANCER : %s" % p.lobby.launch_sub.text)
	Settings.using_pad = true
	hub.refresh_prompts()
	_check_inside(hub, "salon")
	await shot("play_coop_lobby_pad")
	# Un joueur pas encore revenu : EN ATTENTE.
	Net.players[9]["away"] = true
	Net.players_changed.emit()
	await seconds(0.2)
	await shot("play_coop_waiting")
	Settings.using_pad = false
	Net.players.erase(5)
	Net.players.erase(9)
	Net.leave()
	GameState.reset_to_menu()
	p.sync()
	Hub2PlayPanel.last_view = Hub2PlayPanel.SOLO
	p.choose(Hub2PlayPanel.SOLO)
	await frames(2)


## Partie de la maquette (Recap.dc.html) : niveau 23 -> 24, +6 240 XP,
## 17 manches, 284 zombies, 42:18, COUPERET / FEU FOLLET / BALAI, 9
## échantillons.
static func mock_last(evacuated := true, progress := true) -> Dictionary:
	var r := MatchResult.new()
	r.evacuated = evacuated
	r.round_reached = 17
	r.kills = 284
	r.duration_sec = 42 * 60 + 18
	var l := XpRules.new_ledger()
	l.kills = {"walker": 200, "dog": 10, "surgeon": 1}
	l.kill_xp = {"walker": 2840, "dog": 500, "surgeon": 640}
	l.wave_xp = 180
	l.rounds = 16
	l.round_xp = 1480
	l.evac_bonus = 600
	l.closed = true
	r.xp_ledger = l
	var start := PlayerProfile.xp_for_level(24) - 4680
	r.xp = 6240 if progress else 0
	r.profile_xp = start + r.xp
	r.level_before = 23
	r.level_after = 24 if progress else 23
	var pd := PlayerData.new(1)
	pd.weapons = [GameWeapon.make("python", 20, 3, [], "loot:1"), GameWeapon.make("spectre", 18, 2, [], "loot:2"),
		GameWeapon.make("stakeout", 17, 1, [], "loot:3")]
	var loot := ProfileLoot.carried(pd, [], {"dog_fang": 3, "dog_fur": 2, "brancard_strap": 2, "brancard_bracelet": 1,
		"surgeon_scalpel": 1})
	r.loot = ProfileLoot.report(loot, evacuated and progress)
	if not progress:
		r.loot["custom"] = true
	return {"result": r, "map": "BUNKER K-7", "map_id": "bunker_k7" if progress else EditorMapDef.CUSTOM_PREFIX + "quai_13",
		"progress": progress, "challenge": false, "solo": true}


func _recap_shots() -> void:
	Router.last_match = mock_last()
	hub.open("recap")
	var r: Hub2RecapPanel = hub.panels.recap
	at.check(not hub.top_bar.visible and not hub.prompts.visible, "récapitulatif : sans barre du haut ni invites")
	r.frozen = true
	r.set_process(false)
	var up: float = r._ups[0][1] if not r._ups.is_empty() else 3.0
	at.check(not r._ups.is_empty(), "passage au niveau 24 prévu (%.2f s)" % up)
	for s in [["recap_t0", 0.3], ["recap_rows", 1.0], ["recap_climb", up - 0.4], ["recap_levelup", up + 0.12], ["recap_levelup_030", up + 0.3], ["recap_levelup_045", up + 0.45],
			["recap_levelup_text", up + 0.6], ["recap_levelup_late", up + 1.3]]:
		r.apply_time(float(s[1]))
		await frames(3)
		await shot(String(s[0]))
	r.frozen = false
	r.play()
	await seconds(0.3)
	await press("ui_accept")
	at.check(not r.animating(), "A : animation finie d'un coup")
	await seconds(0.2)
	await shot("recap_end")
	# Défaite : ce qui est perdu.
	Router.last_match = mock_last(false)
	r.load_last()
	r.finish()
	await seconds(0.2)
	await shot("recap_defeat")
	# Carte perso : aucune progression.
	Router.last_match = mock_last(true, false)
	r.load_last()
	r.finish()
	await seconds(0.2)
	await shot("recap_custom")
	await press("ui_accept")
	at.check(hub.current_id == "lab", "A (fin) : CONTINUER -> LABO (%s)" % hub.current_id)
