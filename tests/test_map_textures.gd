extends TestCase
## Textures de la carte (format 16, MapTextureLib, MapTextureTools,
## MapAgentTextures) : définition (texture.json) contrôlée clé par clé, images
## PNG / JPEG (fabriquées ici par Image : aucun binaire dans le dépôt)
## vérifiées puis décodées à la réception, enregistrement et relecture du
## dossier de la carte, textes de la carte, archive, paquet réseau, cache,
## repli sur la surface par défaut (texture absente : avertissement du
## validateur), export (« tex-<tid> », « map_textures ») et matériau du jeu,
## validation des opérations (MapOps : « map:<tid> » connu / inconnu), chaque
## commande MCP en succès et en refus (invité de session compris).

const TMP := "res://tests/_out/test_map_textures"
const DecorFree := preload("res://tests/test_map_decor_free.gd")


func before_each() -> void:
	EditorMap.root_override = ProjectSettings.globalize_path(TMP + "/maps")
	CustomMapGuard.cache_override = ProjectSettings.globalize_path(TMP + "/cache")


func after_each() -> void:
	EditorMap.root_override = ""
	CustomMapGuard.cache_override = ""
	MapCatalog.set_map_prefabs({})


# ------------------------------------------------------------------ outils

## Image de test : damier de deux couleurs, `w` × `h` px.
static func checker(w := 64, h := 32, a := Color(0.8, 0.2, 0.1), b := Color(0.1, 0.3, 0.8)) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			@warning_ignore("integer_division")
			img.set_pixel(x, y, a if ((x / 8) + (y / 8)) % 2 == 0 else b)
	return img


static func png(w := 64, h := 32) -> PackedByteArray:
	return checker(w, h).save_png_to_buffer()


static func jpg(w := 64, h := 32) -> PackedByteArray:
	return checker(w, h).save_jpg_to_buffer(0.9)


