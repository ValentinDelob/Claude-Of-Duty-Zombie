extends TestCase
## Effets de l'éditeur de cartes (docs/MAP_OBJECTS.md § 12) : catégorie
## « Effets » de l'inventaire et ses sous-onglets (flammes, fumées,
## étincelles, électricité, eau, ambiance), au moins 3 effets chacun ; format
## 11 : des EFFETS PURS (particules, lumières, arcs : aucun objet solide,
## aucune collision ; bûches, torche, tuyaux... sont des décors de l'onglet
## Décor), une ZONE redimensionnable (poignées, bornes, rotation) qui règle
## l'émission et le nombre de particules (densité constante, plafond par
## effet, budgets de la carte) ; conversion des cartes d'avant (effet + décor,
## une seule fois) ; pose par-dessus le décor et les objets de jeu ; réglages
## jamais écrits à leur valeur par défaut ; aller-retour des fichiers ;
## export vers le jeu (clé « effects ») ; contrôle des cartes reçues.

const ObjectsTest := preload("res://tests/test_map_objects.gd")


static func _fx(doc: EditorMap, id: String, pos: Vector2, extra := {}) -> Dictionary:
	var o: Dictionary = MapCatalog.item("effet:" + id).make.duplicate(true)
	o["id"] = doc.new_id("fx")
	o["etage"] = 0
	o["position"] = MapGeom.arr(pos)
	o.merge(extra, true)
	doc.objets.append(o)
	return o


## Zone [largeur, profondeur, hauteur] d'une description « effects ».
static func _zone(id: String, k: float) -> Array:
	var z := MapCatalog.effect_default_zone(id) * k
	return [z.x, z.y, z.z]


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


func test_every_effect_has_zone_bounds_and_its_decor_exists() -> void:
	for id in MapCatalog.EFFECTS:
		var d: Dictionary = MapCatalog.EFFECTS[id]
		var dims := MapCatalog.effect_dims(id)
		assert_eq(dims.size(), 2 if String(d.mount) == "mur" or not d.zone.has("h") else 3, "%s : dimensions de zone" % id)
		for key in dims:
			var spec: Array = d.zone[key]
			assert_true(float(spec[1]) <= float(spec[0]) and float(spec[0]) <= float(spec[2]), "%s.%s : défaut dans ses bornes" % [id, key])
			assert_true(float(spec[1]) >= MapCatalog.ZONE_LIMITS[0] and float(spec[2]) <= MapCatalog.ZONE_LIMITS[1], "%s.%s : bornes absolues" % [id, key])
		assert_true(int(d.get("cap", 0)) > 0 and int(d.cap) <= 2000, "%s : plafond de particules" % id)
		for pid in d.get("decor", []):
			assert_true(MapCatalog.PREFABS.has(pid), "%s : décor %s au catalogue" % [id, pid])
			assert_true(MapCatalog.item("prefab:" + String(pid)).cat == "prefabs", "%s : décor %s dans l'onglet Décor" % [id, pid])
	# Les effets qui évoquent un objet ont changé de nom (l'objet est un décor).
	assert_eq(String(MapCatalog.EFFECTS.torche.fr), "Flamme de torche")
	assert_eq(String(MapCatalog.EFFECTS.vapeur.fr), "Jet de vapeur")
	assert_eq(String(MapCatalog.EFFECTS.fuite.fr), "Filet d'eau")
	assert_eq(String(MapCatalog.EFFECTS.tesla.fr), "Arcs en boule")
	assert_eq(String(MapCatalog.EFFECTS.cable_nu.fr), "Étincelles de câble")
	assert_eq(String(MapCatalog.EFFECTS.flaque.fr), "Ronds dans l'eau")


# ------------------------------------------------------------------ construction (jeu)

