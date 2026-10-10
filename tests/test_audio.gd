extends TestCase
## Sons : recettes d'import CC0 (sources, licences, fichiers, documentation),
## exclusion du générateur procédural, intensité perçue par catégorie
## (SfxLoudness), couche électrique des armes améliorées, rythme et variété
## des vocalises des zombies.

## Sons qui étaient encore procéduraux et doivent être des enregistrements CC0.
const MUST_BE_CC0 := ["break_open", "break_close", "impact_concrete_1", "impact_concrete_2", "impact_metal_1",
	"impact_metal_2", "impact_wood_1", "impact_wood_2", "grenade_pin", "grenade_throw", "grenade_bounce",
	"monkey_wind", "monkey_bounce", "monkey_music", "dog_growl_1", "dog_growl_2", "dog_growl_3", "dog_bark_1",
	"dog_bark_2", "dog_bite_1", "dog_bite_2", "dog_whine", "dog_explode", "footstep_1", "footstep_2",
	"footstep_3", "footstep_4", "player_breath_1", "player_breath_2", "player_hurt_1", "player_hurt_2",
	"player_down", "dive_land", "minigun_fire", "thunder_fire", "thunder_charge", "nova_blast",
	"pap_zap_1", "pap_zap_2", "pap_zap_3"]


func test_recipes_have_sources() -> void:
	var used := {}
	for n in SfxRecipes.RECIPES:
		var r: Dictionary = SfxRecipes.RECIPES[n]
		assert_true(r.has("layers") and not r.layers.is_empty(), "%s : couches" % n)
		assert_true(r.get("preset", "") == "" or SfxRecipes.PRESETS.has(r.preset), "%s : préréglage" % n)
		var recorded := false
		for l in r.layers:
			if l.has("stem"):
				assert_true(l.stem in ["monkey_tune"], "%s : piste procédurale connue" % n)
				continue
			recorded = true
			used[l.src] = true
			assert_true(SfxRecipes.SOURCES.has(l.src), "%s : source %s documentée" % [n, l.src])
		assert_true(recorded, "%s : au moins un enregistrement CC0" % n)
	for id in SfxRecipes.SOURCES:
		var s: Dictionary = SfxRecipes.SOURCES[id]
		assert_true(String(s.url).begins_with("https://cdn.freesound.org/previews/%s/%s_" % [id.substr(0, id.length() - 3), id]), "%s : url" % id)
		assert_true(String(s.author) != "" and String(s.title) != "", "%s : auteur et titre" % id)
		assert_true(used.has(id), "%s : source utilisée par une recette" % id)


func test_replaced_sounds_are_cc0() -> void:
	for n in MUST_BE_CC0:
		assert_true(SfxRecipes.RECIPES.has(n), "%s : enregistrement CC0" % n)
	# Plus d'ancien impact procédural unique.
	assert_false(ResourceLoader.exists("res://assets/audio/impact_concrete.wav"), "impact_concrete remplacé par des variantes")


## docs/ASSETS.md liste chaque son importé et chaque source (lien freesound).
func test_assets_doc_lists_everything() -> void:
	var doc := FileAccess.get_file_as_string("res://docs/ASSETS.md")
	assert_true(doc != "", "docs/ASSETS.md lisible")
	for n in SfxRecipes.RECIPES:
		assert_true(doc.contains("`%s.wav`" % n), "ASSETS.md : %s" % n)
	for id in SfxRecipes.SOURCES:
		assert_true(doc.contains("https://freesound.org/s/%s/" % id), "ASSETS.md : source %s" % id)


func test_imported_files_exist() -> void:
	for n in SfxRecipes.RECIPES:
		assert_true(ResourceLoader.exists("res://assets/audio/%s.wav" % n), "%s.wav présent" % n)


func test_generator_skips_replaced() -> void:
	var gen: GDScript = load("res://tools/gen_audio.gd")
	assert_true(gen.replaced("zombie_groan_1"), "râle importé exclu")
	assert_true(gen.replaced("m1911_fire"), "tir importé exclu")
	assert_true(gen.replaced("monkey_music"), "singe importé exclu")
	assert_true(gen.replaced("dog_growl_2"), "chien importé exclu")
	assert_false(gen.replaced("ray_fire"), "son procédural conservé")
	assert_false(gen.replaced("announce_max_ammo"), "annonce procédurale conservée")