static func _write(path: String, b: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var fa := FileAccess.open(path, FileAccess.WRITE)
	fa.store_buffer(b)
	fa.close()


## Deux salles (DecorFree) ; la texture « carreaux » (PNG) importée et posée
## au sol de la première salle.
static func textured_map() -> EditorMap:
	var doc := DecorFree.two_rooms()
	var r := MapTextureTools.import_bytes(doc, png(), {"nom": "Carreaux", "taille": 1.5, "id": "carreaux"})
	assert(r.has("tid"))
	doc.pieces[0]["surface_sol"] = MapTextureLib.ref("carreaux")
	return doc


## Matériau du sol des salles de la zone de jeu `letter` (« a » : zone de
## départ, la salle A ; les morceaux de sol s'appellent « a0_1 »...).
static func _floor_mat(data: Dictionary, letter: String) -> String:
	for r in data.rooms:
		if String(r.id).begins_with(letter + "0_"):
			return String(r.get("floor_mat", ""))
	return ""


static func _has_warning(v: MapValidator, part: String) -> bool:
	return v.warnings().any(func(m): return String(m.fr).contains(part))


# ------------------------------------------------------------------ format

func test_def_and_ids() -> void:
	assert_true(MapTextureLib.tid_ok("brique_rouge_2"), "identifiant admis")
	for bad in ["", "A", "a__b", "_a", "a_", "a/b", "a.b", "x".repeat(33), 3]:
		assert_false(MapTextureLib.tid_ok(bad), "identifiant refusé : %s" % str(bad))
	assert_eq(MapTextureLib.tid_of("map:sol_bleu"), "sol_bleu")
	assert_eq(MapTextureLib.tid_of("concrete"), "", "surface du jeu : pas une texture de la carte")
	assert_eq(MapTextureLib.parse_key("textures/sol/image.png"), ["sol", "image.png"])
	assert_eq(MapTextureLib.parse_key("textures/sol/image.gif"), [], "extension non admise")
	assert_eq(MapTextureLib.parse_key("textures/../image.png"), [], "chemin refusé")
	var good := {"format": 1, "nom": {"fr": "Sol", "en": "Floor"}, "taille": 2.0}
	assert_eq(MapTextureLib.check_def(good), [], "définition minimale admise")
	var s := MapTextureLib.sanitize({"nom": {"fr": "Sol"}, "taille": 1.234, "rugosite": 0.85, "metal": 0.3, "teinte": "#FFFFFF"})
	assert_eq(s, {"format": 1, "nom": {"fr": "Sol"}, "taille": 1.23, "metal": 0.3}, "défauts retirés, nombres arrondis : %s" % str(s))
	for bad in [{"nom": {"fr": "Sol"}, "taille": 2, "script": "x"}, {"nom": {"fr": "Sol"}, "taille": 0.0},
			{"nom": {"fr": "<b>Sol</b>"}, "taille": 2}, {"nom": {"fr": "Sol"}, "taille": 2, "rugosite": 2},
			{"nom": {"fr": "Sol"}, "taille": 2, "teinte": "rouge"}, {"taille": 2}, []]:
		assert_false(MapTextureLib.check_def(bad).is_empty(), "définition refusée : %s" % str(bad))


func test_image_checks() -> void:
	assert_eq(MapTextureLib.file_for(png()), "image.png")
	assert_eq(MapTextureLib.file_for(jpg()), "image.jpg")
	assert_eq(MapTextureLib.file_for(png(), true), "normal.png")
	assert_eq(MapTextureLib.check_image(png(), "image.png"), [], "PNG valide")
	assert_eq(MapTextureLib.check_image(jpg(), "image.jpg"), [], "JPEG valide")
	assert_false(MapTextureLib.check_image(png(), "image.jpg").is_empty(), "PNG nommé .jpg refusé")
	assert_false(MapTextureLib.check_image("pas une image".to_utf8_buffer(), "image.png").is_empty(), "texte refusé")
	# PNG tronqué : en-tête lisible, données abîmées : le vrai décodage refuse.
	var cut := png().slice(0, 40)
	assert_true(MapTextureLib.check_header(cut, "image.png").is_empty(), "en-tête du PNG tronqué lisible")
	assert_false(MapTextureLib.check_image(cut, "image.png").is_empty(), "PNG tronqué refusé au décodage")
	# Côté plus grand que la limite du moteur (lu dans l'en-tête, jamais décodé).
	var big := png()
	big.encode_u32(16, 0)
	big[16] = 0x00
	big[17] = 0x00
	big[18] = 0x4E
	big[19] = 0x20   # largeur 20000
	assert_false(MapTextureLib.check_header(big, "image.png").is_empty(), "20000 px de côté refusé")
	var img := MapTextureLib.decode(png(64, 32), "image.png")
	assert_true(img != null and img.get_width() == 64 and img.get_height() == 32, "décodé depuis les octets")
	var avg := Color.html(MapTextureLib.average_color(img))
	assert_true(avg.r > 0.3 and avg.b > 0.3, "couleur moyenne entre les deux couleurs du damier : %s" % avg.to_html(false))


# ------------------------------------------------------------------ dossier, textes, archive

func test_save_load_dir() -> void:
	var doc := textured_map()
	doc.textures["carreaux"]["rugosite"] = 0.4
	assert_true(MapTextureTools.update(doc, "carreaux", {"rugosite": 0.4, "normale": png(16, 16)}).has("def"), "carte des normales ajoutée")
	var dir := EditorMap.map_dir("tex_dossier")
	EditorMap.delete_map(dir)
	assert_eq(doc.save_dir(dir), OK, "enregistrée")
	assert_true(FileAccess.file_exists(dir.path_join("textures/carreaux/texture.json")), "texture.json dans le dossier")
	assert_true(FileAccess.file_exists(dir.path_join("textures/carreaux/image.png")), "image.png dans le dossier")
	assert_true(FileAccess.file_exists(dir.path_join("textures/carreaux/normal.png")), "normal.png dans le dossier")
	assert_eq(FileAccess.get_file_as_bytes(dir.path_join("textures/carreaux/image.png")), MapTextureLib.image_bytes(doc.texture_files, "carreaux"), "octets de l'image identiques")
	var c: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("carte.json")))
	assert_eq(int(c.format), EditorMap.FORMAT, "écrite au format courant")
	var back := EditorMap.load_dir(dir)
	assert_eq(back.load_errors, [], "relue sans erreur")
	assert_eq(back.textures, doc.textures, "définitions relues")
	assert_true(back.same_as(doc), "relue à l'identique (textes de la carte)")
	assert_eq(String(back.pieces[0].surface_sol), "map:carreaux")
	# Image remplacée par un JPEG, carte des normales retirée : fichiers d'avant effacés.
	assert_true(MapTextureTools.update(back, "carreaux", {"image": jpg(), "retirer_normale": true}).has("def"))
	assert_eq(back.save_dir(dir), OK)
	assert_true(FileAccess.file_exists(dir.path_join("textures/carreaux/image.jpg")) and not FileAccess.file_exists(dir.path_join("textures/carreaux/image.png")), "png remplacé par jpg")
	assert_false(FileAccess.file_exists(dir.path_join("textures/carreaux/normal.png")), "carte des normales effacée")
	# Texture retirée : dossier effacé.
	back.pieces[0].erase("surface_sol")
	MapTextureLib.remove(back, "carreaux")
	assert_eq(back.save_dir(dir), OK)
	assert_false(DirAccess.dir_exists_absolute(dir.path_join("textures")), "dossier textures/ effacé")
	EditorMap.delete_map(dir)


