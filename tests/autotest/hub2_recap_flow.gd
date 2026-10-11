extends AutotestScenario
## Fin de partie -> récapitulatif du hub v2 (Recap.dc.html), en vrai, hub v2
## activé (réglage caché) :
## 1. carte du jeu (arène de test) : XP gagnée (éliminations, manches),
##    échantillons, évacuation -> écran de fin SANS le rapport d'XP et de
##    butin (il passe au hub), retour au menu sur le RÉCAPITULATIF : XP
##    gagnée = profil, niveau, détail, butin gardé ; A termine l'animation,
##    A de nouveau : LABO ; le profil a l'XP, les échantillons, le codex, et
##    le tableau des contrats a tourné ;
## 2. carte perso (copie de SMALLEST dans le dossier des cartes de test) :
##    même partie -> AUCUNE progression (GAME_CONCEPT §4.20) : ni XP, ni
##    échantillons, ni codex, ni contrats ; compteur d'XP de partie masqué ;
##    récapitulatif « +0 XP », POUR LE FUN, BUTIN NON GARDÉ.

const SMALLEST := "res://tests/fixtures/maps/smallest"
const CUSTOM_ID := "recap_custom"

var H := AutotestHelpers
var SW := preload("res://tests/autotest/smallest_window.gd")


func run() -> void:
	timeout_sec = 120
	ProfileStore.reset()
	Settings.hub_v2 = true
	Router.last_match = {}
	# 1. Carte du jeu.
	var before := ProfileStore.load_profile()
	var rot0 := before.contracts.rotation
	if not await _play("test_arena", true):
		return
	var pr := ProfileStore.load_profile()
	at.check(pr.xp > 0, "XP au profil (%d)" % pr.xp)
	at.check(pr.sample_count("dog_fang") == 2, "échantillons gardés (%d)" % pr.sample_count("dog_fang"))
	at.check(pr.codex.kills("walker") == 4, "codex : 4 marcheurs (%d)" % pr.codex.kills("walker"))
	at.check(pr.contracts.rotation > rot0, "contrats : le tableau a tourné (%d -> %d)" % [rot0, pr.contracts.rotation])
	# 2. Carte perso : aucune progression.
	var dir := SW.install_fixture(CUSTOM_ID, SMALLEST)
	at.check(dir != "", "carte perso installée (%s)" % dir)
	var xp0 := pr.xp
	var rot1 := pr.contracts.rotation
	if not await _play(EditorMapDef.CUSTOM_PREFIX + CUSTOM_ID, false):
		return
	var pr2 := ProfileStore.load_profile()
	at.check(pr2.xp == xp0, "carte perso : XP inchangée (%d -> %d)" % [xp0, pr2.xp])
	at.check(pr2.sample_count("dog_fang") == 2, "carte perso : échantillons non gardés (%d)" % pr2.sample_count("dog_fang"))
	at.check(pr2.codex.kills("walker") == 4, "carte perso : codex inchangé (%d)" % pr2.codex.kills("walker"))
	at.check(pr2.contracts.rotation == rot1, "carte perso : contrats inchangés (%d)" % pr2.contracts.rotation)
	Settings.hub_v2 = false
	Router.last_match = {}
	ProfileStore.reset()
	SW.remove_dir(EditorMap.maps_root())


## Une partie sur `map_id` : 4 marcheurs tués (relevé du serveur), 3
## manches, 2 crocs, évacuation ; puis le récapitulatif. Vrai si tout a suivi.
func _play(map_id: String, progress: bool) -> bool:
	var p := await H.start_solo_game(self, map_id)
	if p == null:
		return false
	var game := Game.instance
	at.check(game.progress == progress, "%s : progression %s" % [map_id, progress])
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	var l := game.xp.ledger(1)
	for i in 4:
		game.xp._send(1, XpRules.add_kill(l, XpRules.WALKER, 3), XpSystem.SRC_KILL)
	XpRules.add_met(l, XpRules.WALKER)
	game.rounds.round_n = 3
	game.loot.my_samples["dog_fang"] = 2
	await frames(3)
	if progress:
		at.check(game.xp.counter_shown() != "", "compteur d'XP de partie : %s" % game.xp.counter_shown())
	else:
		at.check(game.xp.counter_shown() == "" and game.xp.pop_shown() == "", "carte perso : aucun compteur d'XP")
	game.srv_end_match(true)
	await until(func(): return game.last_result != null, 3.0, "fin de partie")
	var r := game.last_result
	at.check(game.hud.xp_report_text() == "" and game.hud.loot_report() == "", "hub v2 : pas de rapport d'XP ni de butin à l'écran de fin")
	at.check(Router.last_match.get("progress", true) == progress, "Router.last_match : progression %s" % progress)
	if not await until(_in_hub2, 30.0, "retour au hub v2"):
		return false
	var menu: MainMenu = tree().current_scene
	var hub: Hub2Screen = menu.current
	at.check(hub.current_id == "recap", "retour : récapitulatif (%s)" % hub.current_id)
	var rp: Hub2RecapPanel = hub.panels.get("recap")
	if rp == null:
		return false
	at.check(rp.model.gained == (r.xp if progress else 0), "récapitulatif : +%d XP (partie : %d)" % [rp.model.gained, r.xp])
	at.check(rp.model.evacuated and rp.model.round_reached == 3, "ÉVACUÉ, manche 3")
	if progress:
		at.check(r.xp > 0 and not rp.model.rows.is_empty() and rp.model.rows[0].key == "kills", "détail : zombies éliminés")
		at.check(rp.model.loot_title() == "BUTIN GARDÉ", rp.model.loot_title())
	else:
		at.check(r.xp == 0 and rp.model.rows.is_empty(), "carte perso : pas d'XP")
		at.check(rp.model.loot_title() == "BUTIN NON GARDÉ" and rp.model.outcome()[0] == "POUR LE FUN", rp.model.loot_title())
	await until(func(): return menu.current.modulate.a >= 0.999, 3.0, "hub affiché")
	at.check(rp.animating(), "animation de l'XP en cours")
	await _accept()
	await frames(3)
	at.check(not rp.animating(), "A : animation terminée d'un coup")
	at.check(hub.current_id == "recap", "A pendant l'animation : on reste sur le récapitulatif")
	await _accept()
	await frames(3)
	at.check(hub.current_id == "lab", "A : CONTINUER -> LABO (%s)" % hub.current_id)
	return true


func _in_hub2() -> bool:
	var s := tree().current_scene
	return s is MainMenu and (s as MainMenu).current is Hub2Screen


func _accept() -> void:
	var ev := InputEventAction.new()
	ev.action = "ui_accept"
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(2)
	var up := InputEventAction.new()
	up.action = "ui_accept"
	up.pressed = false
	Input.parse_input_event(up)