func test_zombie_variants_exist() -> void:
	for i in range(1, ZombieVoice.GROANS + 1):
		assert_true(SfxRecipes.RECIPES.has("zombie_groan_%d" % i))
	for i in range(1, ZombieVoice.SPRINTS + 1):
		assert_true(SfxRecipes.RECIPES.has("zombie_sprint_%d" % i))
	for i in range(1, ZombieVoice.ATTACKS + 1):
		assert_true(SfxRecipes.RECIPES.has("zombie_attack_%d" % i))
	for i in range(1, ZombieVoice.DEATHS + 1):
		assert_true(SfxRecipes.RECIPES.has("zombie_death_%d" % i))
	for i in range(1, ZombieVoice.STEPS + 1):
		assert_true(SfxRecipes.RECIPES.has("zombie_step_%d" % i))


func test_voice_pick_never_repeats() -> void:
	for last in range(0, ZombieVoice.GROANS + 1):
		for roll in 40:
			var v := ZombieVoice.pick(ZombieVoice.GROANS, last, roll)
			assert_true(v >= 1 and v <= ZombieVoice.GROANS, "variante dans les bornes")
			assert_true(v != last, "pas deux fois la même variante")
	assert_eq(ZombieVoice.pick(1, 1, 5), 1)
	# Toutes les variantes finissent par sortir.
	var seen := {}
	var last := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for roll in 200:
		last = ZombieVoice.pick(ZombieVoice.GROANS, last, rng.randi())
		seen[last] = true
	assert_eq(seen.size(), ZombieVoice.GROANS, "toutes les variantes jouées")


func test_voice_rhythm() -> void:
	# Marcheurs : râles espacés ; coureurs : plus fréquents, jamais du spam.
	assert_true(ZombieVoice.interval(0, 0.0) >= 3.5)
	assert_true(ZombieVoice.interval(1, 1.0) <= 10.0)
	assert_true(ZombieVoice.interval(2, 0.0) >= 2.0)
	assert_true(ZombieVoice.interval(3, 1.0) < ZombieVoice.interval(0, 1.0))
	assert_eq(ZombieVoice.vocal_name(0, 3), "zombie_groan_3")
	assert_eq(ZombieVoice.vocal_name(2, 2), "zombie_sprint_2")
	assert_eq(ZombieVoice.vocal_count(3), ZombieVoice.SPRINTS)


func test_every_weapon_has_own_family_sound() -> void:
	var seen := {}
	for id in WeaponDB.WEAPONS:
		var snd: String = WeaponDB.stats(id).sound
		assert_true(ResourceLoader.exists("res://assets/audio/%s.wav" % snd), "%s : %s" % [id, snd])
		seen[snd] = true
	assert_true(seen.size() >= 20, "au moins 20 signatures d'armes (%d)" % seen.size())


# ---------------------------------------------------------------- intensité perçue

func test_loudness_categories_mapping() -> void:
	assert_eq(SfxLoudness.category("dry_fire").id, "rechargement", "cliquetis à vide : pas un tir")
	assert_eq(SfxLoudness.category("g11_fire").id, "tir")
	assert_eq(SfxLoudness.category("thunder_fire").id, "arme_merveille")
	assert_eq(SfxLoudness.category("pap_zap_2").id, "arme_zap")
	assert_eq(SfxLoudness.category("zombie_groan_4").id, "zombie")
	assert_eq(SfxLoudness.category("ambience_bunker").id, "ambiance")
	assert_eq(SfxLoudness.category("ambience_bunker").mode, "int")
	assert_eq(SfxLoudness.category("menu_move").id, "interface")
	assert_eq(SfxLoudness.category("jingle_titan").id, "ritournelle")
	assert_eq(SfxLoudness.category("inconnu_xyz").id, "decor")


func test_loudness_measure_and_limiter() -> void:
	# Bruit blanc à -20 dBFS RMS pendant 1 s : ~ -17 LUFS (la pondération K
	# relève les aigus de 4 dB, où se trouve l'essentiel de l'énergie du bruit
	# blanc).
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var b := PackedFloat32Array()
	b.resize(44100)
	for i in b.size():
		b[i] = rng.randfn(0.0, 0.1)
	var l := SfxLoudness.momentary_max(b)
	assert_true(l > -18.5 and l < -15.5, "bruit blanc -20 dB RMS : %.1f LUFS" % l)
	assert_near(SfxLoudness.integrated(b), l, 1.0, "intégré ≈ momentané pour un bruit stationnaire")
	# Un son deux fois plus court (200 ms) paraît moins fort (fenêtre 400 ms).
	assert_true(SfxLoudness.momentary_max(b.slice(0, 8820)) < l - 2.5, "son bref moins fort")
	# Limiteur : aucune crête au-dessus du plafond.
	var hot := b.duplicate()
	for i in hot.size():
		hot[i] *= 12.0
	hot = SfxLoudness.limit(hot)
	assert_true(SfxLoudness.peak_db(hot) <= SfxLoudness.CEILING_DB + 0.01, "plafond respecté")
	# Nivellement : un tir trop faible est remonté à la cible, sans saturer.
	var shot := PackedFloat32Array()
	shot.resize(30000)
	for i in shot.size():
		shot[i] = rng.randf_range(-1.0, 1.0) * exp(-float(i) / 3000.0) * 0.05
	var lv := SfxLoudness.level("test_fire", shot)
	assert_near(SfxLoudness.momentary_max(lv), float(SfxLoudness.category("test_fire").target), 0.6, "tir mis à la cible")
	assert_true(SfxLoudness.peak_db(lv) <= SfxLoudness.CEILING_DB + 0.01, "tir sans écrêtage")