func test_old_format_read() -> void:
	var doc := DecorFree.two_rooms()
	var texts := doc.file_texts()
	var c: Dictionary = JSON.parse_string(texts["carte.json"])
	c["format"] = 14
	texts["carte.json"] = JSON.stringify(c)
	var m := EditorMap.from_texts(texts)
	assert_eq(m.load_errors, [], "format 14 lu tel quel")
	assert_eq(m.format_read, 14)
	assert_true(m.textures.is_empty())
	assert_false(m.file_texts().keys().any(func(k): return String(k).begins_with("textures/")), "aucune entrée de texture écrite")


func test_texts_snapshot_archive_package() -> void:
	var doc := textured_map()
	var texts := doc.file_texts()
	assert_true(texts.has("textures/carreaux/texture.json") and texts.has("textures/carreaux/image.png"), "entrées de texture dans les textes")
	var m := EditorMap.from_texts(texts)
	assert_true(m.same_as(doc), "textes relus à l'identique")
	# Instantané (session, annulation) : définitions seulement ; copie : images aussi.
	var snap := doc.snapshot()
	assert_true(snap.has("textures") and not str(snap).contains(String(doc.texture_files.values()[0]).left(40)), "instantané sans les images")
	var dup := doc.duplicate_map()
	assert_true(dup.same_as(doc), "copie de la carte avec ses images")
	var guest := EditorMap.new()
	guest.restore(snap)
	assert_eq(guest.textures, doc.textures, "invité : définitions reçues")
	assert_false(MapTextureLib.usable(guest, "carreaux"), "invité : pas d'image")
	# Archive .zip : image en binaire, relue identique.
	var zp := ProjectSettings.globalize_path(TMP + "/carte_tex.zip")
	DirAccess.make_dir_recursive_absolute(zp.get_base_dir())
	assert_eq(doc.export_zip(zp), OK, "archive écrite")
	var z := ZIPReader.new()
	z.open(zp)
	assert_eq(z.read_file("textures/carreaux/image.png"), MapTextureLib.image_bytes(doc.texture_files, "carreaux"), "image binaire dans l'archive")
	z.close()
	var zm := EditorMap.import_zip(zp)
	assert_eq(zm.load_errors, [], "archive importée")
	assert_true(zm.same_as(doc), "archive relue à l'identique")
	# Paquet réseau (format 2) et cache.
	var pk := CustomMapGuard.package_of(doc)
	var un := CustomMapGuard.unpack(pk.bytes)
	assert_true(un.ok, "paquet relu : %s" % str(un.reasons))
	assert_eq(un.texts, pk.texts, "textes du paquet")
	assert_eq(CustomMapGuard.store(pk.sha, pk.texts), OK, "enregistrée dans le cache")
	assert_true(FileAccess.file_exists(CustomMapGuard.cache_dir(pk.sha).path_join("textures/carreaux/image.png")), "image dans le cache")
	var lc := CustomMapGuard.load_cached(pk.sha)
	assert_true(lc.ok, "relue du cache : %s" % str(lc.reasons))
	assert_true((lc.map as EditorMap).same_as(doc), "carte du cache identique")


# ------------------------------------------------------------------ contrôle des cartes reçues

