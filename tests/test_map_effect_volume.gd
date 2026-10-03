extends TestCase
## VOLUME des effets de l'éditeur de cartes (MapCatalog.effect_volume, docs/
## MAP_OBJECTS.md § 12) : tout ce qu'un effet affiche reste dans sa boîte,
## celle que l'éditeur dessine. Pour CHAQUE effet du catalogue, zones
## minimale, par défaut et maximale, intensités, plafonds bas et hauts :
##   - chaque couche de particules (émission + vitesse, gravité,
##     amortissement, turbulence bornée, rebonds sur le sol simulés au pas
##     d'une image + taille des particules : MapEffect.part_reach) tient dans
##     le volume ; rien sous le sol ni derrière le mur (ils le cachent) ;
##   - les arcs électriques (bouts et largeur, quelle que soit la caméra),
##     la source des lumières, le sol de collision ;
##   - la boîte de visibilité de chaque couche couvre le volume ;
##   - la boîte de l'éditeur (élévations, aperçu 3D, clic) = ce volume posé
##     où le jeu le pose (export de la carte).

const ObjectsTest := preload("res://tests/test_map_objects.gd")

## Tolérance (m) : arrondis de l'export, simulation.
const EPS := 0.01


## Zones à essayer pour l'effet `fid` : minimale, par défaut, maximale et
## mélangée (largeur au plus petit, le reste au plus grand).
static func _zones(fid: String) -> Array:
	var dims := MapCatalog.effect_dims(fid)
	var lo := []
	var hi := []
	var mix := []
	for i in dims.size():
		var b := MapCatalog.effect_zone_bounds(fid, dims[i])
		lo.append(b[0])
		hi.append(b[1])
		mix.append(b[0] if i == 0 else b[1])
	return [lo, [], hi, mix]


## Description « effects » de l'effet : zone, intensité, hauteur sous plafond.
static func _opts(fid: String, zone: Array, intensity: float, room_h: float) -> Dictionary:
	var d: Dictionary = MapCatalog.EFFECTS[fid]
	var o := {"intensity": intensity, "room_h": room_h}
	match String(d.mount):
		"mur":
			o["ground"] = minf(float(d.get("y", 1.5)), room_h - 0.2)
		"plafond":
			o["ground"] = room_h - 0.02
		_:
			o["ground"] = float(d.get("y", 0.0))
	if not zone.is_empty():
		var z := MapCatalog.effect_default_zone(fid)
		var keys := MapCatalog.effect_dims(fid)
		for i in keys.size():
			match String(keys[i]):
				"l":
					z.x = float(zone[i])
				"p":
					z.y = float(zone[i])
				"h":
					z.z = float(zone[i])
		o["zone"] = [z.x, z.y, z.z]
	return o


## Tout ce que l'effet `e` affiche est-il dans son volume ? Rend les écarts.
func _outside(e: MapEffect) -> Array:
	var out := []
	var vol := e.volume.grow(EPS)
	for p in e.parts:
		var r := e.part_reach(p, true)
		if not vol.encloses(r):
			out.append("couche %d (%s) : %s hors de %s" % [p.get_index(), p.draw_pass_1.get_class(), r, e.volume])
		var vis := AABB(p.visibility_aabb.position, p.visibility_aabb.size)
		if not (p.transform * vis).grow(0.001).encloses(e.volume):
			out.append("couche %d : boîte de visibilité %s plus petite que le volume" % [p.get_index(), vis])
	for l in e.lights:
		if not vol.has_point(l.position):
			out.append("lumière hors du volume : %s" % l.position)
	for i in e.arcs.size():
		for n in 25:
			e._aim_arc(i)
			var t: Transform3D = e.arcs[i].transform
			var span := t.basis.y.length()
			var dir := t.basis.y / maxf(span, 0.0001)
			var half_w := t.basis.x.length() * 0.5
			# Bouts de l'arc ± sa demi-largeur, en travers de l'arc (toute caméra).
			for s in [-0.5, 0.5]:
				var end: Vector3 = t.origin + t.basis.y * float(s)
				for k in 3:
					var m := half_w * sqrt(maxf(0.0, 1.0 - dir[k] * dir[k]))
					if end[k] - m < vol.position[k] or end[k] + m > vol.end[k]:
						out.append("arc %d hors du volume (axe %d : %.3f ± %.3f)" % [i, k, end[k], m])
						break
	if e.collider:
		if not is_equal_approx(e.floor_y, e.volume.position.y):
			out.append("sol de collision %.3f ailleurs qu'au bas du volume %.3f" % [e.floor_y, e.volume.position.y])
	for c in e.body.get_children():
		if c is GPUParticlesCollisionBox3D and not e.collider:
			out.append("sol de collision sans volume jusqu'au sol")
	return out


