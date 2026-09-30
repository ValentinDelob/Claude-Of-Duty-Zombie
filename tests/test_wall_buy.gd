extends TestCase
## Achat mural (WallBuy) : une arme sans prix au mur n'est jamais donnée.


## Arme de la boîte mystère (CLAUDE-RAY) ou identifiant inconnu posé au mur
## (carte perso) : prix 0, l'achat (et le rachat de munitions à 0) la donnait
## gratuitement. Refusé sans toucher aux points ni à l'inventaire.
func test_weapon_without_wall_price_is_refused() -> void:
	assert_eq(WeaponDB.wall_cost("ray"), 0, "CLAUDE-RAY : pas de prix au mur")
	assert_eq(WeaponDB.wall_cost("inconnue"), 0, "arme inconnue : pas de prix")
	assert_true(WeaponDB.wall_cost("m14") > 0, "M14 : prix au mur")
	for id in ["ray", "inconnue"]:
		var g := Game.new()
		var session := Session.new()
		g.session = session
		var pd := PlayerData.new(1)
		pd.weapons = [WeaponDB.new_instance(WeaponDB.STARTING_WEAPON)]
		session.data[1] = pd
		var system := InteractionSystem.new()
		system.game = g
		var wb := WallBuy.new()
		wb.system = system
		# Même état que setup_marker (sans son push_error, compté par le check).
		wb.weapon_id = id
		wb.cost = WeaponDB.wall_cost(id)
		var points := pd.points
		wb.srv_use(1)
		assert_eq(pd.points, points, "%s : aucun point dépensé" % id)
		assert_eq(pd.weapons.size(), 1, "%s : arme non donnée" % id)
		# Déjà en main (rachat de munitions à moitié prix = 0) : refusé aussi.
		pd.weapons.append(WeaponDB.new_instance("ray"))
		pd.weapons[1].reserve = 0
		wb.weapon_id = "ray"
		wb.srv_use(1)
		assert_eq(pd.weapons[1].reserve, 0, "%s : munitions non rendues" % id)
		wb.free()
		system.free()
		session.free()
		g.free()
