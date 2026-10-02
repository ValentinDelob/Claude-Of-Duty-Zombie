extends TestCase
## Format 10 de l'éditeur de cartes (docs/MAP_OBJECTS.md § 11) : catégorie
## « Effets » de l'inventaire et ses sous-onglets (flammes, fumées,
## étincelles, électricité, eau, ambiance), au moins 3 effets chacun ; chaque
## effet se construit sans erreur (particules, lumières, objets, AUCUNE
## collision) ; pose par-dessus le décor et les objets de jeu ; réglages
## (intensité, taille, couleur, hauteur) jamais écrits à leur valeur par
## défaut ; aller-retour des fichiers ; export vers le jeu (clé « effects ») ;
## contrôle des cartes reçues (clés et valeurs bornées, nombre d'effets).

const ObjectsTest := preload("res://tests/test_map_objects.gd")


static func _fx(doc: EditorMap, id: String, pos: Vector2, extra := {}) -> Dictionary:
	var o: Dictionary = MapCatalog.item("effet:" + id).make.duplicate(true)
	o["id"] = doc.new_id("fx")
	o["etage"] = 0
	o["position"] = MapGeom.arr(pos)
	o.merge(extra, true)
	doc.objets.append(o)
	return o


# ------------------------------------------------------------------ catalogue

func test_effects_category_has_sub_tabs_with_three_effects_each() -> void:
	var subs := MapCatalog.subs_of("effets")
	assert_true(subs.size() >= 6, "au moins 6 sous-onglets (%d)" % subs.size())
	assert_eq(MapCatalog.subs_of("prefabs"), [], "les autres catégories n'ont pas de sous-onglets")
	var total := 0
	for s in subs:
		var list := MapCatalog.in_category("effets", String(s[0]))
		assert_true(list.size() >= 3, "sous-onglet %s : %d effets (3 au moins)" % [s[0], list.size()])
		total += list.size()
		for it in list:
			assert_eq(String(it.make.type), "effet", "%s : type effet" % it.id)
			assert_true(String(it.fr) != "" and String(it.en) != "", "%s : nom FR et EN" % it.id)
			assert_true(String(it.tool) in ["floor_item", "wall_item"], "%s : posé au sol, au plafond ou au mur" % it.id)
	assert_eq(total, MapCatalog.in_category("effets").size(), "chaque effet est dans un sous-onglet")
	assert_true(total >= 18, "au moins 18 effets (%d)" % total)
	assert_eq(MapCatalog.EFFECTS.size(), total, "tous les effets du catalogue sont dans l'inventaire")


func test_every_effect_builds_without_collision() -> void:
	var parent := Node3D.new()
	host.add_child(parent)
	for id in MapCatalog.EFFECTS:
		var fx := MapEffects.build(id, {"ground": 1.5, "room_h": 3.2, "intensity": 1.0, "scale": 1.0})
		assert_true(fx != null, "%s construit" % id)
		if fx == null:
			continue
		parent.add_child(fx)
		assert_true(fx.parts.size() >= 1, "%s : %d couches de particules" % [id, fx.parts.size()])
		assert_true(fx.particle_count() <= 600, "%s : %d particules (600 au plus)" % [id, fx.particle_count()])
		assert_eq(fx.find_children("*", "CollisionObject3D", true, false).size(), 0, "%s : aucune collision" % id)
		for l in fx.lights:
			assert_false(l.shadow_enabled, "%s : lumière sans ombre" % id)
		# Réglages extrêmes : se construit aussi.
		var big := MapEffects.build(id, {"ground": 30.0, "intensity": 2.0, "scale": 2.5, "color": "ff0000"})
		var small := MapEffects.build(id, {"ground": 0.0, "intensity": 0.25, "scale": 0.5})
		assert_true(big != null and small != null, "%s : réglages extrêmes" % id)
		assert_true(big.particle_count() >= small.particle_count(), "%s : plus de particules à l'intensité 2" % id)
		big.free()
		small.free()
	assert_true(MapEffects.build("inconnu") == null, "effet inconnu : rien")
	await wait_frames(3)
	parent.queue_free()


