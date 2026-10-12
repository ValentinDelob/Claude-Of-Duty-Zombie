extends AutotestScenario
## Fenêtre d'évacuation (GAME_CONCEPT.md §4.5) dans le vrai jeu, sur l'arène de
## test (porte d'évacuation contre le mur nord) : porte fermée hors fenêtre ;
## vague spéciale (manche de chiens forcée) vaincue -> porte ouverte, aucun
## zombie, la manche suivante attend, cadre de vote du HUD (EvacVotePanel :
## EN ATTENTE, touches F1 / F2) ; fin des 2 minutes -> la partie continue ;
## vote ÉVACUER de loin (hors de la zone : repère de la porte) puis CONTINUER
## -> la partie reprend aussitôt ; vote ÉVACUER dans la zone -> évacuation de
## l'équipe et écran de fin (évacuation réussie, manche atteinte, durée).

var H := AutotestHelpers
var game: Game
var p: Player
var door: EvacDoor


## Manche de chiens forcée en `n`, vaincue aussitôt (tous les chiens « apparus »
## et aucun vivant) : la vague spéciale est terminée.
func _clear_special_wave(n: int) -> bool:
	var dogs := game.rounds.dogs
	dogs.debug_force_next(n)
	game.rounds.debug_jump_to(n)
	if not await until(func(): return dogs.active and game.rounds.round_n == n, 2.0, "vague spéciale %d" % n):
		return false
	at.check(game.rounds.wave == WaveRules.SPECIAL, "manche %d : vague spéciale" % n)
	dogs.spawned = dogs.total
	return await until(func(): return door.is_open, 3.0, "porte ouverte après la vague %d" % n)


## Vote de n'importe où (F1 : CONTINUER, F2 : ÉVACUER).
func _vote(v: int) -> void:
	await H.evac_vote(self, p, v)


