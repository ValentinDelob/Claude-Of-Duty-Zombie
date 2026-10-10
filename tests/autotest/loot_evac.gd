extends AutotestScenario
## Butin des vagues spéciales (GAME_CONCEPT §4.7, §4.16), cas nominal en
## solo : vague de chiens forcée, chiens tués -> échantillons et pièce dans
## les onglets de la partie (chances forcées à 100 %), compteur discret ;
## vague vaincue -> une arme personnelle au sol, à la couleur du joueur ;
## inventaire plein -> message, l'arme reste ; ramassage par [F] ; pièce
## installée depuis le panneau d'inventaire ; évacuation -> armes, pièces et
## échantillons ajoutés au profil, rapport « butin gardé » à l'écran de fin.

var H := AutotestHelpers
var game: Game
var p: Player


func run() -> void:
	timeout_sec = 120
	ProfileStore.reset()
	p = await H.start_solo_game(self, "test_arena")
	if p == null:
		return
	game = Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	game.map_def.waves = WaveRules.parse({"speciale": {"premiere": 0, "intervalle": 0}})
	var loot := game.loot
	at.check(loot != null and loot.get_path() == ^"/root/Game/Loot", "système de butin présent")
	loot.debug_part_chance = 1.0
	loot.debug_sample_chance = 1.0
	var pd := game.session.local_data()
	game.rounds.paused = false

	# 1. Vague de chiens : échantillons et pièces par chien tué.
	if not await H.clear_dog_wave(self, 2):
		return
	var killed := game.rounds.dogs.killed
	at.check(killed >= 1, "chiens tués : %d" % killed)
	for s in ["dog_fang", "dog_fur", "dog_collar"]:
		at.check(int(loot.my_samples.get(s, 0)) == killed, "échantillon %s : %d" % [s, int(loot.my_samples.get(s, 0))])
	at.check(loot.my_parts.size() == killed, "une pièce par chien (chance forcée) : %d" % loot.my_parts.size())
	at.check(loot.counter_shown().contains(LootRules.sample_name("dog_fang")), "compteur affiché : « %s »" % loot.counter_shown())

	# 2. Arme personnelle au sol.
	at.check(loot.drops.size() == LootRules.WEAPONS_SPECIAL, "une arme par joueur (%d)" % loot.drops.size())
	var d: LootDrop = loot.drops.values()[0]
	at.check(d.owner_pid == 1 and d.is_inside_tree() and game.interact.get_obj(d.interact_id) == d, "arme au sol, enregistrée, au joueur")
	var lvl := GameWeapon.level_of(d.weapon)
	at.check(lvl >= 1 and lvl <= 4, "niveau manche 2 : 1 à 4 (%d)" % lvl)
	at.check(not BaseWeapons.is_base(d.weapon.id), "pas une arme de base : %s" % d.weapon.id)
	at.check(VoxelCheck.check_scene(d).ok, "modèle cubique")
	await at.screenshot("drop")

	# 3. Inventaire plein : refusé, l'arme reste.
	for i in GameWeapon.BAG:
		game.session.give_to_bag(1, GameWeapon.make("mp40", 1, 0, [], "w%d" % (i + 10)))
	H.aim_at(p, d.interact_point())
	if not await until(func(): return game.interact.focused == d, 2.0, "arme visée"):
		return
	p.input.interact_pressed = true
	await until(func(): return game.hud._flash.text == LootSystem.msg_text(LootSystem.MSG_BAG_FULL, ""), 2.0, "message inventaire plein")
	at.check(game.hud._flash.text == LootSystem.msg_text(LootSystem.MSG_BAG_FULL, ""), "message : « %s »" % game.hud._flash.text)
	at.check(loot.drops.has(d.drop_id) and pd.bag.size() == GameWeapon.BAG, "l'arme reste au sol")

	# 4. Une place libérée : ramassage.
	pd.bag.clear()
	game.session.sync_inventory(1)
	var found: Dictionary = d.weapon.duplicate(true)
	var drop_iid := d.interact_id
	await frames(2)
	p.input.interact_pressed = true
	await until(func(): return loot.drops.is_empty(), 2.0, "arme ramassée")
	at.check(loot.drops.is_empty() and game.interact.get_obj(drop_iid) == null, "arme retirée du sol")
	at.check(pd.bag.size() == 1 and pd.bag[0].uid == found.uid, "arme dans l'inventaire de partie")

	# 5. Pièce installée depuis le panneau d'inventaire (pièce puis arme).
	var inv := game.hud.inventory
	inv.open()
	at.check(inv.part_buttons.size() == loot.my_parts.size(), "rangée des pièces : %d" % inv.part_buttons.size())
	var parts_before := loot.my_parts.size()
	inv.press(InventoryPanel.ROW_PARTS, 0)
	inv.press(InventoryPanel.ROW_BAG, 0)
	await until(func(): return loot.my_parts.size() == parts_before - 1, 2.0, "pièce montée")
	at.check(pd.bag[0].parts.size() == 1, "pièce sur l'arme trouvée (score %d)" % GameWeapon.score(pd.bag[0]))
	inv.close()

	# 6. Évacuation : tout rejoint le profil.
	var door := game.evac
	var inside := door.global_position + door.global_basis.z * 1.5 + Vector3.UP * 0.05
	p.teleport_to(inside)
	await frames(3)
	H.aim_at(p, door.interact_point())
	await until(func(): return game.interact.focused == door, 2.0, "porte visée")
	p.input.interact_pressed = true
	var ok: bool = await until(func(): return GameState.state == GameState.State.GAME_OVER and game.last_result != null, 3.0, "évacuation")
	at.check(ok, "évacuation")
	if not ok:
		return
	var pr := ProfileStore.load_profile()
	var mine := pr.versions_of(found.id)
	at.check(mine.size() == 1 and mine[0].level == found.level and mine[0].parts.size() == 1, "arme trouvée dans l'arsenal, avec sa pièce")
	at.check(pr.parts.size() == parts_before - 1, "pièces non montées gardées : %d" % pr.parts.size())
	at.check(pr.sample_count("dog_fang") == killed and pr.sample_count("dog_collar") == killed, "échantillons au profil")
	at.check(pr.xp == game.last_result.xp and pr.xp > 0, "XP gardée (%d)" % pr.xp)
	at.check(game.last_result.loot.get("kept", false) == true, "résultat : butin gardé")
	at.check(game.hud.loot_report().begins_with(Lang.t("BUTIN GARDÉ", "LOOT KEPT")), "rapport : « %s »" % game.hud.loot_report())
	await at.screenshot("report")
	ProfileStore.reset()
