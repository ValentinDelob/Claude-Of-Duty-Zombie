class_name AutotestHelpers
extends RefCounted
## Fonctions partagées par les scénarios.


## Lance une partie solo et attend que le joueur local soit en jeu.
static func start_solo_game(sc: AutotestScenario) -> Player:
	await sc.until(func(): return sc.tree().current_scene != null and sc.tree().current_scene.name == "MainMenu", 5.0, "menu")
	Router.start_solo()
	var ok: bool = await sc.until(func(): return Game.instance != null and Game.instance.local_player != null, 10.0, "joueur local en jeu")
	if not ok:
		return null
	var p := Game.instance.local_player
	p.bot_controlled = true
	await sc.frames(5)
	return p
