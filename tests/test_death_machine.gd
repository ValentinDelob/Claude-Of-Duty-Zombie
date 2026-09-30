extends TestCase
## Bonus FAUCHEUSE (DEATH MACHINE de BO1) : arme de bonus hors arsenal, tenue
## par-dessus l'inventaire.


func test_in_bag() -> void:
	assert_true(PowerupRules.DEATH_MACHINE in PowerupRules.ALL, "dans le sac de bonus")
	assert_eq(PowerupRules.display_name(PowerupRules.DEATH_MACHINE), Lang.t("FAUCHEUSE !", "REAPER!"))
	var model := PowerupModels.build(PowerupRules.DEATH_MACHINE)
	assert_true(model.get_child_count() > 8, "modèle au sol")
	model.free()


func test_weapon_stats() -> void:
	var id := PowerupRules.DEATH_MACHINE_WEAPON
	assert_true(WeaponDB.exists(id) and WeaponDB.is_powerup_weapon(id))
	assert_false(WeaponDB.WEAPONS.has(id), "hors arsenal (ni mur ni boîte)")
	assert_false(WeaponDB.box_pool().has(id), "jamais dans la boîte")
	assert_eq(WeaponDB.wall_cost(id), 0)
	var s := WeaponDB.stats(id)
	for k in WeaponDB.REQUIRED:
		assert_true(s.has(k), "champ %s" % k)
	assert_true(s.get("infinite", false), "munitions illimitées")
	assert_eq(s.name, "FAUCHEUSE")
	# 30 s de tir continu sans vider le chargeur (même avec TWIN SHOT).
	assert_true(int(s.mag) > int(s.rpm) / 60.0 * PowerupRules.DURATION * 1.4, "chargeur pour 30 s")
	# Dégâts énormes : bien au-dessus des mitrailleuses de l'arsenal.
	assert_true(int(s.damage) >= 3 * int(WeaponDB.stats("hk21").damage), "dégâts %d" % s.damage)
	assert_true(ResourceLoader.exists("res://assets/audio/%s.wav" % s.sound), "son %s" % s.sound)
	assert_true(ResourceLoader.exists("res://assets/audio/announce_death_machine.wav"), "annonce")
	var sp := WeaponModels.spec(s.model)
	assert_true(sp.parts.size() >= 10 and sp.anchors.muzzle.z < -0.4, "modèle FPS du minigun")


func test_player_data_overlay() -> void:
	var pd := PlayerData.new(3)
	pd.weapons = [WeaponDB.new_instance("m1911"), WeaponDB.new_instance("mp40")]
	pd.slot = 1
	assert_eq(pd.current_weapon().id, "mp40")
	pd.powerup_weapon = WeaponDB.new_instance(PowerupRules.DEATH_MACHINE_WEAPON)
	assert_eq(pd.current_weapon().id, PowerupRules.DEATH_MACHINE_WEAPON, "le minigun en main")
	# L'inventaire est intact dessous et répliqué avec l'arme de bonus.
	var copy := PlayerData.new(3)
	copy.apply_inventory(pd.inventory_dict())
	assert_eq(copy.current_weapon().id, PowerupRules.DEATH_MACHINE_WEAPON)
	assert_eq(copy.weapons.size(), 2)
	# À terre : plus de minigun (pistolet du dernier recours).
	pd.life = PlayerData.Life.DOWNED
	assert_eq(pd.current_weapon().id, "mp40")
	pd.life = PlayerData.Life.ALIVE
	pd.powerup_weapon = {}
	assert_eq(pd.current_weapon().id, "mp40", "arme rendue à la fin")
