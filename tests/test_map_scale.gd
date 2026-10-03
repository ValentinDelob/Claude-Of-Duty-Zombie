extends TestCase
## Échelle et rotation 3D du décor (docs/EDITOR_SCALE_ROTATE.md, MapScale,
## format 14) : ce qui change d'échelle type par type (§ 1.1), prefab qui
## contient un Pack-a-Punch bloqué et message qui le nomme, bornes, clés
## remises en ordre, aller-retour au format 14, carte d'avant inchangée,
## carte reçue hors bornes refusée, boîte orientée (rot 37°, incl 30°), sens
## des trois axes, décomposition, règles de pose (dessus, porteur, plafond).

const TMP := "res://tests/_out/test_map_scale"
const DecorFree := preload("res://tests/test_map_decor_free.gd")

## Prefab de la carte qui contient un Pack-a-Punch (définition lue telle
## quelle : la bibliothèque calcule ses parties non redimensionnables).
const PAP_DEF := {"format": 1, "nom": {"fr": "Coin Pack-a-Punch", "en": "Pack-a-Punch corner"}, "fp": [8, 6], "h": 1.8, "bloque": "solide",
	"parties": [{"decor": "pap", "pos": [-1.5, 0]}, {"decor": "sacs_sable", "pos": [0.5, -1]}, {"decor": "tonneaux", "pos": [0.5, 1]}]}
const GROUP_DEF := {"format": 1, "nom": {"fr": "Barricade", "en": "Barricade"}, "fp": [6, 4], "h": 1.5, "bloque": "solide",
	"parties": [{"decor": "caisses", "pos": [-0.5, 0]}, {"decor": "sacs_sable", "pos": [1.5, 0], "rot": 90}]}
const SLANT_DEF := {"format": 1, "nom": {"fr": "Biais", "en": "Slant"}, "fp": [6, 4], "h": 1.5, "bloque": "solide",
	"parties": [{"decor": "caisses", "pos": [0, 0], "rot": 45}]}


func before_each() -> void:
	EditorMap.root_override = ProjectSettings.globalize_path(TMP + "/maps")


func after_each() -> void:
	EditorMap.root_override = ""
	MapCatalog.set_map_prefabs({})


static func _o(prefab: String, extra := {}) -> Dictionary:
	var o := {"id": "d1", "type": "prefab", "prefab": prefab, "etage": 0, "position": [5.0, 5.0]}
	o.merge(extra, true)
	return o


# ------------------------------------------------------------------ § 1.1 type par type

func test_what_scales_type_by_type() -> void:
	# Décor du catalogue : au sol, mural, au plafond -> échelle ; inclinaison au sol seulement.
	for id in ["gravats", "poutre", "caisses", "tonneaux", "bureau", "epave_voiture", "flaque_eau", "bobine_tesla"]:
		assert_true(MapScale.scalable(_o(id)), "%s se redimensionne" % id)
		assert_true(MapScale.tiltable(_o(id)), "%s s'incline" % id)
	for id in ["torche_murale", "tuyau_vapeur", "boitier_electrique", "tuyau_fuite"]:
		assert_true(MapScale.scalable(_o(id)), "%s (mural) se redimensionne" % id)
		assert_false(MapScale.tiltable(_o(id)), "%s (mural) ne s'incline pas" % id)
		assert_true(MapScale.tilt_refusal(_o(id))[0].contains("mur"), "raison : suit son mur")
	assert_true(MapScale.scalable(_o("cable_suspendu")) and not MapScale.tiltable(_o("cable_suspendu")), "câble suspendu : échelle, pas d'inclinaison")
	# Jamais : objets de jeu, ouvertures, construction, luminaires, effets, caisse et baril historiques.
	var fixed := [{"type": "atout", "atout": "titan"}, {"type": "pap"}, {"type": "boite"}, {"type": "arme", "arme": "m14"},
		{"type": "courant"}, {"type": "levier"}, {"type": "teleporteur"}, {"type": "depart"}, {"type": "apparition"},
		{"type": "porte"}, {"type": "fenetre"}, {"type": "pilier"}, {"type": "escalier"}, {"type": "piege"}, {"type": "mur"},
		{"type": "bloc_invisible"}, {"type": "luminaire", "luminaire": "suspension"}, {"type": "lampe"}, {"type": "effet", "effet": "feu"},
		{"type": "caisse"}, {"type": "baril"}]
	for o in fixed:
		assert_false(MapScale.scalable(o), "%s ne change pas d'échelle" % o.type)
		assert_false(MapScale.tiltable(o), "%s ne s'incline pas" % o.type)
		assert_false(MapScale.scale_refusal(o).is_empty(), "%s : raison donnée" % o.type)
	assert_eq(MapScale.phrase({"type": "atout", "atout": "titan"})[0], "l'atout %s" % PerkDB.display_name("titan"))
	assert_eq(MapScale.phrase({"type": "pap"})[0], "un Pack-a-Punch")
	# Clés lues seulement sur un décor.
	assert_eq(MapScale.scale_of({"type": "pap", "echelle": [2, 2, 2]}), Vector3.ONE, "pas d'échelle pour un objet de jeu")