# ------------------------------------------------------------------ contenu

func test_every_effect_stays_in_its_volume() -> void:
	MapCatalog.items()
	for fid in MapCatalog.EFFECTS:
		var d: Dictionary = MapCatalog.EFFECTS[fid]
		var rooms := [3.2]
		if String(d.mount) == "plafond" or d.get("vol") is String:
			rooms = [2.8, 5.0]
		for room_h in rooms:
			for zone in _zones(fid):
				for it in ([0.25, 1.0, 2.0] if (zone as Array).is_empty() else [1.0]):
					var e := MapEffects.build(fid, _opts(fid, zone, float(it), float(room_h)))
					assert_true(e != null, "%s construit" % fid)
					if e == null:
						continue
					var bad := _outside(e)
					assert_eq(bad, [], "%s, zone %s, intensité %.2f, plafond %.1f m : tout dans le volume" % [fid, zone, it, room_h])
					e.free()
		# Plafond atteint (cap) : les nappes grossissent, toujours contenues.
		var big := _zones(fid)[2] as Array
		var e2 := MapEffects.build(fid, _opts(fid, big, 2.0, 3.2))
		assert_eq(_outside(e2), [], "%s, zone maximale, intensité 2 : tout dans le volume" % fid)
		e2.free()


func test_volume_follows_the_mount() -> void:
	# Au sol : de la hauteur de pose vers le haut (zone h ou « vol »), sous le plafond.
	var v := MapCatalog.effect_volume("poussiere", Vector3(3, 2, 2.5), 0.0, 3.2)
	assert_eq(v, AABB(Vector3(-1.5, 0, -1), Vector3(3, 2.5, 2)), "poussière : zone au sol, hauteur h")
	v = MapCatalog.effect_volume("poussiere", Vector3(3, 2, 8.0), 0.0, 3.2)
	assert_near(v.size.y, 3.2, 0.001, "jamais au-dessus du plafond")
	v = MapCatalog.effect_volume("brasier", Vector3(1.2, 1.2, 0), 0.0, 3.2)
	assert_near(v.size.y, float(MapCatalog.EFFECTS.brasier.vol), 0.001, "grand feu : hauteur du catalogue")
	v = MapCatalog.effect_volume("cendres", Vector3(3, 3, 0), 0.5, 3.2)
	assert_near(v.end.y, 2.7, 0.001, "cendres : jusqu'au plafond")
	# Au plafond : vers le bas, jusqu'au sol pour ce qui tombe.
	v = MapCatalog.effect_volume("pluie_etincelles", Vector3(1.5, 1.5, 0), 3.18, 3.2)
	assert_near(v.position.y, -3.18, 0.001, "pluie d'étincelles : jusqu'au sol")
	assert_near(v.end.y, 0.0, 0.001, "depuis le plafond")
	# Mural : centré sur sa hauteur, portée vers la pièce ; jusqu'au sol pour ce qui tombe.
	v = MapCatalog.effect_volume("vapeur", Vector3(0.6, 1.5, 0.6), 1.2, 3.2)
	assert_eq(v, AABB(Vector3(-0.3, -0.3, 0), Vector3(0.6, 0.6, 1.5)), "jet de vapeur : centré, portée")
	v = MapCatalog.effect_volume("soudure", Vector3(1.0, 1.6, 0.4), 1.3, 3.2)
	assert_near(v.position.y, -1.3, 0.001, "soudure : jusqu'au sol")
	assert_near(v.end.y, 0.2, 0.001, "soudure : haut de sa zone")
	for fid in MapCatalog.EFFECTS:
		var z := MapCatalog.effect_default_zone(fid)
		var vv := MapCatalog.effect_volume(fid, z, 1.0, 3.2)
		assert_true(vv.size.x > 0.0 and vv.size.y >= MapCatalog.EFFECT_MIN_VOL - 0.001 and vv.size.z > 0.0, "%s : volume non vide" % fid)
		assert_near(vv.size.x, z.x, 0.001, "%s : largeur de la zone" % fid)
		assert_near(vv.size.z, z.y, 0.001, "%s : profondeur (ou portée) de la zone" % fid)


# ------------------------------------------------------------------ boîte de l'éditeur