func test_effects_follow_the_quality_and_the_map_budget() -> void:
	var fx := MapEffects.build("brasier")
	host.add_child(fx)
	fx.apply_quality(RenderQuality.preset(0))
	for p in fx.parts:
		assert_near(p.amount_ratio, 0.5, 0.001, "qualité basse : moitié des particules")
	assert_true(fx.lights.all(func(l): return l.visible), "lumière principale du feu gardée en qualité basse")
	fx.apply_quality(RenderQuality.preset(1))
	fx.set_budget(0.5)
	assert_near(fx.parts[0].amount_ratio, 0.5, 0.001, "budget de la carte dépassé : particules réduites")
	assert_eq(fx.limit_lights(0), 0, "budget de lumières épuisé")
	assert_false(fx.lights[0].visible, "lumière éteinte")
	fx.queue_free()


# ------------------------------------------------------------------ pose

func test_effects_go_over_anything_and_never_block() -> void:
	var doc := ObjectsTest.objects_map()
	# Au sol, au plafond, par-dessus la boîte et le départ des joueurs.
	for c in [["petit_feu", Vector2(5, 5)], ["goutte", Vector2(9.0, 7.0)], ["brouillard", Vector2(9.5, 1.5)], ["incendie", Vector2(9.0, 7.0)]]:
		var tmpl: Dictionary = MapCatalog.item("effet:" + String(c[0])).make
		var r := MapRules.place_floor_item(doc, 0, tmpl, c[1])
		assert_true(r.ok, "%s posé (%s)" % [c[0], MapRules.why(r)])
	var torch: Dictionary = MapCatalog.item("effet:torche").make
	var rw := MapRules.place_wall_item(doc, 0, torch, Vector2(9.75, 0.4))
	assert_true(rw.ok, "torche contre le mur, par-dessus la boîte (%s)" % MapRules.why(rw))
	# Un effet ne gêne pas la pose d'un objet de jeu.
	_fx(doc, "brasier", Vector2(5.0, 5.0))
	var r2 := MapRules.place_floor_item(doc, 0, MapCatalog.item("apparition").make, Vector2(5.0, 5.0))
	assert_true(r2.ok, "apparition posée sous un brasier (%s)" % MapRules.why(r2))
	assert_true(MapRules.place_floor_item(doc, 0, MapCatalog.item("prefab:caisses").make, Vector2(5.0, 5.0)).ok, "décor posé sur un effet")
	# Aucune case bloquée : la carte reste jouable, même trajet.
	var v := ObjectsTest._check(doc)
	assert_eq(v.errors(), [], "carte valide avec des effets")
	assert_eq(v.effects.size(), 1, "un effet relevé par le validateur")


func test_effect_count_is_capped() -> void:
	var doc := ObjectsTest.objects_map()
	for i in MapCatalog.MAX_EFFECTS:
		_fx(doc, "poussiere", Vector2(2 + (i % 10), 2 + int(i / 10.0) * 0.5))
	var r := MapRules.place_floor_item(doc, 0, MapCatalog.item("effet:braises").make, Vector2(6, 6))
	assert_false(r.ok, "effet de trop refusé")
	var moved := MapRules.place_floor_item(doc, 0, doc.objets[-1], Vector2(6, 6), String(doc.objets[-1].id))
	assert_true(moved.ok, "un effet posé se déplace toujours")


# ------------------------------------------------------------------ fichiers et jeu