func test_map_prefab_with_pack_a_punch_is_blocked() -> void:
	MapCatalog.set_map_prefabs({"coin_pap": PAP_DEF, "barricade": GROUP_DEF, "biais": SLANT_DEF})
	var o := _o("map:coin_pap")
	assert_false(MapScale.scalable(o), "prefab avec un Pack-a-Punch : bloqué")
	assert_false(MapScale.tiltable(o), "et reste droit")
	assert_eq(MapScale.blockers_of(o).size(), 1, "un seul objet de jeu")
	var r := MapScale.scale_refusal(o)
	assert_eq(r[0], "Échelle impossible : « Coin Pack-a-Punch » contient un Pack-a-Punch (objet de jeu à taille fixe)", "message qui nomme l'objet")
	assert_eq(r[1], "Scale impossible: \"Pack-a-Punch corner\" contains a Pack-a-Punch (fixed-size game object)")
	assert_true(MapScale.tilt_refusal(o)[0].contains("reste droit"), "inclinaison : objet de jeu, reste droit")
	# Inventaire : la bulle le dit.
	var it := MapCatalog.item("prefab:map:coin_pap")
	assert_true(String(it.hint_fr).contains("échelle fixe (Pack-a-Punch)"), "bulle : échelle fixe (%s)" % it.hint_fr)
	# Groupe de décors : redimensionnable ; partie tournée en biais : uniforme seulement.
	assert_true(MapScale.scalable(_o("map:barricade")) and not MapScale.uniform_only(_o("map:barricade")), "groupe à 90° : par axe")
	assert_true(MapScale.uniform_only(_o("map:biais")), "partie à 45° : uniforme seulement")
	assert_false(MapScale.check_scale(_o("map:biais"), Vector3(2, 1, 1)).is_empty(), "échelle par axe refusée")
	assert_true(MapScale.check_scale(_o("map:biais"), Vector3(2, 2, 2)).is_empty(), "uniforme permise")
	# Nommage : deux noms au plus puis « et N autres » ; récursif.
	var many := {"parties": [{"decor": "pap"}, {"decor": "atout:titan"}, {"decor": "boite"}, {"decor": "grenades"}, {"decor": "map:coin_pap"}]}
	var names := MapScale.unscalable_parts(many, {"coin_pap": PAP_DEF})
	assert_eq(names.size(), 4, "quatre objets distincts (le Pack-a-Punch du prefab cité n'est compté qu'une fois)")
	assert_eq(MapScale.names_text(names)[0], "un Pack-a-Punch, l'atout %s et 2 autres" % PerkDB.display_name("titan"))
	# Sélection mixte (Q2) : bloquée, le message nomme l'élément.
	var g := MapScale.group_refusal([_o("caisses"), {"type": "atout", "atout": "titan"}])
	assert_eq(g[0], "Échelle impossible : la sélection contient l'atout %s" % PerkDB.display_name("titan"))
	assert_true(MapScale.group_refusal([_o("caisses"), _o("poutre")]).is_empty(), "sélection de décor : permise")


# ------------------------------------------------------------------ bornes et fichier