## Analyse automatique de TOUS les sons du jeu : chacun est à la cible de sa
## catégorie (± tolérance) ; les tirs d'armes sont cohérents entre eux.
func test_loudness_of_every_sound() -> void:
	var bad := []
	var fire := []
	for f in DirAccess.get_files_at("res://assets/audio/"):
		if f.get_extension() != "wav":
			continue
		var n := f.get_basename()
		var b := SfxLoudness.read_wav(ProjectSettings.globalize_path("res://assets/audio/" + f))
		assert_false(b.is_empty(), "%s : lisible" % n)
		var off: float = float(SfxRecipes.RECIPES[n].get("loud", 0.0)) if SfxRecipes.RECIPES.has(n) \
			else float(SfxRecipes.LEVEL_OFFSETS.get(n, 0.0))
		assert_true(absf(off) <= 8.0, "%s : décalage d'intensité raisonnable" % n)
		var c := SfxLoudness.category(n)
		var dev := SfxLoudness.deviation(n, b, off, 12.0)
		if absf(dev) > float(c.tol):
			bad.append("%s (%s) %+.1f LU" % [n, c.id, dev])
		if SfxLoudness.peak_db(b) > -0.3:
			bad.append("%s : crête %.1f dBFS" % [n, SfxLoudness.peak_db(b)])
		if c.id == "tir" and off == 0.0:
			fire.append(SfxLoudness.measure(n, b, 12.0))
	assert_true(bad.is_empty(), "intensités hors catégorie : %s" % [bad])
	fire.sort()
	assert_true(fire.size() >= 20, "tirs analysés (%d)" % fire.size())
	assert_true(fire[-1] - fire[0] <= 3.0, "tirs cohérents : écart %.1f LU (%.1f..%.1f)" % [fire[-1] - fire[0], fire[0], fire[-1]])


func test_monkey_beats_grid() -> void:
	var beats := SynthStems.monkey_beats()
	assert_eq(beats.size(), 18, "18 temps en 8 s à 135 bpm")
	for i in range(1, beats.size()):
		assert_true(beats[i] > beats[i - 1], "temps croissants")
	# Le ressort se détend : les derniers temps s'espacent.
	assert_true(beats[17] - beats[16] > beats[1] - beats[0] + 0.05, "ralenti final")
	assert_true(beats[17] < SynthStems.MONKEY_SECONDS, "dans la durée")


# ---------------------------------------------------------------- armes

func test_pack_a_punch_zap_layer() -> void:
	var mp40 := WeaponDB.stats("mp40", true)
	assert_true(WeaponAudio.has_zap(mp40, true), "arme améliorée : couche électrique")
	assert_false(WeaponAudio.has_zap(WeaponDB.stats("m1911"), false), "arme normale : pas de zap")
	assert_false(WeaponAudio.has_zap(WeaponDB.stats("ray", true), true), "arme merveille : pas de zap ajouté")
	assert_near(WeaponAudio.pitch(mp40, true), WeaponAudio.PAP_PITCH, 0.0001, "hauteur à peine abaissée")
	assert_true(WeaponAudio.PAP_PITCH > 0.9, "plus de simple son ralenti à 0,8")
	assert_near(WeaponAudio.pitch(WeaponDB.stats("m1911"), false), 1.0, 0.0001)
	for i in 20:
		var z := WeaponAudio.zap_name()
		assert_true(ResourceLoader.exists("res://assets/audio/%s.wav" % z), z)


func test_impact_surfaces_exist() -> void:
	for surf in ["concrete", "metal", "wood"]:
		for i in [1, 2]:
			assert_true(ResourceLoader.exists("res://assets/audio/impact_%s_%d.wav" % [surf, i]), "impact %s %d" % [surf, i])
	# Détection unique de la matière (Fx.surface_kind) : clés de matériau du
	# décor -> famille de son d'impact.
	assert_eq(Fx.surface_kind("steel"), "metal")
	assert_eq(Fx.surface_kind("barrel"), "metal")
	assert_eq(Fx.surface_kind("dark_wood"), "wood")
	assert_eq(Fx.surface_kind("crate"), "wood")
	assert_eq(Fx.surface_kind("marble"), "concrete")
