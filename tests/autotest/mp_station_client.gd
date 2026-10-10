extends AutotestScenario
## [MP] Client : construit à la station une arme de son arsenal (profil
## local : niveau 6, MP40 niveau 4 rare, M14 niveau 9) par l'interface ouverte
## avec [F] ; voit l'état de sa construction (manche de fin, puis prête) reçu
## de l'hôte et la récupère avec [F].

const PORT := 17915

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 150
	var pr := PlayerProfile.new()
	pr.add_xp(PlayerProfile.xp_for_level(6))
	var mp40 := OwnedWeapon.create("mp40", 4, OwnedWeapon.Rarity.RARE)
	mp40.uid = "w1"
	pr.add_weapon(mp40)
	pr.add_weapon(OwnedWeapon.create("m14", 9, OwnedWeapon.Rarity.EPIC))
	ProfileStore.save_profile(pr)
	if not await MpHelpers.join_game(self, PORT):
		return
	var game := Game.instance
	var p := game.local_player
	p.bot_controlled = true
	var pd := game.session.local_data()
	var st := game.station
	at.check(st != null, "client : station de construction")
	if st == null:
		return
	p.teleport_to(st.global_position + st.global_basis.z * 1.7 + Vector3.UP * 0.05)
	await frames(3)
	MpHelpers.signal_peer("place")
	if not await MpHelpers.wait_peer(self, "vu", 30.0):
		return
	await until(func(): return pd.points == 3000, 5.0, "ferraille reçue")

	# 1. [F] : l'interface s'ouvre (ordre de l'hôte), arsenal du profil local.
	var panel := game.hud.station_panel
	H.aim_at(p, st.interact_point())
	await until(func(): return game.interact.focused == st, 3.0, "station visée")
	p.input.interact_pressed = true
	var ok: bool = await until(func(): return panel.visible, 5.0, "interface ouverte")
	at.check(ok and panel.entries.size() == 3, "client : interface ouverte, 3 armes (%d)" % panel.entries.size())
	if not ok:
		return
	# M14 niveau 9 : refusée par l'hôte même demandée directement.
	st.request_build(panel.entries[2])
	await seconds(0.6)
	at.check(st.builds.is_empty() and pd.points == 3000, "client : arme trop haute refusée")
	panel.press_build(1)
	MpHelpers.signal_peer("lance")
	ok = await until(func(): return not st.local_build().is_empty(), 5.0, "état de construction reçu")
	at.check(ok and not bool(st.local_build().ready), "client : en construction")
	if not await MpHelpers.wait_peer(self, "en_cours", 30.0):
		return
	at.check(panel.status_text().contains(str(int(st.local_build()["round"]))), "client : manche de fin affichée « %s »" % panel.status_text())
	# Seconde construction : refusée par l'hôte.
	st.request_build(panel.entries[0])
	await seconds(0.6)
	MpHelpers.signal_peer("seconde")
	panel.close()

	# 2. Prête : récupération avec [F].
	if not await MpHelpers.wait_peer(self, "prete", 30.0):
		return
	ok = await until(func(): return bool(st.local_build().get("ready", false)), 5.0, "prête chez le client")
	at.check(ok and st.prompt(p.peer_id).contains(Lang.t("Récupérer", "Collect")), "client : invite « %s »" % st.prompt(p.peer_id))
	H.aim_at(p, st.interact_point())
	await until(func(): return game.interact.focused == st, 3.0, "station visée")
	p.input.interact_pressed = true
	ok = await until(func(): return pd.bag.size() == 1, 5.0, "arme dans l'inventaire")
	at.check(ok and String(pd.bag[0].uid) == "w1" and int(pd.bag[0].level) == 4, "client : MP40 de son arsenal récupéré")
	if not await MpHelpers.wait_peer(self, "fin", 30.0):
		return
	await MpHelpers.finish(self)