func test_bounds_and_tidy() -> void:
	var o := _o("caisses")
	MapScale.set_scale(o, Vector3(1.234, 0.1, 9))
	assert_true(Vector3(o.echelle[0], o.echelle[1], o.echelle[2]).is_equal_approx(Vector3(1.23, 0.25, 4.0)), "arrondi au pas, borné")
	MapScale.set_scale(o, Vector3.ONE)
	assert_false(o.has("echelle"), "[1, 1, 1] : clé retirée")
	MapScale.set_incl(o, Vector2(0.04, -200.0))
	assert_true(Vector2(o.incl[0], o.incl[1]).is_equal_approx(Vector2(0.0, 160.0)), "ramenée dans ]-180, 180], au dixième")
	MapScale.set_incl(o, Vector2.ZERO)
	assert_false(o.has("incl"), "[0, 0] : clé retirée")
	assert_false(MapScale.check_scale(_o("caisses"), Vector3(4.5, 1, 1)).is_empty(), "au-delà de ×4")
	assert_false(MapScale.check_scale(_o("caisses"), Vector3(0.2, 1, 1)).is_empty(), "sous ×0,25")
	# Épave de voiture (4,5 m) × 4 = 18 m : permis ; éboulement 5 m × 4 = 20 m : la limite.
	assert_true(MapScale.check_scale(_o("epave_voiture"), Vector3(4, 4, 4)).is_empty(), "18 m de long")
	# Flaque (1 cm de haut) × 0,25 : sous 5 cm de haut.
	assert_false(MapScale.check_scale(_o("flaque_eau"), Vector3(1, 1, 0.25)).is_empty(), "dimension finale sous 5 cm")
	# Remise en ordre d'un fichier écrit à la main.
	var bad := [_o("caisses", {"echelle": "x"}), _o("caisses", {"echelle": [1, 1, 1]}), _o("caisses", {"echelle": [NAN, 1, 1]}),
		_o("torche_murale", {"incl": [10, 0]}), _o("caisses", {"incl": [0, 0.02]}), {"id": "a", "type": "pap", "position": [1, 1], "echelle": [2, 2, 2]}]
	for b in bad:
		MapScale.tidy(b)
		assert_false(b.has("echelle") or b.has("incl"), "retirée : %s" % str(b))
	var ok := _o("caisses", {"echelle": [0.1, 5, 1.5], "incl": [0, 30.04]})
	MapScale.tidy(ok)
	assert_true(Vector3(ok.echelle[0], ok.echelle[1], ok.echelle[2]).is_equal_approx(Vector3(0.25, 4.0, 1.5)), "bornée")
	assert_true(Vector2(ok.incl[0], ok.incl[1]).is_equal_approx(Vector2(0.0, 30.0)), "au dixième")
	MapCatalog.set_map_prefabs({"coin_pap": PAP_DEF})
	var blocked := _o("map:coin_pap", {"echelle": [2, 2, 2], "incl": [10, 0]})
	var msg := MapScale.tidy(blocked)
	assert_false(blocked.has("echelle") or blocked.has("incl"), "prefab bloqué : échelle et inclinaison retirées")
	assert_true(not msg.is_empty() and String(msg[0]).contains("Pack-a-Punch"), "avec un message qui nomme l'objet")


static func _scaled_map() -> EditorMap:
	var doc := DecorFree.two_rooms()
	DecorFree._obj(doc, {"type": "prefab", "prefab": "caisses", "position": [4.0, 4.0], "echelle": [1.5, 1.5, 1.5]})
	DecorFree._obj(doc, {"type": "prefab", "prefab": "poutre", "position": [19.0, 5.5], "incl": [0, 30], "rot": 37})
	DecorFree._obj(doc, {"type": "prefab", "prefab": "torche_murale", "position": [2.0, 10.0], "mur": "s", "echelle": [1, 1, 2]})
	return doc