func test_every_effect_is_pure_without_any_mesh_or_collision() -> void:
	var parent := Node3D.new()
	host.add_child(parent)
	for id in MapCatalog.EFFECTS:
		var cap := int(MapCatalog.EFFECTS[id].cap)
		var fx := MapEffects.build(id, {"ground": 1.5, "room_h": 3.2, "intensity": 1.0})
		assert_true(fx != null, "%s construit" % id)
		if fx == null:
			continue
		parent.add_child(fx)
		assert_true(fx.parts.size() >= 1, "%s : %d couches de particules" % [id, fx.parts.size()])
		assert_true(fx.particle_count() <= mini(600, cap), "%s : %d particules (600 et %d au plus)" % [id, fx.particle_count(), cap])
		assert_eq(fx.find_children("*", "CollisionObject3D", true, false).size(), 0, "%s : aucune collision" % id)
		# Aucun objet : les seuls maillages sont les panneaux des arcs électriques.
		for mi in fx.find_children("*", "MeshInstance3D", true, false):
			assert_true(fx.arcs.has(mi), "%s : maillage %s qui n'est pas un arc" % [id, mi.name])
		for gi in fx.find_children("*", "GeometryInstance3D", true, false):
			assert_true(gi is GPUParticles3D or fx.arcs.has(gi), "%s : %s n'est ni particules ni arc" % [id, gi.name])
		assert_eq(fx.body.scale, Vector3.ONE, "%s : jamais mis à l'échelle" % id)
		for l in fx.lights:
			assert_false(l.shadow_enabled, "%s : lumière sans ombre" % id)
		# Zones extrêmes, intensités extrêmes : se construit, plafond respecté.
		var big := MapEffects.build(id, {"ground": 30.0, "intensity": 2.0, "zone": _zone(id, 100.0), "color": "ff0000"})
		var small := MapEffects.build(id, {"ground": 0.0, "intensity": 0.25, "zone": _zone(id, 0.01)})
		assert_true(big != null and small != null, "%s : réglages extrêmes" % id)
		assert_true(big.particle_count() <= cap, "%s : zone maximale, %d particules (plafond %d)" % [id, big.particle_count(), cap])
		assert_true(big.particle_count() >= small.particle_count(), "%s : plus de particules dans la grande zone" % id)
		big.free()
		small.free()
	assert_true(MapEffects.build("inconnu") == null, "effet inconnu : rien")
	await wait_frames(3)
	parent.queue_free()


func test_particle_density_follows_the_zone_up_to_the_cap() -> void:
	# Brouillard : 6 × 6 m puis 12 × 12 m : 4 fois plus de particules,
	# même taille de particule (assez de place dans les deux volumes), boîte
	# d'émission plus de 2 fois plus large.
	var a := MapEffects.build("brouillard", {"zone": [6.0, 6.0, 0.6]})
	var b := MapEffects.build("brouillard", {"zone": [12.0, 12.0, 0.6]})
	assert_near(float(b.particle_count()) / a.particle_count(), 4.0, 0.3, "densité constante (%d -> %d)" % [a.particle_count(), b.particle_count()])
	var pa := a.parts[0].process_material as ParticleProcessMaterial
	var pb := b.parts[0].process_material as ParticleProcessMaterial
	assert_near(pb.scale_min, pa.scale_min, 0.001, "particules de même taille")
	assert_true(pb.emission_box_extents.x > pa.emission_box_extents.x * 2.0, "émission sur toute la zone")
	assert_true(b.parts[0].visibility_aabb.size.x >= 12.0, "boîte de visibilité : le volume")
	# Plafond de l'effet : 40 × 40 m, au plus « cap » particules ; la nappe
	# grossit un peu pour rester couvrante.
	var c := MapEffects.build("brouillard", {"zone": [40.0, 40.0, 0.6]})
	assert_true(c.particle_count() <= int(MapCatalog.EFFECTS.brouillard.cap), "plafond de l'effet (%d)" % c.particle_count())
	assert_true((c.parts[0].process_material as ParticleProcessMaterial).scale_min > pa.scale_min, "nappe plus large au plafond")
	# Intensité : × 2 particules.
	var d := MapEffects.build("brouillard", {"zone": [6.0, 6.0, 0.6], "intensity": 2.0})
	assert_near(float(d.particle_count()) / a.particle_count(), 2.0, 0.2, "intensité 2 : deux fois plus")
	# Poussière : volume (hauteur de zone comprise).
	var e1 := MapEffects.build("poussiere", {"zone": [3.0, 3.0, 2.0]})
	var e2 := MapEffects.build("poussiere", {"zone": [3.0, 3.0, 4.0]})
	assert_near(float(e2.particle_count()) / e1.particle_count(), 2.0, 0.2, "poussière : suit le volume")
	# Petite zone : la flamme de torche reste petite, un seul foyer.
	var t := MapEffects.build("torche", {"zone": [0.6, 0.5, 0.8]})
	assert_true(t.particle_count() <= int(MapCatalog.EFFECTS.torche.cap), "torche plafonnée")
	# Lumière : portée selon la zone, bornée.
	var f1 := MapEffects.build("incendie", {"zone": [3.0, 2.0, 0.0]})
	var f2 := MapEffects.build("incendie", {"zone": [12.0, 8.0, 0.0]})
	assert_true(f2.lights[0].omni_range > f1.lights[0].omni_range, "grand incendie : lumière plus loin")
	assert_true(f2.lights.all(func(l): return l.omni_range <= MapEffects.MAX_LIGHT_RANGE), "portée bornée")
	assert_true(f2.lights.size() >= 2 and f2.lights.size() <= 3, "grand incendie : 2 à 3 lumières (%d)" % f2.lights.size())
	# Description d'avant le format 11 : « scale » lu comme zone par défaut × taille.
	var old := MapEffects.build("brasier", {"scale": 2.0})
	assert_near(old.zone.x, MapCatalog.effect_default_zone("brasier").x * 2.0, 0.001, "« scale » d'avant : zone × 2")
	for fx in [a, b, c, d, e1, e2, t, f1, f2, old]:
		fx.free()


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


