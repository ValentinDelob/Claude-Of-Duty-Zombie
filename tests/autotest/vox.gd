extends AutotestScenario
## Répliques des personnages : le personnage du joueur (rotation 0 en test :
## Callahan), une réplique déclenchée par le jeu (atout bu, joueur à terre),
## jouée en 2D pour soi, dans la langue choisie, sans répétition immédiate.

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 60
	var p: Player = await H.start_solo_game(self)
	if p == null:
		return
	var game := Game.instance
	game.rounds.paused = true
	for zid in game.zombies.zombies.keys():
		game.zombies.despawn(zid)
	at.check(game.vox != null, "système de répliques en jeu")
	at.check(CharacterDB.id_of(1) == "callahan", "solo en test : Callahan")
	var heard: Array = []
	game.vox.said.connect(func(pid, cat, v): heard.append([pid, cat, v]))
	var before := Settings.language
	Settings.language = "fr"
	# Atout bu : réplique après l'animation de la boisson.
	game.perks.srv_grant(1, "titan")
	await until(func(): return heard.any(func(h): return h[1] == "perk_titan"), 5.0, "réplique de l'atout")
	at.check(game.vox._self_voice.playing, "réplique jouée en 2D pour le joueur local")
	var stream_fr: AudioStream = game.vox._self_voice.stream
	at.check(stream_fr != null and stream_fr.resource_path.contains("/fr/callahan/perk_titan_"), "voix française de Callahan (%s)" % (stream_fr.resource_path if stream_fr else ""))
	# Délai par situation : pas deux fois de suite la même réplique.
	at.check(not game.vox.srv_say(1, "perk_titan"), "même situation : attendre avant de la redire")
	# Langue anglaise (voix anglaises en cours de génération : seulement si le
	# fichier tiré existe, sinon la réplique reste muette sans erreur).
	Settings.language = "en"
	await seconds(2.5)
	heard.clear()
	at.check(game.vox.srv_say(1, "round_start"), "réplique de début de manche")
	await frames(3)
	var v: int = heard[0][2] if not heard.is_empty() else -1
	if ResourceLoader.exists(CharacterDB.vox_path("en", "callahan", "round_start", v)):
		var stream_en: AudioStream = game.vox._self_voice.stream
		at.check(stream_en != null and stream_en.resource_path.contains("/en/callahan/round_start_"), "voix anglaise (%s)" % (stream_en.resource_path if stream_en else ""))
	# Joueur à terre : réplique prioritaire, même juste après une autre.
	heard.clear()
	game.combat.damage_player(1, 400, p.global_position + Vector3(1, 1, 0))
	await until(func(): return heard.any(func(h): return h[1] == "downed"), 3.0, "réplique à terre")
	Settings.language = before