func test_format_14_round_trip_and_older_maps() -> void:
	var doc := _scaled_map()
	var texts := doc.file_texts()
	assert_true(String(texts["carte.json"]).contains("\"format\": 14"), "format 14")
	assert_true(String(texts["objets.json"]).contains("\"echelle\":[1.5,1.5,1.5]"), "échelle écrite")
	assert_true(String(texts["objets.json"]).contains("\"incl\":[0,30]"), "inclinaison écrite (entiers sans décimale)")
	var back := EditorMap.from_texts(texts)
	assert_eq(back.load_errors, [], "relue sans message")
	assert_eq(back.file_texts(), texts, "réécrite à l'identique")
	# Valeurs par défaut jamais écrites.
	var plain := DecorFree.two_rooms()
	DecorFree._obj(plain, {"type": "prefab", "prefab": "caisses", "position": [4.0, 4.0], "echelle": [1, 1, 1], "incl": [0, 0]})
	var pt := EditorMap.from_texts(plain.file_texts()).file_texts()
	assert_false(String(pt["objets.json"]).contains("echelle") or String(pt["objets.json"]).contains("incl"), "défauts retirés")
	# Carte au format 13 : lue telle quelle (objets identiques), réécrite au format 14.
	var old := DecorFree.two_rooms()
	DecorFree._obj(old, {"type": "prefab", "prefab": "caisses", "position": [4.0, 4.0], "rot": 90})
	var t13 := old.file_texts()
	t13["carte.json"] = String(t13["carte.json"]).replace("\"format\": %d" % EditorMap.FORMAT, "\"format\": 13")
	var m13 := EditorMap.from_texts(t13)
	assert_eq(m13.format_read, 13)
	assert_eq(m13.file_texts()["objets.json"], t13["objets.json"], "objets d'une carte 13 inchangés")
	# Carte au format 14 lue par un jeu au format 13 : refusée (format plus récent).
	assert_true(CustomMapGuard.check_texts(texts).ok, "carte au format 14 acceptée par ce jeu")


func test_received_map_out_of_bounds_is_refused() -> void:
	var texts := _scaled_map().file_texts()
	assert_eq(CustomMapGuard.check_texts(texts).reasons, [], "carte valide acceptée")
	var cases := {
		"[1.5,1.5,1.5]": ["\"x\"", "[5,1,1]", "[0,1,1]", "[1,1]", "[1,1,1,1]", "[\"1\",1,1]", "{\"x\":1}"],
		"[0,30]": ["[0,200]", "[\"a\",0]", "[0]", "30"],
	}
	for good in cases:
		for badv in cases[good]:
			var t := texts.duplicate()
			t["objets.json"] = String(texts["objets.json"]).replace(good, badv)
			assert_false(CustomMapGuard.check_texts(t).ok, "refusée : %s" % badv)
	# Inclinaison d'un décor mural, échelle sur un objet de jeu.
	var t1 := texts.duplicate()
	t1["objets.json"] = String(texts["objets.json"]).replace("\"echelle\":[1,1,2]", "\"echelle\":[1,1,2],\"incl\":[10,0]")
	var r1 := CustomMapGuard.check_texts(t1)
	assert_false(r1.ok, "inclinaison d'un décor mural refusée")
	var t2 := texts.duplicate()
	t2["objets.json"] = String(texts["objets.json"]).replace("\"depart\":true", "\"depart\":true,\"echelle\":[2,2,2]")
	assert_false(CustomMapGuard.check_texts(t2).ok, "échelle d'une boîte mystère refusée")
	# Emprise finale de plus de 20 m (mur effondré 6 m × 4).
	var t3 := texts.duplicate()
	t3["objets.json"] = String(texts["objets.json"]).replace("\"prefab\":\"caisses\"", "\"prefab\":\"eboulis\"").replace("[1.5,1.5,1.5]", "[4,1,1]")
	assert_false(CustomMapGuard.check_texts(t3).ok, "emprise de 24 m refusée")
	# Prefab de la carte qui contient un objet de jeu : échelle refusée.
	assert_false(MapScale.check_object(_o("map:coin_pap", {"echelle": [2, 2, 2]}), PAP_DEF, MapScale.unscalable_parts(PAP_DEF)).is_empty(),
		"échelle d'un prefab qui contient un objet de jeu")
	assert_true(MapScale.check_object(_o("map:coin_pap"), PAP_DEF, MapScale.unscalable_parts(PAP_DEF)).is_empty(), "sans échelle : accepté")
	assert_false(MapScale.check_object(_o("map:biais", {"echelle": [2, 1, 1]}), SLANT_DEF, []).is_empty(), "parties en biais : uniforme exigée")


# ------------------------------------------------------------------ orientation (§ 3.1)

