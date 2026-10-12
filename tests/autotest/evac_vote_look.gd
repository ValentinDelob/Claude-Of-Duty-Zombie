extends AutotestScenario
## @rendu : vote d'évacuation (maquette docs/hub_v2/Evacuation.dc.html),
## capture de la fonction en cours, à retirer une fois validée. Arène de
## test, équipe de trois (deux coéquipiers ajoutés pour l'affichage : Mehdi
## ÉVACUER, Sarah_K CONTINUER), fenêtre ouverte à 1:42 (barre à 85 %) :
## cadre à gauche sans vote (EN ATTENTE), puis ÉVACUER (repère « ÉVACUATION ·
## N m » au-dessus de la porte), CONTINUER, en anglais, touches de la manette,
## et repère collé au bord quand la porte est hors de l'écran.

var H := AutotestHelpers
var game: Game
var p: Player
var door: EvacDoor

const MEHDI := 2001
const SARAH := 2002


## Temps de la maquette (1:42) figé pendant la capture.
func _freeze_at_1_42() -> void:
	door.time_left = 101.5
	door.set_process(false)


func run() -> void:
	timeout_sec = 90
	var lang0 := String(Settings.language)
	Settings.language = "fr"
	ProfileStore.reset()
	p = await H.start_solo_game(self, "test_arena")
	if p == null:
		return
	game = Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	door = game.evac
	var me := p.peer_id
	var name0: String = Net.players.get(me, {}).get("name", "")
	Net.players[me]["name"] = "Valentin"
	# Vague spéciale vaincue : la porte s'ouvre.
	game.map_def.waves = WaveRules.parse({"speciale": {"premiere": 0, "intervalle": 0}})
	game.rounds.paused = false
	var dogs := game.rounds.dogs
	dogs.debug_force_next(2)
	game.rounds.debug_jump_to(2)
	if not await until(func(): return dogs.active, 2.0, "vague spéciale"):
		return
	dogs.spawned = dogs.total
	if not await until(func(): return door.is_open, 3.0, "porte ouverte"):
		return
	# Coéquipiers pour l'affichage seulement (ni corps ni connexion).
	for t in [[MEHDI, "Mehdi", 1], [SARAH, "Sarah_K", 2]]:
		Net.players[t[0]] = {"name": t[1], "slot": t[2]}
		game.session.data[t[0]] = PlayerData.new(t[0])
	door.srv_vote(MEHDI, EvacRules.Vote.LEAVE)
	door.srv_vote(SARAH, EvacRules.Vote.READY)
	# Face à la porte, à une quinzaine de mètres (maquette : 18 m).
	var far := door.global_position + door.global_basis.z * 15.0 + Vector3.UP * 0.05
	p.teleport_to(far)
	await frames(3)
	H.aim_at(p, door.global_position + Vector3.UP * 1.4)
	_freeze_at_1_42()
	await seconds(4.5)  # bandeau de la vague (« LA MEUTE APPROCHE ») effacé, rendu posé
	var panel := game.hud.evac_panel
	var d := panel.describe()
	at.check(d.visible and d.clock == "1:42" and d.rows.size() == 3, "cadre : %s" % str(d))
	at.check(d.rows[0].name == "Valentin (toi)" and d.rows[0].text == "EN ATTENTE"
			and d.rows[1].text == "ÉVACUER" and d.rows[2].text == "CONTINUER", "lignes de la maquette")
	at.check(panel.position == Vector2(24, 150) and panel.size.x == 304.0, "position et largeur (%s, %s)" % [panel.position, panel.size])
	await at.screenshot("attente")

	door.set_process(true)
	await H.evac_vote(self, p, EvacRules.Vote.LEAVE)
	_freeze_at_1_42()
	await seconds(0.4)
	var mk := game.hud.evac_marker
	at.check(mk.visible and mk.placed.get("on_screen", false), "repère au-dessus de la porte : « %s »" % mk._text)
	await at.screenshot("evacuer")

	door.set_process(true)
	await H.evac_vote(self, p, EvacRules.Vote.READY)
	_freeze_at_1_42()
	await seconds(0.3)
	at.check(not mk.visible, "CONTINUER : plus de repère")
	await at.screenshot("continuer")

	door.set_process(true)
	await H.evac_vote(self, p, EvacRules.Vote.LEAVE)
	_freeze_at_1_42()
	Settings.language = "en"
	Settings.using_pad = true
	await seconds(0.3)
	at.check(panel.describe().rows[0].name == "Valentin (you)", "anglais : (you)")
	await at.screenshot("en_manette")
	Settings.using_pad = false

	# Porte derrière le joueur : repère collé au bord, flèche vers la porte.
	Settings.language = "fr"
	p.yaw += PI * 0.75
	p.rotation.y = p.yaw
	await seconds(0.3)
	at.check(mk.visible and not mk.placed.get("on_screen", true), "porte hors de l'écran : repère au bord (%s)" % str(mk.placed))
	await at.screenshot("repere_bord")

	# Remise en état.
	door.set_process(true)
	Settings.language = lang0
	Net.players[me]["name"] = name0
	for id in [MEHDI, SARAH]:
		Net.players.erase(id)
		game.session.data.erase(id)
	ProfileStore.reset()
