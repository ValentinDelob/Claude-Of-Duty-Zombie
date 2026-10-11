extends TestCase
## Rendus Blender du hub (HubRenders, sh tools/hub_renders.sh) : chaque arme,
## couteau et objet lancé, chaque ennemi du codex, chaque sorte d'échantillon
## et chaque personnage a son image, à la bonne taille, importée sans perte
## avec mipmaps ; un identifiant inconnu donne la texture de repli.


func _check(path: String, size: Vector2i, what: String) -> void:
	assert_true(HubRenders.has(path), "%s : rendu absent %s" % [what, path])
	if not HubRenders.has(path):
		return
	var tex := HubRenders.texture(path)
	assert_false(HubRenders.is_fallback(tex), "%s : texture de repli" % what)
	assert_eq(Vector2i(tex.get_size()), size, "%s : taille de %s" % [what, path])
	var imp := FileAccess.get_file_as_string(path + ".import")
	assert_true(imp.contains("compress/mode=0"), "%s : import sans perte attendu" % path)
	assert_true(imp.contains("mipmaps/generate=true"), "%s : mipmaps attendues" % path)


func test_every_weapon_has_a_render() -> void:
	for id in WeaponDB.WEAPONS:
		_check(HubRenders.weapon_path(id), HubRenders.WEAPON_SIZE, "arme " + id)
	for id in KnifeDB.KNIVES:
		_check(HubRenders.weapon_path(id), HubRenders.WEAPON_SIZE, "couteau " + id)
	for item in ThrowableRules.CRATE_ITEMS:
		_check(HubRenders.weapon_path(item.id), HubRenders.WEAPON_SIZE, "objet " + item.id)


func test_every_codex_enemy_has_a_render() -> void:
	var ids := CodexData.default().ids()
	assert_true(ids.size() >= 8, "codex : au moins 8 ennemis")
	for id in ids:
		_check(HubRenders.enemy_path(id), HubRenders.ENEMY_SIZE, "ennemi " + id)


func test_every_sample_has_a_render() -> void:
	var n := 0
	for kind in LootRules.SAMPLES:
		for s in LootRules.SAMPLES[kind]:
			n += 1
			_check(HubRenders.sample_path(s[0]), HubRenders.SAMPLE_SIZE, "échantillon " + s[0])
	assert_true(n >= 10, "au moins 10 sortes d'échantillons")


func test_characters_have_renders() -> void:
	for c in HubRenders.CHARACTERS:
		_check(HubRenders.character_path(c), HubRenders.CHARACTER_SIZES[c], "personnage " + c)


func test_model_mapping() -> void:
	assert_eq(HubRenders.weapon_model("decoy"), "teddy")
	assert_eq(HubRenders.weapon_model("knife"), "knife")
	assert_eq(HubRenders.weapon_model("m1911"), "m1911")
	assert_eq(HubRenders.weapon_path("bat"), "res://assets/ui/hub/renders/weapons/bat.png")


func test_unknown_id_gives_fallback() -> void:
	var tex := HubRenders.enemy("pas_un_ennemi")
	assert_true(tex != null, "jamais null")
	assert_true(HubRenders.is_fallback(tex), "texture de repli")
	assert_true(HubRenders.is_fallback(HubRenders.weapon("pas_une_arme")), "arme inconnue : repli")
	assert_eq(HubRenders.sample("pas_un_echantillon"), HubRenders.empty())
