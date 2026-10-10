extends AutotestScenario
## [MP] Hôte : équipement et inventaire de partie en réseau (GAME_CONCEPT
## §4.12, §4.13). Le client part avec le niveau et les armes de départ de SON
## profil (envoyés à l'hôte au chargement) ; l'hôte range deux armes dans son
## inventaire ; le client les échange par son panneau ; l'état d'équipement
## est sur l'hôte, répliqué à tous (puissance visible des autres joueurs) ;
## une arme de niveau trop élevé est refusée ; le client tire avec l'arme
## échangée (cadence et munitions validées ici).

const PORT := 17911

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 120
	# Profil de l'hôte : niveau 2, sélection par défaut.
	var pr := PlayerProfile.new()
	pr.add_xp(PlayerProfile.xp_for_level(2))
	ProfileStore.save_profile(pr)
	if not await MpHelpers.host_game(self, PORT):
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	var cid := 0
	for pid in game.players:
		if pid != 1:
			cid = pid
	var cpd := game.session.get_data(cid)
	var hpd := game.session.local_data()

	# 1. Départ : chacun avec son profil.
	at.check(hpd.level == 2, "hôte : niveau de son profil (%d)" % hpd.level)
	at.check(cpd.level == 8, "client : niveau de son profil, reçu par l'hôte (%d)" % cpd.level)
	at.check(cpd.weapons.size() == 1 and cpd.weapons[0].uid == BaseWeapons.UID_PREFIX + WeaponDB.STARTING_WEAPON,
			"client : armes de départ de son profil")
	at.check(cpd.bag.is_empty(), "client : inventaire vide")

	# 2. Deux armes rangées dans l'inventaire du client (comme une construction).
	game.session.give_to_bag(cid, GameWeapon.make("mp40", 6, OwnedWeapon.Rarity.RARE, [], "w5"))
	game.session.give_to_bag(cid, GameWeapon.make("m14", 9, OwnedWeapon.Rarity.EPIC, [], "w6"))
	MpHelpers.signal_peer("rangees")

	# 3. Échange fait par le client : l'hôte (qui fait foi) le voit.
	if not await MpHelpers.wait_peer(self, "echange", 30.0):
		return
	at.check(cpd.weapons.size() == 1 and cpd.weapons[0].uid == "w5", "hôte : MP40 niveau 6 en main du client")
	at.check(cpd.bag.size() == 2 and cpd.bag[0].id == WeaponDB.STARTING_WEAPON and cpd.bag[1].uid == "w6",
			"hôte : pistolet rangé, M14 niveau 9 refusée (restée dans l'inventaire)")
	at.check(cpd.power() == 6, "puissance du client : %d" % cpd.power())
	# Tableau des scores de l'hôte : niveau et puissance du client.
	game.hud.scoreboard.refresh()
	var cells := _row_cells(game, "Client")
	at.check(cells.size() >= 3 and cells[1] == "8" and cells[2] == "6", "tableau des scores : niveau 8, puissance 6 (%s)" % [cells])

	# 4. Tir du client avec l'arme échangée : validé ici, munitions décomptées.
	var full := int(GameWeapon.stats(cpd.weapons[0]).mag)
	var shots := [0]
	game.combat.shot_validated.connect(func(pid): if pid == cid: shots[0] += 1)
	MpHelpers.signal_peer("tire")
	await until(func(): return shots[0] >= 1, 10.0, "tir du client validé")
	at.check(shots[0] >= 1 and int(cpd.weapons[0].mag) == full - shots[0], "MP40 du client : %d / %d" % [int(cpd.weapons[0].mag), full])
	await MpHelpers.finish(self)


## Textes des cellules de la ligne du joueur `who` dans le tableau des scores.
func _row_cells(game: Game, who: String) -> Array:
	for row in game.hud.scoreboard._rows_box.get_children():
		if row.is_queued_for_deletion():
			continue
		var hb := row.get_child(0)
		var texts := []
		for l in hb.get_children():
			texts.append((l as Label).text)
		if not texts.is_empty() and String(texts[0]).begins_with(who):
			return texts
	return []