func test_map_budget_holds_with_huge_zones() -> void:
	# 64 nappes de brume au maximum : le budget de 9000 particules et de 16
	# lumières de la carte tient (MeshMapBuilder._build_effects).
	var list := []
	for i in MapCatalog.MAX_EFFECTS:
		list.append({"fx": "incendie" if i % 2 == 0 else "brouillard", "p": [i * 2.0, 0.0, 0.0], "yaw": 0.0, "ground": 0.0, "room_h": 4.0,
			"intensity": 2.0, "zone": [12.0, 12.0, 3.0] if i % 2 == 0 else [40.0, 40.0, 3.0], "eid": "fx%d" % i})
	var holder := Node3D.new()
	host.add_child(holder)
	var b := MapPreviewBuilder.new({"effects": list})
	b._make_root(holder, "Decor")
	b._build_effects()
	var made := holder.find_children("*", "MapEffect", true, false)
	assert_eq(made.size(), MapCatalog.MAX_EFFECTS, "%d effets" % MapCatalog.MAX_EFFECTS)
	var shown := 0.0
	var lights := 0
	for fx in made:
		shown += fx.particle_count() * fx._budget
		lights += fx._light_on.count(1)
	assert_true(shown <= MapEffects.PARTICLE_BUDGET * 1.05, "budget de particules (%d)" % int(shown))
	assert_true(lights <= MapEffects.LIGHT_BUDGET, "budget de lumières (%d)" % lights)
	holder.queue_free()
	await wait_frames(2)


# ------------------------------------------------------------------ zone dans l'éditeur

func test_zone_handles_resize_with_bounds_and_rotation() -> void:
	var doc := ObjectsTest.objects_map()
	var fog := _fx(doc, "brouillard", Vector2(6, 5))
	var hs := MapTransform.effect_handles(fog)
	assert_eq(hs.size(), 8, "4 coins et 4 milieux")
	assert_eq(hs[0], Vector2(4, 3), "coin haut-gauche de la zone de 4 × 4 m")
	assert_eq(hs[5], Vector2(8, 5), "milieu droit")
	# Coin bas-droit tiré : le coin opposé reste en place.
	var r := MapTransform.effect_resized(fog, 2, Vector2(12, 9))
	assert_eq(MapCatalog.effect_zone(r), Vector3(8, 6, 0.6), "zone 8 × 6 m")
	assert_eq(MapTransform.effect_handles(r)[0], Vector2(4, 3), "coin opposé fixe")
	assert_eq(r.zone, [8.0, 6.0, 0.6], "clé zone écrite")
	# Bornes de l'effet : jamais au-delà de 40 m ni sous 2 m, jamais retournée.
	var big := MapTransform.effect_resized(fog, 5, Vector2(90, 5))
	assert_near(MapCatalog.effect_zone(big).x, 40.0, 0.001, "40 m au plus")
	var flip := MapTransform.effect_resized(fog, 5, Vector2(0, 5))
	assert_near(MapCatalog.effect_zone(flip).x, 2.0, 0.001, "2 m au moins, côté gauche fixe")
	assert_near(MapTransform.effect_handles(flip)[0].x, 4.0, 0.001, "jamais retournée")
	# Retour à la zone par défaut : clé retirée.
	var back := MapTransform.effect_resized(r, 2, Vector2(8, 7))
	assert_false(back.has("zone"), "zone par défaut : pas de clé")
	# Zone tournée : poignées et redimensionnement dans le repère de l'effet.
	var rot := _fx(doc, "incendie", Vector2(18, 5), {"rot": 90})
	var rh := MapTransform.effect_handles(rot)
	assert_true(rh[0].distance_to(Vector2(19, 3.5)) < 0.01, "coin tourné de 90° (%s)" % rh[0])
	var rr := MapTransform.effect_resized(rot, 6, Vector2(16, 5))
	assert_near(MapCatalog.effect_zone(rr).y, 2.0 + 1.0, 0.001, "profondeur tirée dans le repère tourné")
	assert_true(MapRules.check_existing(doc, rr).ok, "zone tournée valide")
	# Effet mural : deux poignées le long du mur, l'autre bout fixe.
	var steam := _fx(doc, "vapeur", Vector2(2.0, 0.0), {"mur": "n"})
	var wh := MapTransform.effect_handles(steam)
	assert_eq(wh.size(), 2, "effet mural : 2 poignées")
	var ws := MapTransform.effect_resized(steam, 1, wh[1] + (wh[1] - wh[0]).normalized() * 1.7 + Vector2(0, 0.4))
	assert_near(MapCatalog.effect_zone(ws).x, MapCatalog.effect_default_zone("vapeur").x + 1.7, 0.001, "jet de vapeur élargi de 1,7 m")
	assert_true(MapTransform.effect_handles(ws)[0].distance_to(wh[0]) < 0.001, "l'autre bout reste fixe")
	assert_near(float(ws.position[1]), 0.0, 0.001, "toujours sur le trait du mur")
	assert_true(MapRules.check_existing(doc, ws).ok, "toujours contre le mur")
	# Clic sur toute la zone, emprise = zone.
	doc.objets.erase(fog)
	doc.objets.append(r)
	assert_true(MapRules.hit(doc, r, Vector2(11.5, 8.5)), "clic dans le coin de la zone")
	assert_false(MapRules.hit(doc, r, Vector2(12.5, 9.5)), "clic hors de la zone")
	assert_eq(MapRules.footprint_rect(r), Rect2(4, 3, 8, 6), "emprise = zone")
	# Tous les effets au sol et au plafond pivotent ; un effet mural suit son mur.
	for id in MapCatalog.EFFECTS:
		var o: Dictionary = MapCatalog.item("effet:" + id).make
		assert_eq(MapTransform.can_rotate(o), String(MapCatalog.EFFECTS[id].mount) != "mur", "%s : rotation" % id)