## Carte d'essai : chaque effet du catalogue posé (au sol, surélevé, au mur,
## au plafond avec descente), dans des pièces de plafonds différents.
static func _map_with_every_effect() -> EditorMap:
	var doc := ObjectsTest.objects_map()
	doc.pieces[1]["plafond"] = 5.0
	var spots := [Vector2(3, 3), Vector2(7, 3), Vector2(11, 3), Vector2(3, 7), Vector2(7, 7), Vector2(11, 7),
		Vector2(17, 3), Vector2(21, 3), Vector2(18, 7), Vector2(21, 8), Vector2(3, 13), Vector2(7, 13), Vector2(11, 13)]
	var walls := [Vector2(2.0, 0.0), Vector2(5.5, 0.0), Vector2(12.0, 0.0), Vector2(16.0, 0.0), Vector2(22.0, 0.0), Vector2(2.0, 16.0), Vector2(11.0, 16.0)]
	var i := 0
	var w := 0
	for fid in MapCatalog.EFFECTS:
		var it := MapCatalog.item("effet:" + fid)
		var o: Dictionary = it.make.duplicate(true)
		o["id"] = "fx_" + fid
		o["etage"] = 0
		if it.tool == "wall_item":
			var res := MapRules.place_wall_item(doc, 0, o, walls[w % walls.size()])
			w += 1
			o["position"] = res.position
			MapRules.apply_wall(o, res)
		else:
			o["position"] = MapGeom.arr(spots[i % spots.size()])
			i += 1
		match String(MapCatalog.EFFECTS[fid].mount):
			"plafond":
				o["descente"] = 0.3
			"sol":
				if fid == "braises":
					o["hauteur"] = 0.75
		doc.objets.append(o)
	return doc


func test_editor_box_is_the_game_volume() -> void:
	MapCatalog.items()
	var doc := _map_with_every_effect()
	var def := EditorMapDef.from_map(doc, "perso:volumes")
	var by := {}
	for fx in def.layout_data.get("effects", []):
		by[String(fx.eid)] = fx
	assert_eq(by.size(), MapCatalog.EFFECTS.size(), "chaque effet exporté")
	var v := MapRaster.build(doc).v
	for o in doc.objets:
		if String(o.get("type", "")) != "effet":
			continue
		var fid := String(o.effet)
		var fx: Dictionary = by.get(String(o.id), {})
		if fx.is_empty():
			continue
		var e := MapEffects.build(fid, fx)
		var ground := float(fx.ground)
		var want := Vector2(ground + e.volume.position.y, ground + e.volume.end.y)
		# Élévations (vues de côté, clic).
		var it := MapElevationItems.item_of(doc, v, o)
		assert_near(float(it.z0), want.x, EPS, "%s : bas de la boîte des élévations = volume" % fid)
		assert_near(float(it.z1), want.y, EPS, "%s : haut de la boîte des élévations = volume" % fid)
		# Aperçu 3D (surlignage orange, clic).
		var sp := MapPreviewWorld.effect_span(o, def.layout_data, doc.floor_height(0))
		assert_near(sp.x, want.x, EPS, "%s : bas de la boîte de l'aperçu 3D = volume" % fid)
		assert_near(sp.y, want.y, EPS, "%s : haut de la boîte de l'aperçu 3D = volume" % fid)
		# Au sol : le contour dessiné est la zone du volume.
		var bb := MapGeom.bbox(MapRules.effect_poly(o))
		var size := Vector2(e.volume.size.x, e.volume.size.z)
		if String(MapCatalog.EFFECTS[fid].mount) == "mur":
			var dv := MapGeom.item_wall_dir(o)
			size = Vector2(e.volume.size.x, e.volume.size.z) if absf(dv.y) > 0.5 else Vector2(e.volume.size.z, e.volume.size.x)
		assert_near(bb.size.x, size.x, EPS, "%s : largeur dessinée = volume" % fid)
		assert_near(bb.size.y, size.y, EPS, "%s : profondeur dessinée = volume" % fid)
		# Et dans ce volume, tout y est.
		assert_eq(_outside(e), [], "%s posé dans la carte : tout dans le volume" % fid)
		e.free()


# ------------------------------------------------------------------ format 13

## Hauteur (m au-dessus du sol) de la première couche de l'effet `fid` construit
## comme en jeu depuis la carte `m` (base de la flamme, arc, boule de la bobine).
static func _drawn_y(m: EditorMap, oid: String) -> float:
	var def := EditorMapDef.from_map(m, "perso:migration")
	for fx in def.layout_data.get("effects", []):
		if String(fx.eid) != oid:
			continue
		var e := MapEffects.build(String(fx.fx), fx)
		var y := float(fx.ground) + e.parts[0].position.y
		e.free()
		return y
	return NAN


