extends TestCase
## Sons : recettes d'import CC0 (sources, licences, fichiers), exclusion du
## générateur procédural, rythme et variété des vocalises des zombies.


func test_recipes_have_sources() -> void:
	for n in SfxRecipes.RECIPES:
		var r: Dictionary = SfxRecipes.RECIPES[n]
		assert_true(r.has("layers") and not r.layers.is_empty(), "%s : couches" % n)
		assert_true(r.get("preset", "") == "" or SfxRecipes.PRESETS.has(r.preset), "%s : préréglage" % n)
		for l in r.layers:
			assert_true(SfxRecipes.SOURCES.has(l.src), "%s : source %s documentée" % [n, l.src])
	for id in SfxRecipes.SOURCES:
		var s: Dictionary = SfxRecipes.SOURCES[id]
		assert_true(String(s.url).begins_with("https://cdn.freesound.org/previews/"), "%s : url" % id)
		assert_true(String(s.author) != "" and String(s.title) != "", "%s : auteur et titre" % id)


func test_imported_files_exist() -> void:
	for n in SfxRecipes.RECIPES:
		assert_true(ResourceLoader.exists("res://assets/audio/%s.wav" % n), "%s.wav présent" % n)


func test_generator_skips_replaced() -> void:
	var gen: GDScript = load("res://tools/gen_audio.gd")
	assert_true(gen.replaced("zombie_groan_1"), "râle importé exclu")
	assert_true(gen.replaced("m1911_fire"), "tir importé exclu")
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