func test_guard() -> void:
	var doc := textured_map()
	var texts := doc.file_texts()
	assert_eq(CustomMapGuard.check_texts(texts).reasons, [], "carte avec une texture PNG acceptée")
	var j := textured_map()
	assert_true(MapTextureTools.update(j, "carreaux", {"image": jpg()}).has("def"))
	assert_eq(CustomMapGuard.check_texts(j.file_texts()).reasons, [], "texture JPEG acceptée")
	var refuse := func(t: Dictionary, why: String) -> void:
		var r := CustomMapGuard.check_texts(t)
		assert_false(r.ok, "refusée : %s" % why)
	var t := texts.duplicate()
	t["textures/carreaux/image.png"] = Marshalls.raw_to_base64("<script>".to_utf8_buffer())
	refuse.call(t, "pas une image")
	t = texts.duplicate()
	t["textures/carreaux/image.png"] = Marshalls.raw_to_base64(png().slice(0, 40))
	refuse.call(t, "PNG tronqué (décodage)")
	t = texts.duplicate()
	t.erase("textures/carreaux/image.png")
	t["textures/carreaux/image.jpg"] = Marshalls.raw_to_base64(png())
	refuse.call(t, "PNG nommé .jpg")
	t = texts.duplicate()
	t["textures/carreaux/image.png"] = "pas du base64 !"
	refuse.call(t, "base64 invalide")
	t = texts.duplicate()
	t["textures/carreaux/image.jpg"] = Marshalls.raw_to_base64(jpg())
	refuse.call(t, "deux images")
	t = texts.duplicate()
	t["textures/autre/image.png"] = Marshalls.raw_to_base64(png())
	refuse.call(t, "image sans texture.json")
	t = texts.duplicate()
	t["textures/carreaux/texture.json"] = JSON.stringify({"nom": {"fr": "x"}, "taille": 2, "shader": "res://x.gdshader"})
	refuse.call(t, "clé inconnue")
	t = texts.duplicate()
	t["textures/Carreaux/texture.json"] = texts["textures/carreaux/texture.json"]
	refuse.call(t, "majuscules dans le nom")
	t = texts.duplicate()
	t["textures/carreaux/image.gif"] = texts["textures/carreaux/image.png"]
	refuse.call(t, "fichier en trop")
	# Image plus grande que la limite du moteur : refusée sur l'en-tête.
	var big := png()
	big[16] = 0x00
	big[17] = 0x00
	big[18] = 0x4E
	big[19] = 0x20
	t = texts.duplicate()
	t["textures/carreaux/image.png"] = Marshalls.raw_to_base64(big)
	refuse.call(t, "20000 px")
	# Texture citée mais absente : acceptée (surface par défaut en jeu).
	var ref_only := DecorFree.two_rooms()
	ref_only.pieces[0]["surface_murs"] = "map:introuvable"
	ref_only.zones[1]["sol"] = "map:introuvable"
	assert_eq(CustomMapGuard.check_texts(ref_only.file_texts()).reasons, [], "texture citée absente : pas un refus")
	var bad_ref := DecorFree.two_rooms()
	bad_ref.pieces[0]["surface_murs"] = "map:../x"
	assert_false(CustomMapGuard.check_texts(bad_ref.file_texts()).ok, "référence mal formée refusée")


# ------------------------------------------------------------------ jeu : export, repli, matériau

func test_export_and_fallback() -> void:
	var doc := textured_map()
	# Salle B : plus de murs propres, ceux de sa zone (la texture).
	doc.pieces[1].erase("surface_murs")
	doc.zones[1]["murs"] = "map:carreaux"
	var v := MapRaster.build(doc).v
	v.analyze()
	assert_false(_has_warning(v, "texture de la carte"), "aucun avertissement de texture")
	var data := MapLayoutExport.build(v)
	assert_eq(_floor_mat(data, "a"), "tex-carreaux", "sol de la salle A : la texture")
	assert_true(data.has("map_textures") and (data.map_textures as Dictionary).has("carreaux"), "texture emportée par la description")
	var wall_mats := {}
	for key in ["blocks", "walls", "obliques"]:
		for w in data.get(key, []):
			wall_mats[String(w.get("mat", ""))] = true
	assert_true(wall_mats.has("tex-carreaux") and wall_mats.has("brick"), "murs de la zone B : la texture, salle A : brique : %s" % str(wall_mats.keys()))
	# Texture absente (citée seulement) : surface par défaut et avertissement.
	var miss := DecorFree.two_rooms()
	miss.pieces[0]["surface_sol"] = "map:introuvable"
	miss.zones[0]["plafond"] = "map:introuvable"
	var v2 := MapRaster.build(miss).v
	v2.analyze()
	assert_true(_has_warning(v2, "introuvable"), "avertissement du validateur : %s" % str(v2.warnings().map(func(m): return m.fr)))
	var d2 := MapLayoutExport.build(v2)
	assert_eq(_floor_mat(d2, "a"), "concrete", "repli : sol par défaut")
	assert_false(d2.has("map_textures"), "rien à emporter")
	# Définition sans image : même repli.
	var noimg := textured_map()
	noimg.texture_files.clear()
	var v3 := MapRaster.build(noimg).v
	assert_true(_has_warning(v3, "sans image"), "avertissement : texture sans image")
	v3.analyze()
	assert_eq(_floor_mat(MapLayoutExport.build(v3), "a"), "concrete")


