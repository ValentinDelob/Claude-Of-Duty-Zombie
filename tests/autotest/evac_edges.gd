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


## Appui sur [F] en visant la porte (vote).
func _vote() -> void:
	H.aim_at(p, door.interact_point())
	await until(func(): return game.interact.focused == door, 2.0, "porte visée")
	var before: int = door.votes.get(1, EvacRules.Vote.NONE)
	p.input.interact_pressed = true
	await until(func(): return int(door.votes.get(1, EvacRules.Vote.NONE)) != before or not door.is_open, 2.0, "vote reçu")


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
	# Carte avec un boss (aucun n'existe encore : la vague reste une manche de
	# zombies), vague de boss en manche 2, aucune vague spéciale.
	game.map_def.boss = "test_boss"
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
	# « partir » hors de la zone puis « prêt » : tous prêts, la partie reprend.
	p.teleport_to(outside)
	await frames(3)
	await _vote()
	await _vote()
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
	# Un coéquipier (sans corps, loin de la porte) vote « prêt » puis s'en va.
	const GONE := 4242
	game.session.data[GONE] = PlayerData.new(GONE)
	door.srv_use(GONE)
	door.srv_use(GONE)
	at.check(int(door.votes.get(GONE, 0)) == EvacRules.Vote.READY, "vote du coéquipier enregistré")
	p.teleport_to(inside)
	await frames(3)
	await _vote()
	await seconds(0.5)
	at.check(door.is_open and GameState.state != GameState.State.GAME_OVER, "coéquipier loin de la porte : on l'attend")
	at.check(game.hud.evac_status().contains(Lang.t("Partir 1/2", "Leave 1/2")) and game.hud.evac_status().contains(Lang.t("vous : PARTIR", "you: LEAVE")),
			"bandeau : votes à jour « %s »" % game.hud.evac_status())
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
