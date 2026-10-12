extends AutotestScenario
## Cas limites de l'évacuation (GAME_CONCEPT.md §4.5) sur l'arène de test :
## vague de BOSS vaincue -> la porte s'ouvre aussi (une seule fois par vague,
## aucun zombie, la manche suivante attend) ; joueur absent (parti pendant la
## fenêtre) : son vote est oublié et l'équipe ne l'attend pas ; fin des
## 2 minutes à l'instant même où l'équipe est prête à partir : évacuation ;
## fin de partie appliquée une seule fois (XP), même message reçu deux fois.

var H := AutotestHelpers
var game: Game
var p: Player
var door: EvacDoor


## Vote de n'importe où (F1 : CONTINUER, F2 : ÉVACUER).
func _vote(v: int) -> void:
	await H.evac_vote(self, p, v)


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
	if door == null:
		at.fail("porte d'évacuation absente")
		return
	var inside := door.global_position + door.global_basis.z * 1.5 + Vector3.UP * 0.05
	var outside := door.global_position + door.global_basis.x * 2.4 + door.global_basis.z * 1.0 + Vector3.UP * 0.05

	# ------------------------------------------------ vague de boss
	# Vague de boss en manche 2, aucune vague spéciale ; le Chirurgien est
	# coupé en autotest (SurgeonRound.enabled) : la vague reste une manche de
	# zombies, comptée vague de boss.
	game.map_def.waves = WaveRules.parse({"speciale": {"premiere": 0, "intervalle": 0}, "boss": {"premiere": 2, "intervalle": 0}})
	game.rounds.dogs.next_dog_round = 0
	game.rounds.paused = false
	game.rounds.debug_jump_to(2)
	at.check(game.rounds.wave == WaveRules.BOSS, "manche 2 : vague de boss (%s)" % game.rounds.wave)
	game.rounds.to_spawn = 0
	await H.clear_zombies(self)
	var ok: bool = await until(func(): return door.is_open, 3.0, "porte ouverte après la vague de boss")
	at.check(ok, "vague de boss vaincue : porte d'évacuation ouverte")
	if not ok:
		return
	await seconds(RoundRules.INTERMISSION + 1.0)
	at.check(game.rounds.round_n == 2 and door.is_open, "la manche suivante attend la fin de la fenêtre")
	at.check(game.zombies.alive_count() == 0 and game.rounds.to_spawn == 0, "aucun zombie pendant la fenêtre")
	# ÉVACUER hors de la zone puis CONTINUER : tous prêts, la partie reprend.
	p.teleport_to(outside)
	await frames(3)
	await _vote(EvacRules.Vote.LEAVE)
	await _vote(EvacRules.Vote.READY)
	ok = await until(func(): return not door.is_open, 2.0, "fenêtre fermée (tous prêts)")
	at.check(ok, "tous prêts : fenêtre fermée")
	# Vague déjà vaincue : pas de seconde ouverture dans la même manche.
	door.srv_open()
	await frames(2)
	at.check(not door.is_open, "une seule ouverture par vague")
	ok = await until(func(): return game.rounds.round_n == 3 and game.rounds.phase == RoundManager.Phase.ACTIVE, EvacRules.RESUME_DELAY + 2.0, "manche 3")
	at.check(ok, "la partie reprend : manche 3")
	game.rounds.to_spawn = 0
	await H.clear_zombies(self)
	await until(func(): return game.rounds.phase == RoundManager.Phase.INTERMISSION, 3.0, "fin de la manche 3")
	at.check(not door.is_open, "manche normale vaincue : porte fermée")

	# ------------------------------------------------ joueur parti pendant la fenêtre
	var dogs := game.rounds.dogs
	dogs.debug_force_next(4)
	game.rounds.debug_jump_to(4)
	if not await until(func(): return dogs.active and game.rounds.round_n == 4, 2.0, "vague spéciale 4"):
		return
	dogs.spawned = dogs.total
	if not await until(func(): return door.is_open, 3.0, "porte ouverte après la vague 4"):
		return
	# Un coéquipier (sans corps, loin de la porte) vote CONTINUER puis s'en va.
	# Votes refusés : « en attente » (pas un choix), valeur inconnue, mort.
	const GONE := 4242
	const GHOST := 4343
	game.session.data[GONE] = PlayerData.new(GONE)
	at.check(not door.srv_vote(GONE, EvacRules.Vote.NONE) and not door.srv_vote(GONE, 7) and not door.votes.has(GONE),
			"EN ATTENTE ne se choisit pas, valeur inconnue refusée")
	at.check(not door.srv_vote(GHOST, EvacRules.Vote.READY), "joueur inconnu : refusé")
	var ghost := PlayerData.new(GHOST)
	ghost.life = PlayerData.Life.DEAD
	game.session.data[GHOST] = ghost
	at.check(not door.srv_vote(GHOST, EvacRules.Vote.READY), "mort (spectateur) : ne vote pas")
	game.session.data.erase(GHOST)
	door.srv_vote(GONE, EvacRules.Vote.LEAVE)
	at.check(door.srv_vote(GONE, EvacRules.Vote.READY) and not door.srv_vote(GONE, EvacRules.Vote.READY),
			"l'autre touche change le vote ; le même vote ne change rien")
	at.check(int(door.votes.get(GONE, 0)) == EvacRules.Vote.READY, "vote du coéquipier enregistré")
	p.teleport_to(inside)
	await frames(3)
	await _vote(EvacRules.Vote.LEAVE)
	await seconds(0.5)
	at.check(door.is_open and GameState.state != GameState.State.GAME_OVER, "coéquipier loin de la porte : on l'attend")
	var rows: Array = game.hud.evac_panel.describe().rows
	at.check(rows.size() == 2 and rows[0].me and rows[0].vote == EvacRules.Vote.LEAVE and rows[1].vote == EvacRules.Vote.READY
			and rows[1].text == Lang.t("CONTINUER", "CONTINUE"), "cadre : votes à jour %s" % str(rows))
	# Il se déconnecte, et les 2 minutes s'achèvent à cet instant : l'équipe
	# restante est prête et à la porte, elle part (l'évacuation passe avant).
	game._cl_remove_player(GONE)
	door.time_left = 0.0
	ok = await until(func(): return GameState.state == GameState.State.GAME_OVER and game.last_result != null, 2.0, "évacuation")
	at.check(ok and game.last_result.evacuated, "parti pendant la fenêtre : l'équipe restante s'évacue")
	if not ok:
		return
	at.check(not door.votes.has(GONE), "vote de l'absent oublié")
	at.check(not door.is_open, "porte refermée")
	var r := game.last_result
	at.check(r.round_reached == 4, "manche atteinte : %d" % r.round_reached)
	var xp := ProfileStore.load_profile().xp
	at.check(xp == r.xp and r.xp > 0, "XP ajoutée une fois (%d)" % xp)
	# Même fin de partie reçue une seconde fois, nouvelle demande de fin : rien
	# n'est compté deux fois.
	game._cl_match_end(r.to_dict())
	game.srv_end_match(true)
	await frames(3)
	at.check(ProfileStore.load_profile().xp == xp, "fin reçue deux fois : XP inchangée (%d)" % ProfileStore.load_profile().xp)
	ProfileStore.reset()