func test_game_material() -> void:
	var doc := textured_map()
	var data := DecorFree.layout(doc)
	var b := MeshMapBuilder.new(data, "")
	var parent := Node3D.new()
	host.add_child(parent)
	b.build(parent)
	var found: MeshInstance3D = null
	for n in parent.find_children("*", "MeshInstance3D", true, false):
		if String(n.name).begins_with("tex-carreaux__"):
			found = n
			break
	assert_true(found != null, "sol texturé construit")
	if found != null:
		var m := found.material_override as ShaderMaterial
		assert_true(m != null and m.shader == MapTextureLib.SHADER, "matériau de la texture importée")
		var tex: Texture2D = m.get_shader_parameter("albedo_tex")
		assert_true(tex != null and tex.get_width() == 64, "image chargée depuis les octets")
		assert_eq(m.get_shader_parameter("tile"), Vector2(1.5, 0.75), "motif de 1,5 m (hauteur selon l'image 64 × 32)")
	parent.queue_free()
	# Image illisible dans la description : surface par défaut, jamais d'arrêt.
	data.map_textures.carreaux.image = Marshalls.raw_to_base64(png().slice(0, 40))
	MapTextureLib._tex_cache.clear()
	var b2 := MeshMapBuilder.new(data, "")
	var p2 := Node3D.new()
	host.add_child(p2)
	b2.build(p2)
	for n in p2.find_children("tex-carreaux__*", "MeshInstance3D", true, false):
		assert_true((n as MeshInstance3D).material_override == WorldLook.surface("concrete"), "image illisible : béton par défaut")
	p2.queue_free()


# ------------------------------------------------------------------ opérations (session, MCP apply)

func test_ops_admit_known_texture() -> void:
	var doc := textured_map()
	var room: Dictionary = doc.pieces[1].duplicate(true)
	room["surface_murs"] = "map:carreaux"
	var chk := MapOps.check_elements(doc, [{"op": "put", "coll": "pieces", "el": room}])
	assert_eq(chk.invalid, {}, "texture connue admise")
	var bad: Dictionary = doc.pieces[1].duplicate(true)
	bad["surface_murs"] = "map:inconnue"
	chk = MapOps.check_elements(doc, [{"op": "put", "coll": "pieces", "el": bad}])
	assert_true(chk.invalid.has(String(bad.id)) and String(chk.invalid[String(bad.id)]).contains("inconnue"), "texture inconnue refusée : %s" % str(chk.invalid))
	var z: Dictionary = doc.zones[0].duplicate(true)
	z["plafond"] = "map:carreaux"
	assert_eq(MapOps.check_elements(doc.snapshot(), [{"op": "put", "coll": "zones", "el": z}]).invalid, {}, "zone : texture connue admise (instantané)")
	z["plafond"] = "map:autre"
	assert_false(MapOps.check_elements(doc.snapshot(), [{"op": "put", "coll": "zones", "el": z}]).invalid.is_empty(), "zone : texture inconnue refusée")


# ------------------------------------------------------------------ MCP