func test_effect_settings_round_trip_and_export() -> void:
	var doc := ObjectsTest.objects_map()
	_fx(doc, "feux_follets", Vector2(5, 5), {"couleur": "#ff00ff", "intensite": 1.5, "taille": 2.0, "hauteur": 0.5})
	_fx(doc, "petit_feu", Vector2(4, 8), {"intensite": 1.0, "couleur": "#00ff00", "hauteur": 0.0})
	_fx(doc, "incendie", Vector2(18, 6), {"rot": 90})
	var torch: Dictionary = MapCatalog.item("effet:torche").make.duplicate(true)
	var rw := MapRules.place_wall_item(doc, 0, torch, Vector2(2.0, 0.4))
	assert_true(rw.ok, "torche posée")
	torch["id"] = doc.new_id("fx")
	torch["etage"] = 0
	torch["position"] = rw.position
	MapRules.apply_wall(torch, rw)
	doc.objets.append(torch)
	_fx(doc, "pluie_etincelles", Vector2(20, 4))
	var texts := doc.file_texts()
	assert_true(String(texts["carte.json"]).contains("\"format\": %d" % EditorMap.FORMAT) and EditorMap.FORMAT >= 10, "format 10 et plus")
	var m := EditorMap.from_texts(texts)
	var wisp: Dictionary = m.objets.filter(func(o): return String(o.get("effet", "")) == "feux_follets")[0]
	assert_eq(String(wisp.couleur), "#ff00ff", "couleur relue")
	assert_near(float(wisp.taille), 2.0, 0.001, "taille relue")
	var fire: Dictionary = m.objets.filter(func(o): return String(o.get("effet", "")) == "petit_feu")[0]
	for k in ["intensite", "couleur", "hauteur", "rot"]:
		assert_false(fire.has(k), "petit feu : « %s » par défaut ou sans objet, retirée" % k)
	assert_eq(EditorMap.from_texts(m.file_texts()).file_texts(), m.file_texts(), "relue puis réécrite à l'identique")
	assert_eq(CustomMapGuard.check_texts(m.file_texts()).reasons, [], "contrôle des cartes reçues : effets acceptés")
	# Export vers le jeu.
	var def := EditorMapDef.from_map(m, "perso:effets")
	assert_true(def.is_valid(), "carte jouable")
	var list: Array = def.layout_data.get("effects", [])
	assert_eq(list.size(), 5, "5 effets exportés")
	var by := {}
	for e in list:
		by[String(e.fx)] = e
	assert_near(float(by.feux_follets.p[1]), 0.5, 0.01, "feux follets surélevés de 0,5 m")
	assert_eq(String(by.feux_follets.color), "ff00ff", "teinte exportée")
	assert_near(float(by.feux_follets.scale), 2.0, 0.001, "taille exportée")
	assert_false(by.petit_feu.has("color"), "le feu ne se teinte pas")
	assert_near(float(by.torche.p[1]), 1.8, 0.01, "torche à 1,8 m")
	assert_near(float(by.pluie_etincelles.p[1]), float(by.pluie_etincelles.room_h) - 0.02, 0.01, "pluie d'étincelles sous le plafond")
	assert_near(float(by.pluie_etincelles.ground), float(by.pluie_etincelles.p[1]), 0.01, "distance au sol")
	assert_near(float(by.incendie.yaw), -PI * 0.5, 0.001, "incendie tourné")
	# Construit par le jeu (décor : MeshMapBuilder._build_effects), sans collision.
	var holder := Node3D.new()
	host.add_child(holder)
	var b := MapPreviewBuilder.new(def.layout_data)
	b.build_decor(holder)
	var made := holder.find_children("*", "MapEffect", true, false)
	assert_eq(made.size(), 5, "5 effets construits")
	for fx in made:
		assert_eq(fx.find_children("*", "CollisionObject3D", true, false).size(), 0, "%s : aucune collision" % fx.name)
	holder.queue_free()
	# Carte sans effet : description inchangée (pas de clé « effects »).
	assert_false(EditorMapDef.from_map(ObjectsTest.objects_map(), "perso:sans").layout_data.has("effects"), "sans effet : pas de clé")


func test_guard_checks_effects_strictly() -> void:
	var doc := ObjectsTest.objects_map()
	_fx(doc, "arc", Vector2(5, 5), {"rot": 45, "couleur": "#80a0ff"})
	var texts := doc.file_texts()
	assert_eq(CustomMapGuard.check_texts(texts).reasons, [], "effet accepté")
	var objs := String(texts["objets.json"])
	var bad := [
		["effet inconnu", objs.replace("\"effet\":\"arc\"", "\"effet\":\"bombe\"")],
		["intensité hors bornes", objs.replace("\"effet\":\"arc\"", "\"effet\":\"arc\", \"intensite\":50")],
		["taille illisible", objs.replace("\"effet\":\"arc\"", "\"effet\":\"arc\", \"taille\":\"x\"")],
		["couleur illisible", objs.replace("\"couleur\":\"#80a0ff\"", "\"couleur\":\"bleu\"")],
		["clé inconnue", objs.replace("\"effet\":\"arc\"", "\"effet\":\"arc\", \"degats\":10")],
		["sans effet", objs.replace("\"effet\":\"arc\",", "")],
	]
	for bc in bad:
		var t: Dictionary = texts.duplicate()
		t["objets.json"] = bc[1]
		assert_true(t["objets.json"] != objs, "%s : texte modifié" % bc[0])
		assert_false(CustomMapGuard.check_texts(t).reasons.is_empty(), "refusé : %s" % bc[0])
	# Trop d'effets.
	var many := ObjectsTest.objects_map()
	for i in MapCatalog.MAX_EFFECTS + 1:
		_fx(many, "poussiere", Vector2(2 + (i % 10), 2 + int(i / 10.0) * 0.5))
	assert_false(CustomMapGuard.check_texts(many.file_texts()).reasons.is_empty(), "%d effets : refusé" % (MapCatalog.MAX_EFFECTS + 1))