func test_zone_settings_are_tidied_and_old_size_converted() -> void:
	var o := {"type": "effet", "effet": "fumee_legere", "position": [3, 3], "taille": 2.0}
	MapCatalog.tidy_effect(o)
	assert_false(o.has("taille"), "« taille » d'avant retirée")
	var dz := MapCatalog.effect_default_zone("fumee_legere") * 2.0
	assert_eq(o.zone, [dz.x, dz.y], "taille 2 : zone par défaut × 2")
	var w := {"type": "effet", "effet": "torche", "position": [3, 0], "mur": "n", "taille": 2.5, "rot": 90}
	MapCatalog.tidy_effect(w)
	assert_eq(w.zone, [0.6, 0.8], "torche : bornée à 0,6 × 0,8 m")
	assert_false(w.has("rot"), "effet mural : pas de rotation")
	var bad := {"type": "effet", "effet": "brouillard", "position": [3, 3], "zone": [5.0, "x", 1.0]}
	MapCatalog.tidy_effect(bad)
	assert_false(bad.has("zone"), "zone illisible retirée")
	var clamp := {"type": "effet", "effet": "brouillard", "position": [3, 3], "zone": [100.0, 1.0, 0.6]}
	MapCatalog.tidy_effect(clamp)
	assert_eq(clamp.zone, [40.0, 2.0, 0.6], "zone bornée")
	var same := {"type": "effet", "effet": "brouillard", "position": [3, 3], "zone": [4.0, 4.0, 0.6]}
	MapCatalog.tidy_effect(same)
	assert_false(same.has("zone"), "zone par défaut : jamais écrite")
	var snapped := {"type": "effet", "effet": "brouillard", "position": [3, 3], "zone": [5.123, 4.0, 0.6]}
	MapCatalog.tidy_effect(snapped)
	assert_eq(snapped.zone, [5.1, 4.0, 0.6], "arrondie à 5 cm")


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
	assert_true(rw.ok, "flamme de torche contre le mur, par-dessus la boîte (%s)" % MapRules.why(rw))
	# Un effet ne gêne pas la pose d'un objet de jeu.
	_fx(doc, "brasier", Vector2(5.0, 5.0))
	var r2 := MapRules.place_floor_item(doc, 0, MapCatalog.item("apparition").make, Vector2(5.0, 5.0))
	assert_true(r2.ok, "apparition posée sous un grand feu (%s)" % MapRules.why(r2))
	assert_true(MapRules.place_floor_item(doc, 0, MapCatalog.item("prefab:caisses").make, Vector2(5.0, 5.0)).ok, "décor posé sur un effet")
	# Une zone immense ne bloque rien non plus.
	_fx(doc, "brouillard", Vector2(7, 5), {"zone": [14.0, 10.0, 0.6]})
	# Aucune case bloquée : la carte reste jouable, même trajet.
	var v := ObjectsTest._check(doc)
	assert_eq(v.errors(), [], "carte valide avec des effets")
	assert_eq(v.effects.size(), 2, "deux effets relevés par le validateur")