func test_mcp_import_list_update() -> void:
	var doc := DecorFree.two_rooms()
	var collab := MapCollab.new(doc)
	host.add_child(collab)
	var path := ProjectSettings.globalize_path(TMP + "/import/brique_rouge.png")
	_write(path, png(128, 64))
	var r := MapAgentTextures.handle(collab, "texture_import", {"chemin": path, "taille": 2.5})
	assert_false(r.has("error"), "import d'un chemin : %s" % str(r))
	assert_eq(String(r.get("ref", "")), "map:brique_rouge", "identifiant tiré du nom du fichier")
	assert_eq(r.get("px"), [128, 64])
	assert_near(float(r.get("hauteur_motif", 0)), 1.25, 0.001, "hauteur du motif selon l'image")
	r = MapAgentTextures.handle(collab, "texture_import", {"data_base64": "data:image/jpeg;base64," + Marshalls.raw_to_base64(jpg()), "nom": {"fr": "Dalles", "en": "Slabs"}, "id": "dalles", "rugosite": 0.3})
	assert_eq(String(r.get("ref", "")), "map:dalles", "import en base64 : %s" % str(r))
	assert_eq(String(r.get("image", "")), "image.jpg")
	for bad in [{}, {"chemin": ProjectSettings.globalize_path(TMP + "/import/absent.png")}, {"chemin": path.get_basename() + ".gif"},
			{"data_base64": "!!!"}, {"data_base64": Marshalls.raw_to_base64("texte".to_utf8_buffer())},
			{"data_base64": Marshalls.raw_to_base64(png()), "taille": 0}, {"data_base64": Marshalls.raw_to_base64(png()), "id": "dalles"},
			{"data_base64": Marshalls.raw_to_base64(png()), "id": "Mauvais Id"}, {"data_base64": Marshalls.raw_to_base64(png()), "teinte": "bleu"}]:
		assert_true(MapAgentTextures.handle(collab, "texture_import", bad).has("error"), "import refusé : %s" % str(bad).left(80))
	# Liste : jeu + carte, où chacune est utilisée.
	doc.pieces[0]["surface_sol"] = "map:dalles"
	var l := MapAgentTextures.handle(collab, "texture_list", {})
	assert_true((l.jeu as Array).any(func(g): return g.ref == "brick" and g.has("utilisee_par")), "surface du jeu utilisée listée")
	var dl: Array = (l.carte as Array).filter(func(c): return c.ref == "map:dalles")
	assert_true(dl.size() == 1 and (dl[0].utilisee_par as Array).size() == 1, "dalles : utilisée une fois")
	# Mise à jour.
	r = MapAgentTextures.handle(collab, "texture_update", {"id": "map:dalles", "taille": 0.8, "teinte": "#ffcc99", "nom": "Dalles claires"})
	assert_false(r.has("error"), "réglages : %s" % str(r))
	assert_eq(doc.textures.dalles.taille, 0.8)
	assert_eq(doc.textures.dalles.teinte, "#ffcc99")
	assert_eq(doc.textures.dalles.nom, {"fr": "Dalles claires", "en": "Dalles claires"})
	assert_true(MapAgentTextures.handle(collab, "texture_update", {"id": "inconnue", "taille": 1}).has("error"), "texture inconnue refusée")
	assert_true(MapAgentTextures.handle(collab, "texture_update", {"id": "dalles", "rugosite": 3}).has("error"), "rugosité hors limites refusée")
	assert_true(MapAgentTextures.handle(collab, "texture_update", {"id": "dalles"}).has("error"), "aucun réglage : refusé")
	# Catalogue de la liaison : textures de la carte.
	assert_eq(MapAgentTextures.catalog_textures(doc).size(), 2)
	collab.queue_free()


func test_mcp_delete() -> void:
	var doc := textured_map()
	var collab := MapCollab.new(doc)
	host.add_child(collab)
	doc.zones[1]["murs"] = "map:carreaux"
	var r := MapAgentTextures.handle(collab, "texture_delete", {"id": "carreaux"})
	assert_true(r.has("error") and String(r.error).contains(String(doc.pieces[0].id)), "utilisée : refus qui nomme les éléments : %s" % str(r))
	assert_true(doc.textures.has("carreaux"))
	r = MapAgentTextures.handle(collab, "texture_delete", {"id": "carreaux", "forcer": true})
	assert_false(r.has("error"), "forcée : %s" % str(r))
	assert_false(doc.textures.has("carreaux"), "texture retirée")
	assert_false(doc.pieces[0].has("surface_sol") or doc.zones[1].has("murs"), "surface par défaut remise")
	assert_true(String(r.get("cid", "")) != "", "une modification de la session (annulable)")
	var u := collab.request_undo(true)
	assert_false(u.is_empty(), "annulable par Claude")
	assert_eq(String(doc.pieces[0].get("surface_sol", "")), "map:carreaux", "annulation : la référence revient (repli si la texture manque)")
	assert_true(MapAgentTextures.handle(collab, "texture_delete", {"id": "carreaux"}).has("error"), "inconnue : refusée")
	collab.queue_free()