func test_maps_before_format_13_keep_their_effects_in_place() -> void:
	MapCatalog.items()
	var doc := ObjectsTest.objects_map()
	var torch: Dictionary = MapCatalog.item("effet:torche").make.duplicate(true)
	var rw := MapRules.place_wall_item(doc, 0, torch, Vector2(2.0, 0.4))
	torch.merge({"id": "fx_t1", "etage": 0, "position": rw.position, "hauteur": 2.0}, true)
	MapRules.apply_wall(torch, rw)
	doc.objets.append(torch)
	doc.objets.append({"id": "fx_a1", "type": "effet", "effet": "arc", "etage": 0, "position": [5.0, 5.0], "hauteur": 1.2})
	doc.objets.append({"id": "fx_b1", "type": "effet", "effet": "tesla", "etage": 0, "position": [9.0, 5.0], "hauteur": 1.0})
	doc.objets.append({"id": "fx_c1", "type": "effet", "effet": "arc", "etage": 0, "position": [5.0, 8.0]})
	doc.objets.append({"id": "fx_p1", "type": "effet", "effet": "pluie_etincelles", "etage": 0, "position": [18.0, 4.0]})
	doc.objets.append({"id": "fx_f1", "type": "effet", "effet": "fumee_noire", "etage": 0, "position": [20.0, 7.0]})
	doc.objets.append({"id": "fx_f2", "type": "effet", "effet": "fumee_legere", "etage": 0, "position": [4.0, 13.0], "zone": [3.0, 3.0]})
	var texts := doc.file_texts()
	texts["carte.json"] = String(texts["carte.json"]).replace("\"format\": %d" % EditorMap.FORMAT, "\"format\": 12")
	# Où les dessinait le jeu au format 12 : flamme 0,27 m au-dessus de la
	# torche, arc et boule à leur hauteur.
	var m := EditorMap.from_texts(texts)
	assert_eq(m.format_read, 12, "carte lue au format 12")
	assert_near(float(m.find("fx_t1").hauteur), 2.45, 0.001, "torche : hauteur décalée de 0,45 m")
	assert_near(_drawn_y(m, "fx_t1"), 2.0 + 0.27, 0.01, "flamme toujours au bout de la torche")
	assert_near(_drawn_y(m, "fx_a1"), 1.2, 0.01, "arc toujours à 1,2 m")
	assert_near(_drawn_y(m, "fx_b1"), 1.0, 0.01, "boule toujours à 1 m")
	assert_false(m.find("fx_c1").has("hauteur"), "arc sans hauteur : rien d'écrit")
	assert_near(_drawn_y(m, "fx_c1"), 1.0, 0.01, "arc par défaut toujours à 1 m")
	assert_eq(m.find("fx_p1").zone, [0.5, 0.5], "pluie d'étincelles : zone par défaut d'avant écrite")
	assert_eq(m.find("fx_f1").zone, [1.5, 1.5], "fumée noire : zone par défaut d'avant écrite")
	assert_eq(m.find("fx_f2").zone, [3.0, 3.0], "zone écrite : inchangée")
	# Idempotent : enregistrée au format 13, relue sans rien changer.
	var t2 := m.file_texts()
	assert_true(String(t2["carte.json"]).contains("\"format\": %d" % EditorMap.FORMAT) and EditorMap.FORMAT >= 13, "réécrite au format 13 et plus")
	var m2 := EditorMap.from_texts(t2)
	assert_eq(m2.file_texts(), t2, "relue puis réécrite à l'identique")
	assert_near(float(m2.find("fx_t1").hauteur), 2.45, 0.001, "pas de second décalage")
	# Carte reçue en multijoueur au format 12 : acceptée, convertie.
	assert_eq(CustomMapGuard.check_texts(texts).reasons, [], "carte reçue au format 12 acceptée")
	assert_true(EditorMapDef.from_map(EditorMap.from_texts(texts), "perso:recue").is_valid(), "jouable après conversion")


func test_old_size_of_format_10_uses_the_old_default_zone() -> void:
	var doc := ObjectsTest.objects_map()
	doc.objets.append({"id": "fx_f1", "type": "effet", "effet": "fumee_noire", "etage": 0, "position": [20.0, 7.0], "taille": 2.0})
	doc.objets.append({"id": "fx_f2", "type": "effet", "effet": "brasier", "etage": 0, "position": [4.0, 4.0], "taille": 2.0})
	var texts := doc.file_texts()
	texts["carte.json"] = String(texts["carte.json"]).replace("\"format\": %d" % EditorMap.FORMAT, "\"format\": 10")
	var m := EditorMap.from_texts(texts)
	assert_eq(m.find("fx_f1").zone, [3.0, 3.0], "fumée noire : zone d'avant (1,5 m) × 2")
	assert_eq(m.find("fx_f2").zone, [2.4, 2.4], "grand feu : zone par défaut × 2 (inchangée)")
	assert_false(m.find("fx_f1").has("taille"), "« taille » retirée")