## Choix affichés dans le cadre de vote, ligne du joueur local.
func _my_row() -> Dictionary:
	var rows: Array = game.hud.evac_panel.describe().rows
	return rows[0] if not rows.is_empty() else {}


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
	door = game.evac
	at.check(door != null and door.interact_id == "evac", "porte d'évacuation construite")
	if door == null:
		return
	at.check(WaveRules.is_default(game.map_def.waves), "schéma des vagues par défaut")
	at.check(not door.is_open and door.prompt(1) == "" and not game.hud.evac_panel.visible, "fermée hors fenêtre : ni invite ni cadre de vote")
	# Repère de la porte : +x le long du mur, +z vers la pièce.
	var inside := door.global_position + door.global_basis.z * 1.5 + Vector3.UP * 0.05
	var outside := door.global_position + door.global_basis.x * 2.4 + door.global_basis.z * 1.0 + Vector3.UP * 0.05
	at.check(door.in_zone(inside) and not door.in_zone(outside), "zone de la porte : devant elle, pas à 2,4 m sur le côté")
	# Vagues spéciales forcées seulement (aucune prévue d'ici la manche 6).
	game.map_def.waves = WaveRules.parse({"speciale": {"premiere": 0, "intervalle": 0}})
	game.rounds.paused = false

	# ------------------------------------------------ fin des 2 minutes
	if not await _clear_special_wave(2):
		return
	await frames(3)
	at.check(game.rounds.phase == RoundManager.Phase.INTERMISSION, "entracte pendant la fenêtre")
	at.check(game.zombies.alive_count() == 0, "aucun zombie pendant la fenêtre")
	var panel := game.hud.evac_panel.describe()
	at.check(panel.visible and panel.rows.size() == 1 and _my_row().me and _my_row().vote == EvacRules.Vote.NONE
			and _my_row().text == Lang.t("EN ATTENTE", "WAITING"), "cadre de vote : %s" % str(panel))
	at.check(panel.keys == [Settings.action_label("vote_continue"), Settings.action_label("vote_evacuate")]
			and (panel.clock.begins_with("1:") or panel.clock == "2:00"), "touches et temps : %s %s" % [panel.keys, panel.clock])
	at.check(door.prompt(1) == "" and game.interact.focused != door, "porte sans invite [F] : vote de n'importe où")
	at.check(not game.hud.evac_marker.visible, "pas encore voté : pas de repère de la porte")
	await at.screenshot("open")
	await seconds(RoundRules.INTERMISSION + 2.0)  # au-delà de l'entracte normal
	at.check(game.rounds.round_n == 2 and door.is_open, "la manche suivante attend la fin de la fenêtre")
	at.check(game.zombies.alive_count() == 0 and game.rounds.to_spawn == 0, "toujours aucun zombie")
	door.time_left = 0.5  # fin des 2 minutes (accélérée)
	await until(func(): return not door.is_open, 2.0, "fenêtre fermée au bout du temps")
	await frames(2)
	at.check(not door.is_open and not game.hud.evac_panel.visible, "fenêtre fermée, cadre de vote retiré")
	var ok: bool = await until(func(): return game.rounds.round_n == 3 and game.rounds.phase == RoundManager.Phase.ACTIVE, EvacRules.RESUME_DELAY + 2.0, "manche 3")
	at.check(ok, "la partie continue : manche 3")
	await H.clear_zombies(self)

	# ------------------------------------------------ ÉVACUER de loin, puis CONTINUER
	if not await _clear_special_wave(4):
		return
	p.teleport_to(outside)
	await frames(3)
	await _vote(EvacRules.Vote.LEAVE)
	at.check(int(door.votes.get(1, 0)) == EvacRules.Vote.LEAVE and door.is_open, "vote ÉVACUER hors de la zone : on attend l'équipe")
	at.check(GameState.state != GameState.State.GAME_OVER, "pas d'évacuation hors de la zone")
	await frames(2)
	at.check(_my_row().text == Lang.t("ÉVACUER", "EVACUATE") and game.hud.evac_panel.describe().mine == EvacRules.Vote.LEAVE,
			"cadre : ÉVACUER en face de mon nom (%s)" % str(_my_row()))
	var mk := game.hud.evac_marker
	at.check(mk.visible and mk._text.contains("%d m" % roundi(p.global_position.distance_to(door.global_position))),
			"repère de la porte : « %s »" % mk._text)
	await _vote(EvacRules.Vote.READY)
	ok = await until(func(): return not door.is_open, 2.0, "tous prêts")
	at.check(ok and GameState.state != GameState.State.GAME_OVER, "tous prêts : la partie reprend")
	ok = await until(func(): return game.rounds.round_n == 5 and game.rounds.phase == RoundManager.Phase.ACTIVE, EvacRules.RESUME_DELAY + 2.0, "manche 5")
	at.check(ok, "manche 5 aussitôt (sans attendre les 2 minutes)")
	await H.clear_zombies(self)

	# ------------------------------------------------ évacuation
	if not await _clear_special_wave(6):
		return
	p.teleport_to(inside)
	await frames(3)
	await _vote(EvacRules.Vote.LEAVE)
	ok = await until(func(): return GameState.state == GameState.State.GAME_OVER and game.last_result != null, 2.0, "évacuation")
	at.check(ok, "tous à la porte et ÉVACUER : évacuation")
	if not ok:
		return
	var r := game.last_result
	at.check(r.evacuated, "issue : évacuation réussie")
	at.check(r.round_reached == 6, "manche atteinte : %d" % r.round_reached)
	at.check(r.duration_sec > 10.0, "durée de la partie : %s" % MatchResult.time_text(r.duration_sec))
	at.check(game.hud._center_msg.text == Lang.t("ÉVACUATION RÉUSSIE", "EVACUATED"), "écran de fin : « %s »" % game.hud._center_msg.text)
	at.check(game.hud._center_sub.text.contains("6"), "manche et temps à l'écran : « %s »" % game.hud._center_sub.text)
	at.check(not door.is_open, "porte refermée")
	# XP de la partie (XpSystem) ajoutée une fois au profil : manches 2, 4 et 6
	# terminées (vagues spéciales vaincues), bonus d'évacuation.
	var l := r.xp_ledger
	var xp := ProfileStore.load_profile().xp
	at.check(int(l.rounds) == 3 and int(l.waves.get(WaveRules.SPECIAL, 0)) == 3,
			"XP : 3 manches et 3 vagues vaincues comptées (%s)" % l)
	at.check(int(l.evac_bonus) > 0 and int(l.evac_bonus) == XpRules.evac_bonus(XpRules.subtotal(l)), "bonus d'évacuation : %d" % l.evac_bonus)
	at.check(r.xp == XpRules.total(l) and xp == r.xp, "XP de l'évacuation au profil (%d, résultat %d)" % [xp, r.xp])
	# Récapitulatif du hub (retour au labo) : XP gagnée, ligne d'évacuation.
	var rc: Hub2RecapModel = H.recap()
	var evac_row := rc.rows.filter(func(row): return row.key == "evac")
	at.check(rc.gained == r.xp and rc.evacuated and evac_row.size() == 1 and int(evac_row[0].xp) == int(l.evac_bonus),
			"récapitulatif : +%d XP, évacuation réussie (%s)" % [rc.gained, rc.rows])
	await at.screenshot("evacuated")
	ProfileStore.reset()