func test_mcp_import_from_map_and_guest() -> void:
	var src := textured_map()
	src.carte["id"] = "source_tex"
	var dir := EditorMap.map_dir("source_tex")
	EditorMap.delete_map(dir)
	assert_eq(src.save_dir(dir), OK)
	var doc := DecorFree.two_rooms()
	assert_true(MapTextureTools.import_bytes(doc, jpg(), {"id": "carreaux", "nom": "Autre"}).has("tid"), "identifiant déjà pris")
	var collab := MapCollab.new(doc)
	host.add_child(collab)
	var r := MapAgentTextures.handle(collab, "texture_import_from_map", {"carte": "source_tex"})
	assert_false(r.has("error"), "copie depuis une autre carte : %s" % str(r))
	var got: Array = r.get("importees", [])
	assert_true(got.size() == 1 and String(got[0].id) != "carreaux", "nouvel identifiant (déjà pris) : %s" % str(got))
	if got.size() == 1:
		var nid := String(got[0].id)
		assert_eq(doc.textures[nid].taille, 1.5, "réglages copiés")
		assert_eq(MapTextureLib.image_bytes(doc.texture_files, nid), MapTextureLib.image_bytes(src.texture_files, "carreaux"), "image copiée")
	assert_true(MapAgentTextures.handle(collab, "texture_import_from_map", {"carte": "inexistante"}).has("error"), "carte inconnue refusée")
	assert_true(MapAgentTextures.handle(collab, "texture_import_from_map", {"carte": "source_tex", "ids": ["nulle_part"]}).has("error"), "texture absente refusée")
	# Invité d'une session : la bibliothèque est à l'hôte.
	collab.role = MapCollab.Role.GUEST
	for c in ["texture_import", "texture_update", "texture_delete", "texture_import_from_map"]:
		var g := MapAgentTextures.handle(collab, c, {"id": "carreaux", "data_base64": Marshalls.raw_to_base64(png()), "carte": "source_tex", "taille": 1})
		assert_true(g.has("error") and String(g.error).contains("hôte"), "%s refusé à un invité" % c)
	assert_false(MapAgentTextures.handle(collab, "texture_list", {}).has("error"), "la liste reste permise")
	collab.role = MapCollab.Role.SOLO
	assert_true(MapAgentTextures.handle(collab, "inconnue", {}).has("error"), "commande inconnue")
	collab.queue_free()
	EditorMap.delete_map(dir)


func test_tool_defs() -> void:
	var names := {}
	for t in MapAgentTextures.tool_defs():
		assert_true(t.has("name") and t.has("description") and t.has("inputSchema") and t.has("cmd"), "outil complet : %s" % str(t.get("name")))
		assert_true(String(t.cmd) in MapAgentTextures.CMDS, "commande connue : %s" % t.cmd)
		assert_true(String(t.description).length() > 200, "description détaillée : %s" % t.name)
		assert_eq(String(t.inputSchema.type), "object")
		names[t.name] = true
	assert_eq(names.size(), 5)
	assert_true(names.has("editor_texture_list") and names.has("editor_texture_import"))
	# JSON pur (aucun type Godot) : sérialisable tel quel par le serveur MCP.
	assert_eq(JSON.parse_string(JSON.stringify(MapAgentTextures.tool_defs())).size(), 5)


# ------------------------------------------------------------------ éditeur

func _editor() -> MapEditor:
	var ed: MapEditor = load(MapEditor.SCENE).instantiate()
	host.add_child(ed)
	await wait_frames(3)
	ed.new_map(true)
	return ed


## Listes de surfaces (OptionButton) du panneau Propriétés, dans l'ordre.
static func _surface_options(ed: MapEditor) -> Array:
	return ed.panels._props.find_children("*", "OptionButton", true, false).filter(func(o):
		for i in o.item_count:
			if str(o.get_item_metadata(i)) == "#importer":
				return true
		return false)