# ------------------------------------------------------------------ cas limites

func test_torch_flame_stays_on_its_torch_under_a_low_ceiling() -> void:
	var an := MapCatalog.effect_anchor("torche")
	assert_near(an, float(MapCatalog.EFFECTS.torche.y) - float(MapCatalog.PREFABS.torche_murale.y), 0.001, "flamme posée au-dessus de la torche par défaut")
	for rh in [2.0, 2.3, 2.6, 3.2]:
		for h in [1.8, 2.25, 2.6, 3.0]:
			var flame := MapVertical.effect_ground("mur", h, 0.0, rh, an)
			# Torche murale : bornée comme une applique (MapLayoutExport).
			var torch := clampf(h - an, MapCatalog.WALL_LIGHT_HEIGHT[0], maxf(MapCatalog.WALL_LIGHT_HEIGHT[0], rh - MapVertical.WALL_MARGIN))
			assert_near(flame - an, torch, 0.001, "plafond %.1f m, hauteur %.2f : flamme au bout de la torche" % [rh, h])


func test_low_wall_effect_never_goes_under_the_floor() -> void:
	for fid in ["vapeur", "torche"]:
		var z := MapCatalog.effect_default_zone(fid)
		z.z = MapCatalog.effect_zone_bounds(fid, "h")[1]
		var v := MapCatalog.effect_volume(fid, z, 0.1, 3.2)
		assert_true(v.position.y >= -0.1 - 0.001, "%s posé à 0,1 m : pas sous le sol (%.2f)" % [fid, v.position.y])
		var e := MapEffects.build(fid, {"zone": [z.x, z.y, z.z], "ground": 0.1, "room_h": 3.2})
		assert_near(e.floor_y, -0.1, 0.001, "%s : le sol au bas du volume" % fid)
		assert_eq(_outside(e), [], "%s posé bas : tout dans le volume" % fid)
		e.free()


# ------------------------------------------------------------------ coût

func test_building_many_effects_stays_fast() -> void:
	MapCatalog.items()
	var ids := MapCatalog.EFFECTS.keys()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var list := []
	for i in MapCatalog.MAX_EFFECTS:
		var fid: String = ids[i % ids.size()]
		var o := _opts(fid, [], rng.randf_range(0.25, 2.0), rng.randf_range(2.8, 4.0))
		var z := MapCatalog.effect_default_zone(fid)
		var k := rng.randf_range(0.6, 2.4)
		o["zone"] = [z.x * k, z.y * rng.randf_range(0.6, 2.0), z.z * k]
		list.append([fid, o])
	# À froid (trajectoires jamais simulées), comme au chargement d'une carte.
	MapEffects._motion_cache.clear()
	var made := []
	var t0 := Time.get_ticks_usec()
	for it in list:
		made.append(MapEffects.build(it[0], it[1]))
	var cold := (Time.get_ticks_usec() - t0) / 1000.0
	# Poignée de zone tirée : l'effet reconstruit à chaque pas.
	var worst := 0.0
	var total := 0.0
	for fid in ["incendie", "pluie_etincelles", "soudure", "brouillard", "cendres"]:
		var z := MapCatalog.effect_default_zone(fid)
		for n in 12:
			var t1 := Time.get_ticks_usec()
			made.append(MapEffects.build(fid, {"zone": [z.x + n * 0.05, z.y + n * 0.05, z.z + n * 0.02]}))
			var ms := (Time.get_ticks_usec() - t1) / 1000.0
			total += ms
			worst = maxf(worst, ms)
	print("    %d effets à froid : %.0f ms ; zone tirée : %.2f ms en moyenne (pire %.2f ms)" % [list.size(), cold, total / 60.0, worst])
	# Budgets avec marge (machine de test plus lente) : 200 ms et 4 ms visés.
	assert_true(cold < 600.0, "%d effets construits à froid en %.0f ms (600 au plus)" % [list.size(), cold])
	assert_true(total / 60.0 < 8.0, "zone tirée : %.2f ms par reconstruction (8 au plus)" % (total / 60.0))
	for e in made:
		e.free()