func test_effect_count_is_capped() -> void:
	var doc := ObjectsTest.objects_map()
	for i in MapCatalog.MAX_EFFECTS:
		_fx(doc, "poussiere", Vector2(2 + (i % 10), 2 + int(i / 10.0) * 0.5))
	var r := MapRules.place_floor_item(doc, 0, MapCatalog.item("effet:braises").make, Vector2(6, 6))
	assert_false(r.ok, "effet de trop refusé")
	var moved := MapRules.place_floor_item(doc, 0, doc.objets[-1], Vector2(6, 6), String(doc.objets[-1].id))
	assert_true(moved.ok, "un effet posé se déplace toujours")


# ------------------------------------------------------------------ décors des effets (onglet Décor)

func test_effect_decor_is_in_the_props_tab_and_built_by_the_game() -> void:
	var ids := ["buches", "foyer_pierres", "planches_brulees", "electrodes", "bobine_tesla", "flaque_eau", "petite_flaque",
		"torche_murale", "tuyau_vapeur", "boitier_electrique", "tuyau_fuite", "cable_suspendu"]
	for pid in ids:
		assert_true(MapCatalog.PREFABS.has(pid), "%s au catalogue" % pid)
		var it := MapCatalog.item("prefab:" + pid)
		assert_eq(String(it.cat), "prefabs", "%s : onglet Décor" % pid)
		var mount := MapCatalog.prefab_mount(pid)
		assert_eq(String(it.tool), "wall_item" if mount == "mur" else "floor_item", "%s : outil selon le montage" % pid)
		var n := EditorPrefabs.build(String(MapCatalog.PREFABS[pid].build))
		assert_true(n != null and n.get_child_count() > 0, "%s construit par le jeu" % pid)
		if n != null:
			assert_eq(n.find_children("*", "CollisionObject3D", true, false).size(), 0, "%s : collisions seulement par pavés du catalogue" % pid)
			n.free()
	assert_eq(MapCatalog.prefab_mount("torche_murale"), "mur")
	assert_eq(MapCatalog.prefab_mount("cable_suspendu"), "plafond")
	assert_eq(MapCatalog.blocking({"type": "prefab", "prefab": "bobine_tesla"}), "solide", "bobine Tesla : bloque")
	assert_eq(MapCatalog.blocking({"type": "prefab", "prefab": "flaque_eau"}), "non", "flaque : on marche dessus")
	assert_false(MapPrefabLib.groupable({"type": "prefab", "prefab": "torche_murale"}), "décor mural : pas dans un prefab groupe")
	assert_true(MapPrefabLib.groupable({"type": "prefab", "prefab": "buches"}), "bûches : groupables")
	# Pose : torche contre un mur (hauteur réglable), câble au plafond.
	var doc := ObjectsTest.objects_map()
	var tmpl: Dictionary = MapCatalog.item("prefab:torche_murale").make.duplicate(true)
	var rw := MapRules.place_wall_item(doc, 0, tmpl, Vector2(2.0, 0.4))
	assert_true(rw.ok, "torche murale contre le mur (%s)" % MapRules.why(rw))
	tmpl["id"] = "d90"
	tmpl["etage"] = 0
	tmpl["position"] = rw.position
	MapRules.apply_wall(tmpl, rw)
	MapCatalog.set_wall_light_height(tmpl, 2.4)
	doc.objets.append(tmpl)
	doc.objets.append({"id": "d91", "type": "prefab", "prefab": "cable_suspendu", "etage": 0, "position": [6.0, 6.0], "rot": 0})
	doc.objets.append({"id": "d92", "type": "prefab", "prefab": "bobine_tesla", "etage": 0, "position": [11.25, 7.25], "rot": 0})
	var m := EditorMap.from_texts(doc.file_texts())
	assert_eq(CustomMapGuard.check_texts(m.file_texts()).reasons, [], "décors acceptés par le contrôle des cartes reçues")
	var def := EditorMapDef.from_map(m, "perso:decor_fx")
	assert_true(def.is_valid(), "carte jouable")
	var by := {}
	for pr in def.layout_data.get("props", []):
		by[String(pr.get("id", ""))] = pr
	assert_true(by.has("d90") and by.has("d91"), "décors exportés")
	assert_near(float(by.d90.p[1]), 2.4, 0.01, "torche à 2,4 m")
	assert_near(float(by.d90.p[2]), 0.25 + MapGeom.WORLD_OFFSET, 0.01, "sur la face du mur")
	assert_near(float(by.d90.yaw), 0.0, 0.001, "tournée vers la pièce")
	assert_near(float(by.d91.p[1]), 3.2, 0.05, "câble sous le plafond (3,2 m)")
	assert_true(def.layout_data.get("blockers", []).size() >= 1, "bobine Tesla : pavé de collision")