func test_axis_senses_and_decomposition() -> void:
	# Dessus (Z) : comme « rot » d'avant, l'est part vers le sud.
	assert_true((MapScale.rz(90) * Vector3(1, 0, 0)).is_equal_approx(Vector3(0, 1, 0)), "Z +90 : est -> sud (horaire vu de dessus)")
	# Avant (regard vers le nord, X à droite, Z en haut) : horaire = le bout est descend.
	assert_true((MapScale.ry(30) * Vector3(1, 0, 0)).z < -0.49, "Y +30 : le bout est descend")
	# Droite (regard vers l'ouest, nord à droite, Z en haut) : horaire = le bout nord descend.
	assert_true((MapScale.rx(30) * Vector3(0, -1, 0)).z < -0.49, "X +30 : le bout nord descend")
	# Sans inclinaison : même orientation de jeu qu'avant (lacet -rot autour de y).
	var g := MapScale.to_game(MapScale.orient(37, Vector2.ZERO))
	assert_true(g.is_equal_approx(Basis(Vector3.UP, -deg_to_rad(37.0))), "jeu : Basis(UP, -rot)")
	# Décomposition : aller-retour.
	for c in [[37.0, Vector2(0, 30)], [0.0, Vector2(20, 0)], [250.0, Vector2(-45, 60)], [10.0, Vector2(170, -30)]]:
		var m := MapScale.orient(float(c[0]), c[1])
		var d := MapScale.decompose(m)
		assert_true(MapScale.orient(float(d.rot), d.incl).is_equal_approx(m), "décomposition %s" % str(c))
	# Anneau d'un axe du monde : Y de +30 puis Z de 90 -> rot 90, incl Y 30.
	var o := _o("poutre")
	MapScale.set_orientation(o, MapScale.axis_rot(2, 90) * MapScale.axis_rot(1, 30) * MapScale.matrix(o))
	assert_eq(MapGeom.rot_of(o), 90)
	assert_true(Vector2(o.incl[0], o.incl[1]).is_equal_approx(Vector2(0.0, 30.0)), str(o.incl))
	# Puis X du monde de +90 sur un objet tourné de 90° : c'est une inclinaison Y dans son repère.
	var p := _o("poutre", {"rot": 90})
	MapScale.set_orientation(p, MapScale.axis_rot(0, 20) * MapScale.matrix(p))
	assert_eq(MapGeom.rot_of(p), 90)
	assert_near(float(p.incl[1]), -20.0, 0.05, "X du monde = -Y local après 90°")


func test_oriented_box_rot_37_incl_30() -> void:
	var o := _o("poutre", {"rot": 37, "incl": [0, 30]})
	# Poutre 7 × 2 × 1,8 m inclinée de 30° : haut à 5,06 m (maquette, écran 2).
	assert_near(MapScale.height(o), 5.059, 0.002, "hauteur de la boîte orientée")
	var lo := INF
	for c in MapScale.corners(o):
		lo = minf(lo, (c as Vector3).z)
	assert_near(lo, 0.0, 0.0001, "point le plus bas posé au sol (z)")
	# Emprise au sol : rectangle de 2 × (3,5 cos 30 + 0,9 sin 30) × 2, tourné de 37°.
	var poly := MapScale.ground_poly(o)
	assert_near(absf(MapScale._signed_area(poly)), 2.0 * (3.5 * cos(PI / 6) + 0.9 * sin(PI / 6)) * 2.0, 0.01, "aire de la projection")
	assert_true(MapGeom.contains(poly, Vector2(5, 5)), "centre dedans")
	assert_true(MapRaster.free_rot(o), "emprise en polygone")
	assert_eq(MapRaster.floor_poly(o), poly, "MapRaster : la projection")
	# Cases bloquées : toutes celles que touche la projection (prudent).
	var cells := MapRaster.floor_cells(o)
	assert_true(cells.size() >= MapGeom.poly_cells(poly).size(), "au moins les cases au centre dedans")
	# Échelle seule : rectangle mis à l'échelle, même centre.
	var s := _o("caisses", {"echelle": [1.5, 1.5, 1.5]})
	assert_true(MapScale.dims(s).is_equal_approx(Vector3(3.75, 3.0, 2.25)), "2,50 × 2,00 × 1,50 -> 3,75 × 3,00 × 2,25 m (maquette)")
	assert_eq(MapRules.footprint_rect(s), Rect2(5 - 1.875, 5 - 1.5, 3.75, 3.0))
	# Décalage de l'origine du modèle en jeu : nul sans inclinaison.
	assert_eq(MapScale.floor_offset(s), Vector3.ZERO)
	# Pavé de collision : centre et taille × échelle, axes échangés à 90°.
	var bx := MapScale.scaled_box(_o("caisses", {"echelle": [2, 1, 3]}), {"center": [0.5, 1, 0.2], "size": [1, 2, 0.5], "yaw": PI / 2})
	assert_true((bx.center as Vector3).is_equal_approx(Vector3(1.0, 3.0, 0.2)), "centre × (sx, sz, sy)")
	assert_true((bx.size as Vector3).is_equal_approx(Vector3(1.0, 6.0, 1.0)), "taille dans le repère du pavé (90° : x <- sy, z <- sx)")