func test_review_map_is_playable_with_every_effect() -> void:
	var doc: EditorMap = load("res://tests/autotest/map_effects_look.gd").review_map()
	var def := EditorMapDef.from_map(doc, "perso:effets_revue")
	var errs: Array = def.validator.errors().map(func(m): return String(m.fr))
	assert_true(def.is_valid(), "carte de revue jouable : %s" % str(errs))
	assert_eq(def.layout_data.get("effects", []).size(), MapCatalog.EFFECTS.size(), "tous les effets exportés")
	assert_true(def.layout_data.get("rooms", []).size() >= 1, "salle exportée")


# ------------------------------------------------------------------ éditeur

func test_inventory_sub_tabs_and_properties_in_the_editor() -> void:
	var ed: MapEditor = load(MapEditor.SCENE).instantiate()
	host.add_child(ed)
	await wait_frames(3)
	ed.new_map(true)
	ed.add_object({"contour": [[2, 2], [14, 2], [14, 10], [2, 10]]}, 0)
	var inv := ed.inventory
	ed.toggle_inventory()
	inv.show_category("effets")
	await wait_frames(1)
	var subs := MapCatalog.subs_of("effets")
	assert_true(inv._subs.visible, "rangée des sous-onglets montrée")
	assert_eq(inv._subs.get_child_count(), subs.size(), "un bouton par sous-onglet")
	assert_eq(inv.cells.size(), MapCatalog.in_category("effets", String(subs[0][0])).size(), "premier sous-onglet : ses effets seulement")
	inv.show_sub("eau")
	assert_eq(inv.cells.map(func(s): return s.item_id), MapCatalog.in_category("effets", "eau").map(func(it): return it.id), "sous-onglet Eau")
	assert_true((inv._subs.get_node("eau") as Button).button_pressed, "bouton Eau enfoncé")
	inv.show_category("prefabs")
	assert_false(inv._subs.visible, "Décor : pas de sous-onglets")
	assert_eq(inv.cells.size(), MapCatalog.in_category("prefabs").size(), "Décor inchangé")
	inv.show_category("effets")
	assert_eq(inv.cells.map(func(s): return s.item_id), MapCatalog.in_category("effets", "eau").map(func(it): return it.id), "sous-onglet gardé")
	ed.toggle_inventory()
	# Effet posé, choisi : ses réglages dans les propriétés.
	var o := ed.add_object({"type": "effet", "effet": "feux_follets", "position": [6.0, 6.0]}, 0)
	assert_true(String(o.id).begins_with("fx"), "identifiant fx (%s)" % o.id)
	ed.select(String(o.id))
	await wait_frames(2)
	var spins := ed.panels._props.find_children("*", "SpinBox", true, false)
	assert_true(spins.size() >= 3, "intensité, taille, hauteur (%d champs)" % spins.size())
	assert_eq(ed.panels._props.find_children("*", "ColorPickerButton", true, false).size(), 1, "couleur (effet qui se teint)")
	(spins[0] as SpinBox).value = 1.6
	assert_near(float(o.get("intensite", 0.0)), 1.6, 0.001, "intensité réglée")
	(spins[0] as SpinBox).value = 1.0
	assert_false(o.has("intensite"), "intensité par défaut : clé retirée")
	ed.queue_free()
	await wait_frames(2)