# ------------------------------------------------------------------ conversion des cartes d'avant

func test_old_maps_are_converted_once_effect_plus_decor() -> void:
	var doc := ObjectsTest.objects_map()
	_fx(doc, "petit_feu", Vector2(5, 5), {"taille": 1.5})
	_fx(doc, "brasier", Vector2(11, 3))
	_fx(doc, "torche", Vector2(2.0, 0.0), {"mur": "n", "hauteur": 2.1})
	_fx(doc, "fuite", Vector2(0.0, 5.0), {"mur": "o"})
	_fx(doc, "flaque", Vector2(18, 6), {"rot": 30})
	_fx(doc, "poussiere", Vector2(18, 3))
	var texts := doc.file_texts()
	texts["carte.json"] = String(texts["carte.json"]).replace("\"format\": %d" % EditorMap.FORMAT, "\"format\": 10")
	assert_true(String(texts["objets.json"]).contains("\"taille\""), "carte d'avant : clé taille")
	assert_eq(CustomMapGuard.check_texts(texts).reasons, [], "carte au format 10 acceptée telle quelle")
	var m := EditorMap.from_texts(texts)
	assert_eq(m.format_read, 10)
	var decor := m.objets.filter(func(o): return String(o.get("type", "")) == "prefab")
	var names := decor.map(func(o): return String(o.prefab))
	names.sort()
	assert_eq(names, ["buches", "flaque_eau", "foyer_pierres", "petite_flaque", "torche_murale", "tuyau_fuite"], "un décor par objet d'effet")
	var effects := m.objets.filter(func(o): return String(o.get("type", "")) == "effet")
	assert_eq(effects.size(), 6, "tous les effets gardés")
	var by := {}
	for o in decor:
		by[String(o.prefab)] = o
	assert_eq(MapGeom.v2(by.buches.position), Vector2(5, 5), "bûches sous le petit feu")
	assert_eq(String(by.torche_murale.mur), "n", "torche sur le même mur")
	assert_near(float(by.torche_murale.hauteur), 2.1, 0.001, "torche à la hauteur de la flamme")
	assert_eq(MapGeom.v2(by.torche_murale.position), Vector2(2, 0), "torche au même endroit")
	assert_eq(int(by.flaque_eau.rot), 30, "flaque tournée comme l'effet")
	assert_true(MapGeom.v2(by.petite_flaque.position).x > 1.0, "flaque du filet d'eau devant le mur, là où l'eau tombe")
	var fire: Dictionary = effects.filter(func(o): return String(o.effet) == "petit_feu")[0]
	assert_false(fire.has("taille"), "taille convertie")
	assert_eq(fire.zone, [0.9, 0.9], "zone = zone par défaut × 1,5")
	# Réécrite au format 11, relue : rien n'est ajouté deux fois.
	var t11 := m.file_texts()
	assert_true(String(t11["carte.json"]).contains("\"format\": %d" % EditorMap.FORMAT) and EditorMap.FORMAT >= 11, "format 11")
	var m2 := EditorMap.from_texts(t11)
	assert_eq(m2.objets.size(), m.objets.size(), "relue : aucun décor en plus")
	assert_eq(m2.file_texts(), t11, "réécrite à l'identique")
	assert_eq(m2.split_legacy_effects(), 0, "conversion idempotente : décors déjà là")
	assert_eq(CustomMapGuard.check_texts(t11).reasons, [], "carte convertie acceptée")
	var dv := EditorMapDef.from_map(m2, "perso:convertie")
	assert_true(dv.is_valid(), "carte convertie jouable : %s" % str(dv.validator.errors().map(func(e): return String(e.fr))))


func test_repo_maps_have_no_effect_to_convert() -> void:
	# Cartes du dépôt : aucune n'a d'effet à convertir (sinon leurs JSON
	# seraient à réécrire au format 11).
	for dir in ["res://assets/maps/draft_arena/"]:
		var m := EditorMap.load_dir(dir)
		assert_true(m.load_errors.is_empty(), "%s lue" % dir)
		assert_eq(m.objets.filter(func(o): return String(o.get("type", "")) == "effet").size(), 0, "%s : aucun effet" % dir)