# ------------------------------------------------------------------ règles de pose

func test_rules_with_scale_and_tilt() -> void:
	var doc := DecorFree.two_rooms()
	var desk := DecorFree._obj(doc, {"type": "prefab", "prefab": "bureau", "position": [4.0, 4.0], "echelle": [1, 1, 2]})
	assert_near(MapRules.support_height(desk), 1.56, 0.001, "dessus du bureau × 2")
	assert_near(MapVertical.decor_top(desk), 1.56, 0.001)
	var sacs := DecorFree._obj(doc, {"type": "prefab", "prefab": "sacs_sable", "position": [10.0, 4.0]})
	var top := DecorFree._obj(doc, {"type": "prefab", "prefab": "caisses", "position": [10.0, 4.0], "z": 0.9})
	var v := MapRaster.build(doc).v
	assert_true(MapVertical.rests_ok(doc, top), "caisses posées sur les sacs")
	# Décor porteur : ne s'incline ni ne change d'échelle seul.
	var tilted := sacs.duplicate(true)
	MapScale.set_incl(tilted, Vector2(0, 20))
	var r := MapScale.check(doc, v, tilted, sacs)
	assert_false(r.ok, "porteur incliné refusé")
	assert_eq(String(r.get("fr", "")), "un décor est posé dessus : sélectionnez-les ensemble")
	# Un décor incliné ne porte rien.
	assert_false(MapScale.carries(tilted))
	assert_eq(MapRules.support_height(tilted), 0.0)
	# Plafond : poutre inclinée de 30° (5,06 m) sous 3,20 m : refusée.
	var beam := DecorFree._obj(doc, {"type": "prefab", "prefab": "poutre", "position": [7.0, 7.5]})
	v = MapRaster.build(doc).v
	var b2 := beam.duplicate(true)
	MapScale.set_incl(b2, Vector2(0, 30))
	var rb := MapScale.check(doc, v, b2, beam)
	assert_false(rb.ok, "trop haut")
	assert_eq(String(rb.get("fr", "")), "trop haut pour le plafond (3,20 m)")
	MapScale.set_incl(b2, Vector2(0, 10))
	assert_true(MapScale.check(doc, v, b2, beam).ok, "10° : tient sous le plafond (%s)" % str(MapScale.check(doc, v, b2, beam)))
	# Pack-a-Punch : refus qui le nomme ; carte d'un prefab bloqué.
	var pap := {"id": "x99", "type": "pap", "etage": 0, "position": [3.0, 0.0], "mur": "n", "echelle": [2, 2, 2]}
	assert_false(MapScale.check(doc, v, pap).ok)
	# Agrandie, la pile de caisses chevauche le bureau.
	var cr := DecorFree._obj(doc, {"type": "prefab", "prefab": "caisses", "position": [7.0, 4.0]})
	v = MapRaster.build(doc).v
	var big := cr.duplicate(true)
	MapScale.set_scale(big, Vector3(2.5, 2.5, 1))
	var rc := MapScale.check(doc, v, big, cr)
	assert_false(rc.ok, "chevauchement refusé")
	assert_true(String(rc.get("fr", "")).begins_with("chevauche"), String(rc.get("fr", "")))
	# Validateur : décor incliné, cases bloquées sur sa projection ; pas d'erreur.
	var doc2 := _scaled_map()
	var v2 := MapRaster.build(doc2).v
	v2.analyze()
	assert_eq(v2.errors().map(func(e): return e.fr), [], "carte au format 14 valide")