static func _index(o: OptionButton, v: String) -> int:
	for i in o.item_count:
		if not o.is_item_separator(i) and str(o.get_item_metadata(i)) == v:
			return i
	return -1


func test_editor_picker_import_delete() -> void:
	var calls := []
	FilePick.native_override = 1
	FilePick.native_show = func(title, _dir, _file, _hidden, _mode, filters, cb):
		calls.append([title, filters, cb])
		return OK
	var ed := await _editor()
	ed.doc = textured_map()
	ed.collab.reset_doc(ed.doc)
	ed.changed()
	var room: Dictionary = ed.doc.pieces[0]
	ed.select(String(room.id))
	ed.panels.refresh_now()
	var opts := _surface_options(ed)
	assert_eq(opts.size(), 3, "trois listes : sol, murs, plafond")
	if opts.size() == 3:
		var sol: OptionButton = opts[0]
		assert_eq(String(sol.get_item_metadata(sol.selected)), "map:carreaux", "sol : la texture de la carte choisie")
		assert_true(sol.get_parent().get_children().any(func(c): return c is Button and not c is OptionButton and c.text == "⚙"), "⚙ à côté d'une texture de la carte")
		# Plafond : la texture de la carte (une modification annulable).
		var ceil: OptionButton = opts[2]
		var i := _index(ceil, "map:carreaux")
		assert_true(i > 0, "texture de la carte proposée au plafond")
		ceil.select(i)
		ceil.item_selected.emit(i)
		assert_eq(String(room.get("surface_plafond", "")), "map:carreaux", "plafond texturé")
		ed.undo()
		assert_false(ed.doc.pieces[0].has("surface_plafond"), "Ctrl+Z : plafond d'avant")
	# Import depuis la liste : explorateur du système (simulé), image copiée,
	# texture posée sur la partie.
	ed.panels.refresh_now()
	opts = _surface_options(ed)
	var path := ProjectSettings.globalize_path(TMP + "/import/pierre_grise.jpg")
	_write(path, jpg(32, 32))
	if opts.size() == 3:
		var murs: OptionButton = opts[1]
		murs.item_selected.emit(_index(murs, "#importer"))
		assert_eq(calls.size(), 1, "explorateur ouvert")
		if calls.size() == 1:
			assert_eq((calls[0][1] as PackedStringArray)[0], "*.png, *.jpg, *.jpeg ; " + Lang.t("Image PNG ou JPEG", "PNG or JPEG image"), "filtre images")
			(calls[0][2] as Callable).call(true, PackedStringArray([path]), 0)
			await wait_frames(2)
		assert_true(ed.doc.textures.has("pierre_grise"), "texture importée : %s" % str(ed.doc.textures.keys()))
		assert_eq(String(ed.doc.pieces[0].get("surface_murs", "")), "map:pierre_grise", "posée sur les murs")
		ed.undo()
		assert_eq(String(ed.doc.pieces[0].get("surface_murs", "")), "brick", "Ctrl+Z : murs d'avant (la texture reste dans la bibliothèque)")
	# Suppression : refusée tant qu'utilisée, sauf confirmation (surface par défaut).
	var tt := ed.texture_tools
	assert_false(tt.delete_texture("carreaux"), "utilisée : refusée")
	assert_true(tt.delete_texture("carreaux", true), "forcée")
	assert_false(ed.doc.textures.has("carreaux") or ed.doc.pieces[0].has("surface_sol"), "surface par défaut remise")
	ed.undo()
	assert_eq(String(ed.doc.pieces[0].get("surface_sol", "")), "map:carreaux", "Ctrl+Z : la référence revient")
	ed.validate()
	assert_true(ed.validator != null and _has_warning(ed.validator, "carreaux"), "texture absente : avertissement du validateur")
	# Invité : la bibliothèque est à l'hôte.
	ed.collab.role = MapCollab.Role.GUEST
	assert_eq(tt.import_file(path), "", "invité : import refusé")
	assert_false(tt.set_settings("pierre_grise", {"taille": 3.0}), "invité : réglages refusés")
	ed.collab.role = MapCollab.Role.SOLO
	assert_true(tt.set_settings("pierre_grise", {"taille": 3.0}), "solo : réglages")
	assert_eq(ed.doc.textures.pierre_grise.taille, 3.0)
	FilePick.native_override = -1
	FilePick.native_show = Callable()
	ed.queue_free()
	await wait_frames(1)