# ------------------------------------------------------------------ fichiers et jeu

func test_effect_settings_round_trip_and_export() -> void:
	var doc := ObjectsTest.objects_map()
	_fx(doc, "feux_follets", Vector2(5, 5), {"couleur": "#ff00ff", "intensite": 1.5, "zone": [3.0, 2.0, 2.0], "hauteur": 0.5})
	_fx(doc, "petit_feu", Vector2(4, 8), {"intensite": 1.0, "couleur": "#00ff00", "hauteur": 0.0})
	_fx(doc, "incendie", Vector2(18, 6), {"rot": 90})
	var torch: Dictionary = MapCatalog.item("effet:torche").make.duplicate(true)
	var rw := MapRules.place_wall_item(doc, 0, torch, Vector2(2.0, 0.4))
	assert_true(rw.ok, "flamme de torche posée")
	torch["id"] = doc.new_id("fx")
	torch["etage"] = 0
	torch["position"] = rw.position
	MapRules.apply_wall(torch, rw)
	doc.objets.append(torch)
	_fx(doc, "pluie_etincelles", Vector2(20, 4))
	var texts := doc.file_texts()
	assert_true(String(texts["carte.json"]).contains("\"format\": %d" % EditorMap.FORMAT) and EditorMap.FORMAT >= 11, "format 11 et plus")
	var m := EditorMap.from_texts(texts)
	var wisp: Dictionary = m.objets.filter(func(o): return String(o.get("effet", "")) == "feux_follets")[0]
	assert_eq(String(wisp.couleur), "#ff00ff", "couleur relue")
	assert_eq(wisp.zone, [3.0, 2.0, 2.0], "zone relue")
	var fire: Dictionary = m.objets.filter(func(o): return String(o.get("effet", "")) == "petit_feu")[0]
	for k in ["intensite", "couleur", "hauteur", "zone", "taille"]:
		assert_false(fire.has(k), "petit feu : « %s » par défaut ou sans objet, retirée" % k)
	assert_eq(EditorMap.from_texts(m.file_texts()).file_texts(), m.file_texts(), "relue puis réécrite à l'identique")
	assert_eq(CustomMapGuard.check_texts(m.file_texts()).reasons, [], "contrôle des cartes reçues : effets acceptés")
	assert_eq(m.objets.filter(func(o): return String(o.get("type", "")) == "prefab").size(), 0, "carte au format 11 : aucun décor ajouté")
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
	assert_eq(by.feux_follets.zone, [3.0, 2.0, 2.0], "zone exportée")
	assert_false(by.feux_follets.has("scale"), "plus de taille")
	assert_eq(by.petit_feu.zone, [0.6, 0.6, 0.0], "zone par défaut exportée")
	assert_false(by.petit_feu.has("color"), "le feu ne se teint pas")
	assert_near(float(by.torche.p[1]), 2.25, 0.01, "flamme de torche à 2,25 m (volume centré sur sa hauteur)")
	assert_eq(by.torche.zone, [0.3, 0.5, 0.6], "zone murale : largeur, portée, hauteur")
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
		if fx.fx_id == "feux_follets":
			assert_eq(fx.zone, Vector3(3.0, 2.0, 2.0), "zone reçue par l'effet")
	holder.queue_free()
	# Carte sans effet : description inchangée (pas de clé « effects »).
	assert_false(EditorMapDef.from_map(ObjectsTest.objects_map(), "perso:sans").layout_data.has("effects"), "sans effet : pas de clé")


