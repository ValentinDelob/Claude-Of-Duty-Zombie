extends AutotestScenario
## @rendu : mains FPS en cubes de 1,25 cm (ajout en cours, validées sur la
## planche docs/weapons/img/hands_m1911.png) : captures à la hanche et en
## visée de quelques armes (pistolet fin, fusil fin, mitraillette fine à
## largeurs paires, mitraillette à poignée avant en cubes de 2,5 cm), à
## comparer à la planche. Vérifie seulement que les mains sont construites
## et que la ligne de mire reste au centre (±1 px) ; à retirer une fois les
## mains validées en jeu.
## HL_ONLY (ids séparés par des virgules) : ces armes seulement.

var H := AutotestHelpers
var game: Game
var p: Player
var pd: PlayerData

const IDS := ["m1911", "ak47", "mp40", "mp5k"]


func equip(id: String) -> bool:
	pd.weapons = [WeaponDB.new_instance(WeaponDB.STARTING_WEAPON), WeaponDB.new_instance(id)]
	pd.slot = 1
	game.combat.cancel_reload(1)
	game.session.sync_inventory(1)
	var ok: bool = await until(func(): return p.weapons.current().get("id", "") == id, 2.0, "arme %s en main" % id)
	await seconds(WeaponController.SWITCH_TIME + 0.25)
	return ok


func run() -> void:
	timeout_sec = 120
	p = await H.start_solo_game(self)
	if p == null:
		return
	game = Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	pd = game.session.local_data()
	# Allée dégagée vers +X (même poste que weapon_aim).
	p.teleport_to(MapData.cell_to_world(Vector2i(2, 3), 0.05), -PI * 0.5)
	p.pitch = 0.0
	await seconds(0.4)
	var only := OS.get_environment("HL_ONLY")
	var ids: Array = IDS if only == "" else Array(only.split(","))
	for id in ids:
		if not await equip(id):
			continue
		var v := p.weapons.view
		at.check(v.hands != null and v.hands.hand_r != null and v.hands.hand_l != null, "%s : mains construites" % id)
		await seconds(0.3)
		await at.screenshot("hip_" + id)
		if OS.get_environment("HL_DEBUG") != "":
			# Mise au point : sans la zone d'équipe, puis sans les avant-bras.
			var team: Array = v.hands.find_children("team", "MeshInstance3D", true, false)
			for mi: MeshInstance3D in team:
				mi.visible = false
			await at.screenshot("hip_noteam_" + id)
			for mi: MeshInstance3D in team:
				mi.visible = true
			for n: Node3D in v.hands.find_children("forearm*", "Node3D", true, false):
				n.visible = false
			await at.screenshot("hip_noarms_" + id)
			for n: Node3D in v.hands.find_children("forearm*", "Node3D", true, false):
				n.visible = true
			# Cuir des gants en rouge pur, pièces d'arme en bleu.
			var red := StandardMaterial3D.new()
			red.albedo_color = Color.RED
			red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			for mi: MeshInstance3D in v.hands.find_children("leather", "MeshInstance3D", true, false):
				mi.material_override = red
			await at.screenshot("hip_red_" + id)
		p.input.aim = true
		await seconds(float(WeaponDB.stats(id).ads_time) + 0.6)
		var c := p.get_viewport().get_visible_rect().size * 0.5
		var mid: String = WeaponDB.stats(id).model
		var rear := p.camera.unproject_position(v.model.to_global(WeaponModels.anchor(mid, "sight")))
		var front := p.camera.unproject_position(v.model.to_global(WeaponModels.anchor(mid, "front")))
		at.check(maxf(rear.distance_to(c), front.distance_to(c)) <= 1.0,
				"%s : ligne de mire au centre (cran %.2f px, guidon %.2f px)" % [id, rear.distance_to(c), front.distance_to(c)])
		await at.screenshot("ads_" + id)
		p.input.aim = false
		await seconds(0.4)
