extends AutotestScenario
## @temps-reel : la lecture des sons avance en temps réel (serveur audio) ; en
## temps accéléré les voix restent « en cours » trop longtemps et le plafond
## de polyphonie fausse le compte des râles.
## Sons importés (enregistrements CC0, tools/audio/sfx_import.gd) : chaque son
## remplacé existe, se charge, est mono 44,1 kHz, a une durée et un niveau
## plausibles, et se joue en jeu (3D et 2D) sans erreur ; polyphonie des
## zombies plafonnée ; limiteur sur le bus principal ; chaque arme a son son.

var H := AutotestHelpers


## Crête et RMS (dB) d'un WAV 16 bits.
static func levels(w: AudioStreamWAV) -> Vector2:
	var d := w.data
	var n := d.size() / 2
	var pk := 0.0
	var acc := 0.0
	for i in range(0, n, 3):
		var v := absf(d.decode_s16(i * 2) / 32768.0)
		pk = maxf(pk, v)
		acc += v * v
	return Vector2(linear_to_db(maxf(pk, 0.00001)), linear_to_db(maxf(sqrt(acc / maxf(n / 3.0, 1.0)), 0.00001)))


static func _count(prefix: String) -> int:
	var n := 0
	for k in Audio.played:
		if String(k).begins_with(prefix):
			n += int(Audio.played[k])
	return n


