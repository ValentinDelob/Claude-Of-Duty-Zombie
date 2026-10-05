extends AutotestScenario
## @rendu : captures d'un escalier dont le haut touche un mur (sortie sur le
## côté droit, palier plat en haut), revue humaine (étape 4 de
## docs/LEVELS_PLAN.md) ; à retirer une fois l'étape validée.
## @niveau perf : hors check par défaut ; lancer avec
## sh tools/scenario.sh stairs_top_wall_look (fenêtre réduite, hors écran).
## Immeuble de tests/test_stairs_floors.gd, escalier posé par les règles de
## l'éditeur contre le mur nord : vu du rez-de-chaussée (volée, palier contre
## le mur) puis du niveau 3,5 m (sortie sur le côté, garde-corps de la trémie).

const Floors := preload("res://tests/test_stairs_floors.gd")
const TopWall := preload("res://tests/test_stairs_top_wall.gd")
const MAP_ID := "escalier_mur"
const OFF := MapGeom.WORLD_OFFSET


func run() -> void:
	timeout_sec = 120
	var doc := Floors.tower_with_stairs()
	var r := Floors.place(doc, 0, TopWall.RECT, "n")
	at.check(r.ok and String(r.get("sortie", "")) == "droite", "escalier posé, sortie à droite (%s)" % MapRules.why(r))
	var dir := EditorMap.map_dir(MAP_ID)
	if doc.save_dir(dir) != OK:
		at.fail("carte non enregistrée dans " + dir)
		return
	var p := await AutotestHelpers.start_solo_game(self, EditorMapDef.CUSTOM_PREFIX + MAP_ID)
	if p == null:
		return
	var game := Game.instance
	p.bot_controlled = true
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await AutotestHelpers.clear_zombies(self)
	await seconds(2.5)   # fin du titre « chargement »
	# Rez-de-chaussée, au sud-est : la volée monte vers le mur nord.
	p.teleport_to(Vector3(14.5 + OFF, 0.05, 9.5 + OFF))
	await seconds(0.4)
	AutotestHelpers.aim_at(p, Vector3(9.5 + OFF, 2.2, 1.5 + OFF))
	await seconds(0.5)
	await at.screenshot("rez_de_chaussee")
	# Niveau 3,5 m, à l'est du palier : la sortie sur le côté droit.
	p.teleport_to(Vector3(14.5 + OFF, 3.55, 1.25 + OFF))
	await seconds(0.6)
	at.check(p.global_position.y > 3.0, "joueur au niveau 3,5 m (%.2f)" % p.global_position.y)
	AutotestHelpers.aim_at(p, Vector3(9.75 + OFF, 2.6, 1.0 + OFF))
	await seconds(0.5)
	await at.screenshot("niveau_3_5")
	# Monte l'escalier et sort sur le côté : il arrive au niveau 3,5 m.
	p.teleport_to(Vector3(9.75 + OFF, 0.05, 8.0 + OFF))
	await seconds(0.4)
	AutotestHelpers.aim_at(p, Vector3(9.75 + OFF, 3.0, 1.0 + OFF))
	await seconds(0.3)
	await at.screenshot("pied")
	Router.back_to_menu()