func test_guard_checks_effects_strictly() -> void:
	var doc := ObjectsTest.objects_map()
	_fx(doc, "arc", Vector2(5, 5), {"rot": 45, "couleur": "#80a0ff", "zone": [3.0, 0.5]})
	_fx(doc, "brouillard", Vector2(7, 5), {"zone": [12.0, 6.0, 1.0]})
	doc.objets.append({"id": "d80", "type": "prefab", "prefab": "torche_murale", "etage": 0, "position": [2.0, 0.0], "mur": "n", "hauteur": 2.2})
	var texts := doc.file_texts()
	assert_eq(CustomMapGuard.check_texts(texts).reasons, [], "effets et décor mural acceptés")
	var objs := String(texts["objets.json"])
	var bad := [
		["effet inconnu", objs.replace("\"effet\":\"arc\"", "\"effet\":\"bombe\"")],
		["intensité hors bornes", objs.replace("\"effet\":\"arc\"", "\"effet\":\"arc\", \"intensite\":50")],
		["taille illisible", objs.replace("\"effet\":\"arc\"", "\"effet\":\"arc\", \"taille\":\"x\"")],
		["couleur illisible", objs.replace("\"couleur\":\"#80a0ff\"", "\"couleur\":\"bleu\"")],
		["clé inconnue", objs.replace("\"effet\":\"arc\"", "\"effet\":\"arc\", \"degats\":10")],
		["sans effet", objs.replace("\"effet\":\"arc\",", "")],
		["zone hors des bornes de l'effet", objs.replace("\"zone\":[3,0.5]", "\"zone\":[9,0.5]")],
		["zone hors des bornes absolues", objs.replace("\"zone\":[12,6,1]", "\"zone\":[60,6,1]")],
		["zone : mauvais nombre de dimensions", objs.replace("\"zone\":[3,0.5]", "\"zone\":[3,0.5,1]")],
		["zone illisible", objs.replace("\"zone\":[3,0.5]", "\"zone\":\"grande\"")],
		["réglage de mur sur un décor au sol", objs.replace("\"prefab\":\"torche_murale\"", "\"prefab\":\"buches\"")],
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
	# Paquet reçu en multijoueur (canonique) : la carte convertie passe.
	var pkg := CustomMapGuard.package_of(EditorMap.from_texts(texts))
	assert_true(CustomMapGuard.check_package(pkg.bytes, pkg.sha).ok, "paquet multijoueur accepté")


func test_review_map_is_playable_with_every_effect() -> void:
	var doc: EditorMap = load("res://tests/autotest/map_effects_look.gd").review_map()
	var def := EditorMapDef.from_map(doc, "perso:effets_revue")
	var errs: Array = def.validator.errors().map(func(m): return String(m.fr))
	assert_true(def.is_valid(), "carte de revue jouable : %s" % str(errs))
	assert_true(def.layout_data.get("effects", []).size() >= MapCatalog.EFFECTS.size(), "tous les effets exportés")
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
	assert_true(inv.cells.any(func(s): return s.item_id == "prefab:torche_murale"), "Décor : la torche murale")
	inv.show_category("effets")
	assert_eq(inv.cells.map(func(s): return s.item_id), MapCatalog.in_category("effets", "eau").map(func(it): return it.id), "sous-onglet gardé")
	ed.toggle_inventory()
	# Effet posé, choisi : ses réglages dans les propriétés (zone au lieu de taille).
	var o := ed.add_object({"type": "effet", "effet": "feux_follets", "position": [6.0, 6.0], "rot": 0}, 0)
	assert_true(String(o.id).begins_with("fx"), "identifiant fx (%s)" % o.id)
	ed.select(String(o.id))
	await wait_frames(2)
	var spins := ed.panels._props.find_children("*", "SpinBox", true, false)
	assert_true(spins.size() >= 5, "intensité, largeur, profondeur, hauteur de zone, hauteur (%d champs)" % spins.size())
	assert_eq(ed.panels._props.find_children("*", "ColorPickerButton", true, false).size(), 1, "couleur (effet qui se teint)")
	(spins[0] as SpinBox).value = 1.6
	assert_near(float(o.get("intensite", 0.0)), 1.6, 0.001, "intensité réglée")
	(spins[0] as SpinBox).value = 1.0
	assert_false(o.has("intensite"), "intensité par défaut : clé retirée")
	(spins[1] as SpinBox).value = 4.0
	assert_near(MapCatalog.effect_zone(ed.doc.find(String(o.id))).x, 4.0, 0.001, "largeur de zone réglée")
	# Poignées du plan : 8, et la poignée tirée agrandit la zone.
	var cur := ed.doc.find(String(o.id))
	assert_eq(ed.canvas.handles().size(), 8, "8 poignées de zone")
	var snap0 := ed.doc.snapshot()
	var res := ed.try_handle(cur.duplicate(true), 5, Vector2(10.0, 6.0), snap0)
	assert_true(res.ok, "poignée tirée (%s)" % MapRules.why(res))
	assert_near(MapCatalog.effect_zone(ed.doc.find(String(o.id))).x, 6.0, 0.001, "zone élargie à 6 m (bord gauche fixe)")
	var big := ed.try_handle(ed.doc.find(String(o.id)).duplicate(true), 5, Vector2(80.0, 6.0), ed.doc.snapshot())
	assert_true(big.ok and MapCatalog.effect_zone(ed.doc.find(String(o.id))).x <= 10.0, "bornée à 10 m")
	assert_false(ed.canvas.gizmo.ring_of(ed.doc.find(String(o.id))).is_empty(), "anneau Z (rotation)")
	ed.queue_free()
	await wait_frames(2)