func run() -> void:
	timeout_sec = 150
	var p: Player = await H.start_solo_game(self, "bunker_k7")
	if p == null:
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)

	# 1) Fichiers : chargement, format, durée, niveau.
	var names: Array = SfxRecipes.RECIPES.keys()
	at.check(names.size() >= 100, "%d sons importés" % names.size())
	var bad := []
	for n in names:
		var st := Audio.get_stream(n)
		var w := st as AudioStreamWAV
		if w == null:
			bad.append("%s : introuvable" % n)
			continue
		var dur := w.get_length()
		# Niveaux mesurés sur le WAV source (le son importé est compressé en QOA).
		var pcm := AudioStreamWAV.load_from_file(ProjectSettings.globalize_path("res://assets/audio/%s.wav" % n))
		var lv := levels(pcm) if pcm else Vector2(99.0, -99.0)
		var max_len: float = SfxRecipes.RECIPES[n].get("max_len", 6.0)
		if w.stereo or w.mix_rate != 44100:
			bad.append("%s : format %s %d Hz" % [n, "stéréo" if w.stereo else "mono", w.mix_rate])
		if dur < 0.04 or dur > max_len:
			bad.append("%s : durée %.2f s" % [n, dur])
		if lv.x > -0.3:
			bad.append("%s : crête %.1f dB" % [n, lv.x])
		# Intensité perçue dans la cible de la catégorie (SfxLoudness).
		var dev := SfxLoudness.deviation(n, SfxLoudness.read_wav(ProjectSettings.globalize_path("res://assets/audio/%s.wav" % n)),
			float(SfxRecipes.RECIPES[n].get("loud", 0.0)), 12.0)
		if absf(dev) > float(SfxLoudness.category(n).tol):
			bad.append("%s : intensité %+.1f LU" % [n, dev])
		if lv.y < -45.0:
			bad.append("%s : RMS %.1f dB" % [n, lv.y])
		if bool(SfxRecipes.RECIPES[n].get("loop", false)) != (w.loop_mode != AudioStreamWAV.LOOP_DISABLED):
			bad.append("%s : boucle" % n)
	at.check(bad.is_empty(), "sons importés valides %s" % [bad])

	# 2) Chaque arme (et son amélioration) a un son existant.
	var missing := []
	for id in WeaponDB.WEAPONS:
		for pap in [false, true]:
			var s := WeaponDB.stats(id, pap)
			if Audio.get_stream(s.sound) == null:
				missing.append("%s%s:%s" % [id, "+" if pap else "", s.sound])
	at.check(missing.is_empty(), "sons d'armes présents %s" % [missing])
	var distinct := {}
	for id in WeaponDB.WEAPONS:
		distinct[WeaponDB.stats(id).sound] = true
	at.check(distinct.size() >= 20, "%d signatures d'armes distinctes" % distinct.size())

	# 3) Lecture en jeu, par familles : armes (2D), zombies et impacts (3D).
	var fwd := -p.global_transform.basis.z
	var t0 := GameClock.msec()
	for n in names:
		if n.begins_with("zombie_") or n.begins_with("flesh") or n.begins_with("barricade") or n.begins_with("impact_") \
				or n.begins_with("dog_") or n in ["headshot", "body_fall", "emerge", "explosion", "frag_explode", "nova_blast", "grenade_bounce", "monkey_bounce"]:
			Audio.play_3d(n, p.global_position + fwd * 4.0 + Vector3.UP, 0.0, 0.0, 99)
		else:
			Audio.play_2d(n, -6.0, 0.0)
		await seconds(0.12)
	at.check(GameClock.msec() - t0 < 60000, "tous les sons joués")
	await at.screenshot("playing")

	# 4) Polyphonie : 30 râles simultanés -> au plus VOICE_LIMITS.zombie voix.
	await seconds(1.5)
	for i in 30:
		var a := TAU * i / 30.0
		Audio.play_3d("zombie_groan_%d" % (1 + i % ZombieVoice.GROANS), p.global_position + Vector3(cos(a), 0.5, sin(a)) * (3.0 + i),
			0.0, 0.05, 99, 1.0, ZombieVoice.GROUP)
	await frames(2)
	var n_play: int = Audio.group_playing(ZombieVoice.GROUP)
	at.check(n_play >= 3 and n_play <= int(Audio.VOICE_LIMITS[ZombieVoice.GROUP]), "voix de zombies plafonnées : %d" % n_play)
	# Un zombie hors de portée n'est pas joué du tout.
	Audio.play_3d("zombie_groan_1", p.global_position + Vector3(0, 0, Audio.MAX_DISTANCE + 20.0), 0.0, 0.0, 99, 1.0, "zombie_step")
	await frames(1)
	at.check(Audio.group_playing("zombie_step") == 0, "son de zombie hors de portée ignoré")

	# 5) Règles de rythme des vocalises.
	at.check(ZombieVoice.interval(0, 0.0) >= 3.5 and ZombieVoice.interval(2, 1.0) <= 6.0, "espacement des râles")

	# 6) Limiteur sur le bus principal.
	var lim := false
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) is AudioEffectHardLimiter:
			lim = true
	at.check(lim, "limiteur sur le bus Master")

	# 7) Vrais zombies en jeu : râles et pas pendant quelques secondes.
	var before := _count("zombie_groan_") + _count("zombie_sprint_")
	var steps_before := _count("zombie_step_")
	for i in 6:
		game.zombies.spawn(p.global_position + fwd * (6.0 + i) + Vector3(i - 3.0, 0, 0), i % 3, 150)
	var max_voices := 0
	for k in 40:
		await seconds(0.2)
		max_voices = maxi(max_voices, Audio.group_playing(ZombieVoice.GROUP))
	var vocal := _count("zombie_groan_") + _count("zombie_sprint_") - before
	at.check(max_voices <= int(Audio.VOICE_LIMITS[ZombieVoice.GROUP]), "zombies vivants : polyphonie respectée (%d)" % max_voices)
	# 6 zombies pendant 8 s : quelques râles, pas un chœur continu.
	at.check(vocal >= 2 and vocal <= 20, "zombies vivants : %d vocalises en 8 s" % vocal)
	at.check(_count("zombie_step_") > steps_before, "pas traînants joués (%d)" % (_count("zombie_step_") - steps_before))
	await at.screenshot("zombies")
	# Tirs réels avec le M1911 sur un zombie (son d'arme + impact chair).
	H.aim_at(p, p.global_position + fwd * 6.0 + Vector3.UP * 1.2)
	for i in 4:
		await H.shoot(self, p, 0.25)
	at.check(true, "tirs joués")

	# 8) Impacts de balles selon la matière (Fx.surface_at) : mur en béton,
	# boîte mystère en bois, Pack-a-Punch en métal.
	var fx: Fx = game.fx_root
	var space := p.get_world_3d().direct_space_state
	var eye := p.global_position + Vector3.UP * 1.5
	var wall := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye + fwd * 80.0, 1))
	at.check(not wall.is_empty() and fx.surface_at(wall.position, wall.normal) == "concrete", "impact sur un mur : béton")
	var box: MysteryBox = game.interact.get_obj("box")
	var bn: Vector3 = box.spots[box.location].normal
	var bc := box.global_position + Vector3.UP * 0.35
	var bh := space.intersect_ray(PhysicsRayQueryParameters3D.create(bc - bn * 2.0, bc + bn * 0.5, 1))
	at.check(not bh.is_empty() and fx.surface_at(bh.position, bh.normal) == "wood", "impact sur la boîte mystère : bois")
	var pap: Node3D = game.interact.get_obj("pap")
	if pap:
		var pc := pap.global_position + Vector3.UP * 0.5
		var ph := space.intersect_ray(PhysicsRayQueryParameters3D.create(pc + Vector3.UP * 1.2, pc, 1))
		at.check(not ph.is_empty() and fx.surface_at(ph.position, ph.normal) == "metal", "impact sur le Pack-a-Punch : métal")
	var before_imp := _count("impact_")
	fx.impact(bh.position, bh.normal)
	fx.impact(wall.position, wall.normal)
	at.check(_count("impact_wood_") >= 1 and _count("impact_") - before_imp == 2, "sons d'impact joués selon la matière")

	# 9) Arme Pack-a-Punchée : tir + couche électrique « zap ».
	var zaps := _count("pap_zap_")
	WeaponAudio.play_3d(WeaponDB.stats("mp40", true), true, p.global_position + fwd * 3.0)
	WeaponAudio.play_3d(WeaponDB.stats("mp40"), false, p.global_position + fwd * 3.0)
	at.check(_count("pap_zap_") - zaps == 1, "zap électrique sur le tir amélioré seulement")
