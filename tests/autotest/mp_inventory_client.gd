extends AutotestScenario
## [MP] Client : part avec son profil (niveau 8, pistolet de départ), échange
## par son panneau d'inventaire l'arme en main avec une arme rangée par
## l'hôte, se voit refuser une arme de niveau 9, voit le niveau et la
## puissance de l'hôte, puis tire avec l'arme échangée.

const PORT := 17911

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 120
	var pr := PlayerProfile.new()
	pr.add_xp(PlayerProfile.xp_for_level(8))
	pr.set_starting_weapons([WeaponDB.STARTING_WEAPON])
	ProfileStore.save_profile(pr)
	if not await MpHelpers.join_game(self, PORT):
		return
	var game := Game.instance
	var p := game.local_player
	p.bot_controlled = true
	var pd := game.session.local_data()
	var wc := p.weapons
	await until(func(): return pd.level == 8, 5.0, "niveau reçu de l'hôte")
	at.check(pd.level == 8, "niveau du profil répliqué (%d)" % pd.level)
	var hpd := game.session.get_data(1)
	at.check(hpd != null and hpd.level == 2 and hpd.power() == 1, "niveau et puissance de l'hôte visibles (%d, %d)" % [hpd.level if hpd else -1, hpd.power() if hpd else -1])

	# 1. Armes rangées par l'hôte : répliquées.
	if not await MpHelpers.wait_peer(self, "rangees", 30.0):
		return
	await until(func(): return pd.bag.size() == 2, 5.0, "inventaire reçu")
	at.check(pd.bag.size() == 2 and pd.bag[0].uid == "w5" and pd.bag[1].level == 9, "client : inventaire répliqué")

	# 2. Échange par le panneau : MP40 niveau 6 en main.
	var inv := game.hud.inventory
	inv.open()
	inv.press(0, 0)
	inv.press(1, 0)
	await until(func(): return wc.current().get("uid", "") == "w5", 5.0, "MP40 en main")
	at.check(wc.current().get("uid", "") == "w5" and pd.bag[0].id == WeaponDB.STARTING_WEAPON, "échange appliqué par l'hôte et reçu")
	at.check(pd.power() == 6, "puissance locale : %d" % pd.power())
	# 3. M14 niveau 9 : refusée par l'hôte.
	inv.press(0, 0)
	inv.press(1, 1)
	await seconds(1.0)
	at.check(pd.weapons[0].uid == "w5" and pd.bag[1].uid == "w6", "M14 niveau 9 refusée (joueur niveau 8)")
	inv.close()
	MpHelpers.signal_peer("echange")

	# 4. Tir avec l'arme échangée.
	if not await MpHelpers.wait_peer(self, "tire", 30.0):
		return
	await seconds(WeaponController.SWITCH_TIME + 0.2)
	await H.shoot(self, p)
	await MpHelpers.finish(self)
