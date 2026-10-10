extends TestCase
## Prefabs de la carte (format 10, docs/MAP_OBJECTS.md § 11, MapPrefabLib) :
## prefab groupe créé depuis du décor posé, modèle .glb / .gltf importé (copié
## dans le dossier de la carte), enregistrement et relecture à l'identique,
## archive, paquet réseau et cache, export en maillage (objets et collisions
## CollisionBox), modèle illisible remplacé par une boîte, refus du contrôle
## des cartes reçues (extension, chemin, adresse externe, prefab absent,
## empreinte, accesseur « bombe »), et AUCUN quota (9e et 20e modèle, gros
## modèle, beaucoup de triangles : acceptés). Le petit .glb des tests est
## construit ici (GLTFDocument, une BoxMesh) : aucun binaire dans le dépôt.

const TMP := "res://tests/_out/test_map_prefabs"
const DecorFree := preload("res://tests/test_map_decor_free.gd")


func before_each() -> void:
	EditorMap.root_override = ProjectSettings.globalize_path(TMP + "/maps")
	CustomMapGuard.cache_override = ProjectSettings.globalize_path(TMP + "/cache")


func after_each() -> void:
	EditorMap.root_override = ""
	CustomMapGuard.cache_override = ""
	MapCatalog.set_map_prefabs({})


# ------------------------------------------------------------------ outils

## Petit modèle : une boîte de 1 × 2 × 3 m (GLTFDocument), en .glb.
static func box_glb(size := Vector3(1, 2, 3)) -> PackedByteArray:
	var root := Node3D.new()
	root.name = "Modele"
	var mi := MeshInstance3D.new()
	mi.name = "Boite"
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	root.add_child(mi)
	mi.owner = root
	var b := MapPrefabLib.to_glb(root)
	root.free()
	return b


static func _write(path: String, b: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var fa := FileAccess.open(path, FileAccess.WRITE)
	fa.store_buffer(b)
	fa.close()


## JSON et BIN d'un .glb.
static func _chunks(glb: PackedByteArray) -> Array:
	var jlen := glb.decode_u32(12)
	var j: Dictionary = JSON.parse_string(glb.slice(20, 20 + jlen).get_string_from_utf8())
	var bin := glb.slice(20 + jlen + 8)
	return [j, bin]


## Gros modèle valide : le petit .glb dont le tampon emporte `mb` Mo de plus
## (octets pseudo-aléatoires, incompressibles : pas une « bombe » de zip).
static func big_glb(mb: int) -> PackedByteArray:
	var ch := _chunks(box_glb())
	var j: Dictionary = ch[0]
	var bin: PackedByteArray = ch[1]
	bin.append_array(Crypto.new().generate_random_bytes(mb * 1048576))
	j.buffers[0]["byteLength"] = bin.size()
	return _glb_of(j, bin)


## .glb refait d'un JSON et d'un BIN (morceaux alignés sur 4 octets).
static func _glb_of(j: Dictionary, bin: PackedByteArray) -> PackedByteArray:
	var jb := JSON.stringify(j).to_utf8_buffer()
	while jb.size() % 4 != 0:
		jb.append(0x20)
	var bb := bin.duplicate()
	while bb.size() % 4 != 0:
		bb.append(0)
	var out := PackedByteArray()
	out.resize(12)
	out.encode_u32(0, 0x46546C67)
	out.encode_u32(4, 2)
	var head := PackedByteArray()
	head.resize(8)
	head.encode_u32(0, jb.size())
	head.encode_u32(4, 0x4E4F534A)
	out.append_array(head)
	out.append_array(jb)
	head.encode_u32(0, bb.size())
	head.encode_u32(4, 0x004E4942)
	out.append_array(head)
	out.append_array(bb)
	out.encode_u32(8, out.size())
	return out


## Carte jouable avec deux décors du catalogue côte à côte dans la salle A.
static func decorated() -> EditorMap:
	var doc := DecorFree.two_rooms()
	DecorFree._obj(doc, {"type": "prefab", "prefab": "caisses", "position": [4.0, 2.5], "rot": 0})
	DecorFree._obj(doc, {"type": "prefab", "prefab": "sacs_sable", "position": [6.5, 2.5], "rot": 90})
	return doc


static func _objs(doc: EditorMap, kind: String) -> Array:
	return doc.objets.filter(func(o): return String(o.get("prefab", "")) == kind)


# ------------------------------------------------------------------ prefab groupe

func test_group_prefab_from_placed_props() -> void:
	var doc := decorated()
	var parts := _objs(doc, "caisses") + _objs(doc, "sacs_sable")
	var res := MapPrefabLib.from_objects("Barricade", "Barricade", parts)
	assert_false(res.has("error"), "prefab groupe créé : %s" % str(res.get("error", "")))
	var def: Dictionary = res.def
	assert_eq((def.parties as Array).size(), 2, "deux parties")
	assert_eq(String(def.bloque), "solide", "bloque comme la partie la plus bloquante")
	assert_true((def.boxes as Array).size() >= 2, "collision : les pavés des parties")
	# Parties autour du centre de leur emprise commune (x : 5 et 7,5 m).
	var c: Vector2 = res.center
	assert_near(c.y, 2.5, 0.01, "centre en y")
	var p0: Array = def.parties[0].pos
	assert_near(float(p0[0]) + c.x, 4.0, 0.01, "première partie à sa place")
	assert_eq(int(def.parties[1].get("rot", 0)), 90, "rotation de la partie gardée")
	assert_true(int(def.fp[0]) >= 6 and int(def.fp[1]) >= 4, "emprise qui couvre les deux décors : %s" % str(def.fp))
	# Rien d'autre qu'un décor du catalogue.
	var bad := MapPrefabLib.from_objects("X", "X", [{"type": "caisse", "position": [1, 1]}])
	assert_true(bad.has("error"), "sans décor du catalogue : refusé")


func test_group_prefab_saved_in_map_folder_and_reloaded() -> void:
	var doc := decorated()
	var parts := _objs(doc, "caisses") + _objs(doc, "sacs_sable")
	var res := MapPrefabLib.from_objects("Barricade", "Barricade", parts)
	assert_true(doc.set_prefab("barricade", res.def), "prefab ajouté")
	for o in parts:
		doc.remove(String(o.id))
	DecorFree._obj(doc, {"type": "prefab", "prefab": "map:barricade", "position": MapGeom.arr(res.center), "rot": 0})
	var texts := doc.file_texts()
	assert_true(texts.has("prefabs/barricade/prefab.json"), "entrée du prefab dans les textes de la carte")
	assert_true(int(JSON.parse_string(texts["carte.json"]).format) >= 10, "format 10 et plus")
	var dir := EditorMap.map_dir("avec_prefab")
	assert_eq(doc.save_dir(dir), OK, "enregistrée")
	assert_true(FileAccess.file_exists(dir.path_join("prefabs/barricade/prefab.json")), "prefab.json dans le dossier de la carte")
	var back := EditorMap.load_dir(dir)
	assert_eq(back.load_errors, [], "relue sans erreur")
	assert_true(back.same_as(doc), "relue à l'identique")
	assert_eq(EditorMap.from_texts(back.file_texts()).file_texts(), back.file_texts(), "réécrite à l'identique")
	assert_eq(MapCatalog.prefab_def("map:barricade").get("fr", ""), "Barricade", "connu du catalogue")
	assert_false(MapCatalog.item("prefab:map:barricade").is_empty(), "objet d'inventaire")
	assert_eq(MapCatalog.in_category(MapCatalog.MAP_CAT).size(), 1, "catégorie « Prefabs de la carte »")
	# Prefab retiré : son dossier aussi.
	back.remove_prefab("barricade")
	back.objets = back.objets.filter(func(o): return String(o.get("prefab", "")) != "map:barricade")
	assert_eq(back.save_dir(dir), OK)
	assert_false(DirAccess.dir_exists_absolute(dir.path_join("prefabs/barricade")), "dossier du prefab retiré effacé")
	# Une carte d'avant (format 9, sans dossier prefabs/) se lit telle quelle.
	var old := DecorFree.two_rooms()
	var t9 := old.file_texts()
	t9["carte.json"] = String(t9["carte.json"]).replace("\"format\": 10", "\"format\": 9")
	var m9 := EditorMap.from_texts(t9)
	assert_eq(m9.load_errors, [], "format 9 lu")
	assert_true(m9.prefabs.is_empty(), "sans prefab")
	assert_eq(m9.file_texts().keys(), EditorMap.FILES, "toujours cinq fichiers sans prefab")


func test_group_prefab_export_props_and_blockers() -> void:
	var doc := decorated()
	var parts := _objs(doc, "caisses") + _objs(doc, "sacs_sable")
	var res := MapPrefabLib.from_objects("Barricade", "Barricade", parts)
	doc.set_prefab("barricade", res.def)
	for o in parts:
		doc.remove(String(o.id))
	DecorFree._obj(doc, {"type": "prefab", "prefab": "map:barricade", "position": MapGeom.arr(res.center), "rot": 90})
	var v := MapRaster.build(doc).v
	v.analyze()
	assert_true(v.ok(), "carte jouable avec le prefab : %s" % str(v.errors().map(func(e): return e.fr)))
	var lay := MapLayoutExport.build(v)
	var props: Array = lay.props.filter(func(p): return String(p.id).begins_with(String(doc.prefab_users("barricade")[0].id)))
	assert_eq(props.size(), 2, "une partie de prefab = un objet du jeu")
	assert_true(props.all(func(p): return p.get("nocollide", false) or p.has("build")), "aucune collision tirée d'un modèle")
	var n_boxes := (res.def.boxes as Array).size()
	var off := MapGeom.WORLD_OFFSET
	var c: Vector2 = res.center
	var mine: Array = lay.blockers.filter(func(b): return absf(float(b.center[0]) - (c.x + off)) < 4.0 and absf(float(b.center[2]) - (c.y + off)) < 4.0 and not b.get("clip", false))
	assert_eq(mine.size(), n_boxes, "collision : les pavés du prefab (CollisionBox)")
	# Rotation de 90° : un pavé décalé en x dans le prefab l'est en z dans le monde.
	var b0: Dictionary = res.def.boxes[0]
	var want := Basis(Vector3.UP, -PI / 2) * Vector3(float(b0.center[0]), 0, float(b0.center[2]))
	assert_true(mine.any(func(b): return absf(float(b.center[2]) - (c.y + off + want.z)) < 0.02), "pavés tournés avec le prefab")
	# Chevauchement : le prefab est du décor (règles du décor).
	assert_true(MapCatalog.is_decor(doc.prefab_users("barricade")[0]) and MapCatalog.may_overlap(doc.prefab_users("barricade")[0]), "décor qui peut chevaucher le décor")


# ------------------------------------------------------------------ modèle importé

func test_model_import_copied_into_map_folder() -> void:
	var glb := box_glb()
	assert_eq(MapPrefabLib.check_glb(glb), [], "petit .glb accepté")
	var src := ProjectSettings.globalize_path(TMP + "/src/caisse_bleue.glb")
	_write(src, glb)
	var got := MapPrefabLib.read_import(src)
	assert_false(got.has("error"), "import lu : %s" % str(got.get("error", "")))
	var res := MapPrefabLib.from_model("Caisse bleue", "Blue crate", got.glb, 1.0, "barriere")
	assert_false(res.has("error"), "prefab modèle : %s" % str(res.get("error", "")))
	var def: Dictionary = res.def
	assert_eq(def.fp, [2, 6], "emprise tirée de la boîte englobante (1 × 3 m)")
	assert_near(float(def.h), 2.0, 0.01, "hauteur")
	assert_eq((def.boxes as Array).size(), 1, "un pavé de collision")
	assert_true(bool(def.boxes[0].get("barrier", false)), "barrière")
	var doc := DecorFree.two_rooms()
	assert_true(doc.set_prefab("caisse_bleue", def, got.glb))
	DecorFree._obj(doc, {"type": "prefab", "prefab": "map:caisse_bleue", "position": [5.0, 5.0], "rot": 0})
	var dir := EditorMap.map_dir("modele_importe")
	assert_eq(doc.save_dir(dir), OK)
	var mp := dir.path_join("prefabs/caisse_bleue/model.glb")
	assert_true(FileAccess.file_exists(mp), "modèle copié dans le dossier de la carte")
	assert_eq(FileAccess.get_file_as_bytes(mp), got.glb, "même octets")
	var back := EditorMap.load_dir(dir)
	assert_eq(back.load_errors, [], "relue")
	assert_true(back.same_as(doc), "relue à l'identique (modèle compris)")
	assert_eq(back.model_bytes("caisse_bleue"), got.glb, "modèle relu")
	# Échelle : emprise et pavé recalculés.
	var big: Dictionary = def.duplicate(true)
	big.modele["echelle"] = 2.0
	MapPrefabLib.refit(big)
	assert_eq(big.fp, [4, 12], "échelle 2 : emprise doublée")
	assert_near(float(big.h), 4.0, 0.01, "échelle 2 : hauteur doublée")
	# Export : un objet « map_model » centré et posé au sol, le pavé du prefab.
	var lay := DecorFree.layout(back)
	var mm: Array = lay.props.filter(func(p): return p.has("map_model"))
	assert_eq(mm.size(), 1, "objet du modèle importé")
	assert_true((lay.get("map_models", {}) as Dictionary).has("caisse_bleue"), "modèle joint à la description")
	assert_near(float(mm[0].p[1]), 1.0, 0.01, "posé au sol (boîte centrée : remontée de 1 m)")
	var bl: Array = lay.blockers.filter(func(b): return bool(b.get("barrier", false)) and not b.get("clip", false) and absf(float(b.size[1]) - 2.0) < 0.01)
	assert_eq(bl.size(), 1, "collision du modèle : un CollisionBox barrière")
	# Construit par le jeu (GLTFDocument), sans collision tirée du modèle.
	var mb := MeshMapBuilder.new(lay, "")
	var inst: Node3D = mb._map_model(mm[0])
	assert_true(inst != null and not inst.find_children("*", "MeshInstance3D", true, false).is_empty(), "modèle chargé")
	assert_true(inst.find_children("*", "CollisionObject3D", true, false).is_empty(), "aucune collision dans le modèle")
	inst.free()


func test_gltf_with_embedded_data_is_converted() -> void:
	var ch := _chunks(box_glb())
	var j: Dictionary = ch[0]
	j.buffers[0]["uri"] = "data:application/octet-stream;base64," + Marshalls.raw_to_base64(ch[1])
	var src := ProjectSettings.globalize_path(TMP + "/src/integre.gltf")
	_write(src, JSON.stringify(j).to_utf8_buffer())
	var got := MapPrefabLib.read_import(src)
	assert_false(got.has("error"), ".gltf aux données intégrées accepté : %s" % str(got.get("error", "")))
	if got.has("glb"):
		assert_eq(MapPrefabLib.check_glb(got.glb), [], "réécrit en .glb")
	# Données à côté (fichier .bin) : refusé.
	j.buffers[0]["uri"] = "integre.bin"
	_write(src, JSON.stringify(j).to_utf8_buffer())
	_write(src.get_base_dir().path_join("integre.bin"), ch[1])
	assert_true(MapPrefabLib.read_import(src).has("error"), ".gltf avec un fichier .bin à côté : refusé")


func test_unreadable_model_becomes_a_box() -> void:
	var mb := MeshMapBuilder.new({"map_models": {"casse": Marshalls.raw_to_base64(PackedByteArray([1, 2, 3, 4]))}}, "")
	var inst: Node3D = mb._map_model({"map_model": "casse", "aabb": [-0.5, 0, -0.5, 0.5, 2, 0.5]})
	assert_true(inst != null, "jamais d'arrêt : une boîte à la place")
	var meshes := inst.find_children("*", "MeshInstance3D", true, false)
	assert_eq(meshes.size(), 1, "une boîte")
	assert_near(((meshes[0] as MeshInstance3D).mesh as BoxMesh).size.y, 2.0, 0.01, "de la taille du modèle")
	inst.free()
	var none: Node3D = mb._map_model({"map_model": "absent"})
	assert_true(none != null, "modèle absent : une boîte aussi")
	none.free()


# ------------------------------------------------------------------ contrôle des cartes reçues

static func _model_map() -> EditorMap:
	var doc := DecorFree.two_rooms()
	var glb := box_glb()
	doc.set_prefab("caisse_bleue", MapPrefabLib.from_model("Caisse", "Crate", glb).def, glb)
	DecorFree._obj(doc, {"type": "prefab", "prefab": "map:caisse_bleue", "position": [5.0, 5.0], "rot": 0})
	return MapTestKit.add_evac(doc)


func test_guard_accepts_prefabs_and_refuses_tampering() -> void:
	var doc := _model_map()
	var texts := doc.file_texts()
	assert_eq(CustomMapGuard.check_texts(texts).reasons, [], "carte avec un modèle importé acceptée")
	assert_true(CustomMapGuard.check_full(texts).ok, "et jouable")
	var refused := func(t: Dictionary, why: String) -> void:
		var r := CustomMapGuard.check_texts(t)
		assert_false(r.ok, "refusée : %s" % why)
	# Chemin piégé, fichier inattendu.
	var t1 := texts.duplicate()
	t1["prefabs/../evil/prefab.json"] = texts["prefabs/caisse_bleue/prefab.json"]
	refused.call(t1, "chemin « .. »")
	var t2 := texts.duplicate()
	t2["prefabs/caisse_bleue/script.gd"] = "extends Node"
	refused.call(t2, "fichier qui n'est ni prefab.json ni model.glb")
	var t3 := texts.duplicate()
	t3["prefabs/Caisse/prefab.json"] = texts["prefabs/caisse_bleue/prefab.json"]
	refused.call(t3, "identifiant de prefab en majuscules")
	# Prefab cité absent.
	var t4 := texts.duplicate()
	t4["objets.json"] = String(texts["objets.json"]).replace("map:caisse_bleue", "map:fantome")
	refused.call(t4, "prefab cité absent")
	# Modèle qui n'est pas un .glb, mal encodé, empreinte fausse, adresse externe.
	var t5 := texts.duplicate()
	var junk := PackedByteArray()
	junk.resize(1024)
	t5["prefabs/caisse_bleue/model.glb"] = Marshalls.raw_to_base64(junk)
	refused.call(t5, "modèle qui n'est pas un .glb")
	var t6 := texts.duplicate()
	t6["prefabs/caisse_bleue/model.glb"] = "pas du base64 !"
	refused.call(t6, "modèle mal encodé")
	var other := box_glb(Vector3(2, 2, 2))
	var t7 := texts.duplicate()
	t7["prefabs/caisse_bleue/model.glb"] = Marshalls.raw_to_base64(other)
	refused.call(t7, "empreinte du modèle fausse")
	var ch := _chunks(box_glb())
	var j: Dictionary = ch[0]
	j.buffers[0]["uri"] = "https://example.com/x.bin"
	assert_false(MapPrefabLib.check_glb(_glb_of(j, ch[1])).is_empty(), "adresse externe dans le .glb refusée")
	var j2: Dictionary = _chunks(box_glb())[0]
	j2["extensionsRequired"] = ["KHR_draco_mesh_compression"]
	assert_false(MapPrefabLib.check_glb(_glb_of(j2, ch[1])).is_empty(), "extension obligatoire inconnue refusée")
	# Aucun quota de triangles ; mais un accesseur qui annonce plus d'éléments
	# que le fichier n'a d'octets (« bombe » de mémoire) est refusé.
	var j3: Dictionary = _chunks(box_glb())[0]
	j3.accessors[j3.meshes[0].primitives[0].indices]["count"] = 2000000000
	assert_false(MapPrefabLib.check_glb(_glb_of(j3, ch[1])).is_empty(), "accesseur plus grand que le fichier refusé")
	var j4: Dictionary = _chunks(box_glb())[0]
	j4["buffers"].append({"byteLength": 4})
	assert_false(MapPrefabLib.check_glb(_glb_of(j4, ch[1])).is_empty(), "deux tampons dans un .glb : refusé (structure)")
	assert_false(MapPrefabLib.check_glb("pas un glb du tout, juste du texte".to_utf8_buffer()).is_empty(), "fichier qui n'est pas un .glb refusé")
	# Définition piégée.
	var def: Dictionary = JSON.parse_string(texts["prefabs/caisse_bleue/prefab.json"])
	def["script"] = "res://evil.gd"
	var t8 := texts.duplicate()
	t8["prefabs/caisse_bleue/prefab.json"] = JSON.stringify(def)
	refused.call(t8, "clé inconnue dans prefab.json")
	var def2: Dictionary = JSON.parse_string(texts["prefabs/caisse_bleue/prefab.json"])
	def2["nom"] = {"fr": "[url=x]piège[/url]"}
	var t9 := texts.duplicate()
	t9["prefabs/caisse_bleue/prefab.json"] = JSON.stringify(def2)
	refused.call(t9, "nom avec balise")
	# Import : extension refusée ; un gros fichier, non (pas de quota).
	var obj := ProjectSettings.globalize_path(TMP + "/src/modele.obj")
	_write(obj, "v 0 0 0".to_utf8_buffer())
	assert_true(MapPrefabLib.read_import(obj).has("error"), "extension .obj refusée")
	DirAccess.remove_absolute(obj)
	var fat := ProjectSettings.globalize_path(TMP + "/src/gros.glb")
	_write(fat, big_glb(9))
	var got := MapPrefabLib.read_import(fat)
	assert_false(got.has("error"), "fichier de plus de 8 Mo accepté : %s" % str(got.get("error", "")))
	DirAccess.remove_absolute(fat)


## Aucun quota (docs/MAP_OBJECTS.md § 11) : 20 modèles importés (le 9e et le
## 20e passaient au-delà des anciennes limites de 8), dont un de 9 Mo
## (ancienne limite : 8 Mo par modèle, 24 Mo en tout), et un modèle aux
## millions de triangles annoncés : la carte se crée, s'enregistre, se relit,
## passe le contrôle des cartes reçues, le paquet réseau, le cache et
## l'archive .zip. Une « bombe » de décompression dans une archive reste
## refusée (sûreté, pas un quota).
func test_no_quota_many_and_big_models() -> void:
	var doc := DecorFree.two_rooms()
	var spots := []
	for x in [2.0, 4.0, 6.0, 8.0, 10.0, 12.0, 16.0, 18.0, 20.0, 22.0]:
		spots.append([x, 2.5])
	for x in [2.0, 4.0, 10.0, 12.0, 16.0, 18.0, 20.0, 22.0]:
		spots.append([x, 5.0])
	spots.append_array([[2.0, 8.0], [4.0, 8.0]])
	for i in 20:
		var glb := big_glb(9) if i == 19 else box_glb(Vector3(0.5 + 0.01 * i, 1.0, 0.5))
		var res := MapPrefabLib.from_model("Modèle %d" % (i + 1), "Model %d" % (i + 1), glb)
		assert_false(res.has("error"), "modèle %d accepté : %s" % [i + 1, str(res.get("error", ""))])
		if res.has("error"):
			return
		assert_true(doc.set_prefab("modele_%d" % (i + 1), res.def, glb), "%de modèle ajouté à la carte" % (i + 1))
		DecorFree._obj(doc, {"type": "prefab", "prefab": "map:modele_%d" % (i + 1), "position": spots[i], "rot": 0})
	assert_eq(doc.model_count(), 20, "20 modèles dans la carte")
	assert_true(doc.model_bytes("modele_20").size() > 9 * 1048576, "un modèle de plus de 9 Mo")
	# Beaucoup de triangles (ancienne limite : 150 000) : accepté par le contrôle.
	var ch := _chunks(big_glb(3))
	var j: Dictionary = ch[0]
	j.accessors[j.meshes[0].primitives[0].indices]["count"] = 3 * 1000000
	var many := _glb_of(j, ch[1])
	assert_eq(MapPrefabLib.check_glb(many), [], "un million de triangles annoncés : accepté")
	assert_eq(int(MapPrefabLib.model_stats(many).get("triangles", 0)), 1000000, "triangles comptés pour information")
	var texts := doc.file_texts()
	assert_eq(CustomMapGuard.check_texts(texts).reasons, [], "contrôle des cartes reçues : accepté")
	var full := CustomMapGuard.check_full(texts)
	assert_true(full.ok, "jouable : %s" % CustomMapGuard.reasons_text(full.get("reasons", [])))
	# Dossier de la carte : enregistrée puis relue à l'identique.
	var dir := EditorMap.map_dir("vingt_modeles")
	assert_eq(doc.save_dir(dir), OK, "enregistrée")
	var back := EditorMap.load_dir(dir)
	assert_eq(back.load_errors, [], "relue sans erreur")
	assert_true(back.same_as(doc), "relue à l'identique (20 modèles)")
	# Paquet réseau et cache ; annonce d'une carte de 200 Mo acceptée (ancienne limite : 40 Mo).
	var pk := CustomMapGuard.package_of(doc)
	var chk := CustomMapGuard.check_package(pk.bytes, pk.sha)
	assert_true(chk.ok, "paquet réseau accepté : %s" % CustomMapGuard.reasons_text(chk.get("reasons", [])))
	assert_eq(CustomMapGuard.check_offer({"sha": pk.sha, "size": pk.bytes.size(), "chunk": CustomMapGuard.CHUNK_BYTES,
		"chunks": ceili(float(pk.bytes.size()) / CustomMapGuard.CHUNK_BYTES), "nom": {"fr": "X"}, "n": 1}), "", "annonce acceptée")
	assert_eq(CustomMapGuard.check_offer({"sha": pk.sha, "size": 200 * 1048576, "chunk": CustomMapGuard.CHUNK_BYTES,
		"chunks": ceili(200.0 * 1048576 / CustomMapGuard.CHUNK_BYTES), "nom": {"fr": "X"}, "n": 1}), "", "annonce d'une carte de 200 Mo acceptée")
	assert_eq(CustomMapGuard.store(pk.sha, pk.texts), OK, "cache")
	assert_true(CustomMapGuard.load_cached(pk.sha, true).ok, "relue du cache")
	# Archive .zip (ancienne limite : 30 Mo, 128 entrées de prefab).
	var zip := ProjectSettings.globalize_path(TMP + "/zips/vingt_modeles.zip")
	DirAccess.make_dir_recursive_absolute(zip.get_base_dir())
	assert_eq(doc.export_zip(zip), OK, "archive exportée")
	var az := EditorMap.import_zip(zip)
	assert_eq(az.load_errors, [], "archive relue")
	assert_true(az.same_as(doc), "archive relue à l'identique")
	# « Bombe » de décompression : 32 Mo de zéros dans un modèle.
	var bomb := ProjectSettings.globalize_path(TMP + "/zips/bombe.zip")
	var z := ZIPPacker.new()
	z.open(bomb)
	for f in EditorMap.FILES:
		z.start_file(f)
		z.write_file(String(texts[f]).to_utf8_buffer())
		z.close_file()
	z.start_file("prefabs/modele_1/prefab.json")
	z.write_file(String(texts["prefabs/modele_1/prefab.json"]).to_utf8_buffer())
	z.close_file()
	var zeros := PackedByteArray()
	zeros.resize(32 * 1048576)
	z.start_file("prefabs/modele_1/model.glb")
	z.write_file(zeros)
	z.close_file()
	z.close()
	assert_false(EditorMap.import_zip(bomb).load_errors.is_empty(), "bombe de décompression refusée (import)")
	assert_false(CustomMapGuard.read_zip_texts(bomb).reasons.is_empty(), "bombe de décompression refusée (lecture)")


func test_package_cache_and_archive_carry_prefabs() -> void:
	var doc := _model_map()
	var pk := CustomMapGuard.package_of(doc)
	var chk := CustomMapGuard.check_package(pk.bytes, pk.sha)
	assert_true(chk.ok, "paquet réseau avec prefabs accepté : %s" % CustomMapGuard.reasons_text(chk.get("reasons", [])))
	assert_true(String(pk.bytes.get_string_from_utf8()).contains("\"format\":2"), "paquet au format 2")
	assert_eq(CustomMapGuard.store(pk.sha, pk.texts), OK, "enregistrée dans le cache")
	assert_true(FileAccess.file_exists(CustomMapGuard.cache_dir(pk.sha).path_join("prefabs/caisse_bleue/model.glb")), "modèle dans le cache")
	var cached := CustomMapGuard.load_cached(pk.sha, true)
	assert_true(cached.ok, "relue du cache (empreinte, contrôle, jouable) : %s" % CustomMapGuard.reasons_text(cached.get("reasons", [])))
	# Une carte sans prefab garde son paquet d'avant (format 1).
	var plain := CustomMapGuard.package_of(DecorFree.two_rooms())
	assert_true(String(plain.bytes.get_string_from_utf8()).contains("\"format\":1"), "sans prefab : paquet au format 1")
	# Archive .zip : exportée puis importée, à l'identique.
	var zip := ProjectSettings.globalize_path(TMP + "/zips/avec_modele.zip")
	DirAccess.make_dir_recursive_absolute(zip.get_base_dir())
	assert_eq(doc.export_zip(zip), OK, "archive exportée")
	var back := EditorMap.import_zip(zip)
	assert_eq(back.load_errors, [], "archive relue")
	assert_true(back.same_as(doc), "archive relue à l'identique (modèle compris)")


# ------------------------------------------------------------------ éditeur (inventaire, création, annulation)

func test_editor_creates_replaces_and_protects_prefabs() -> void:
	var ed: MapEditor = load(MapEditor.SCENE).instantiate()
	host.add_child(ed)
	await wait_frames(3)
	ed.new_map(true)
	ed.doc = decorated()
	ed.changed()
	var n0 := ed.doc.objets.size()
	# Rectangle de capture autour des deux décors.
	var objs := ed.prefab_tools.captured(Rect2(2.0, 1.0, 6.0, 3.0))
	assert_eq(objs.size(), 2, "deux décors dans le rectangle")
	var pid := ed.prefab_tools.create_from_objects(objs, "Barricade [x]", true)
	assert_true(pid != "", "prefab créé")
	assert_eq(ed.doc.objets.size(), n0 - 1, "les deux décors remplacés par un prefab posé")
	assert_eq(ed.doc.prefab_users(pid).size(), 1, "posé une fois")
	assert_false(String(MapPrefabLib.name_of(ed.doc.prefabs[pid])).contains("["), "nom nettoyé (pas de balise)")
	# Inventaire : actions et prefab de la carte.
	ed.inventory.show_category(MapCatalog.MAP_CAT)
	assert_eq(ed.inventory.cells.size(), 1, "le prefab dans l'inventaire")
	assert_true(ed.inventory._grid.get_child_count() >= 3, "cases Créer… et Importer…")
	# Supprimer : refusé tant qu'il est posé.
	assert_false(ed.prefab_tools.delete_prefab(pid), "suppression refusée : prefab posé")
	assert_true(ed.doc.prefabs.has(pid), "toujours là")
	# Annuler : les deux décors reviennent, le prefab reste dans la bibliothèque.
	ed.undo()
	assert_eq(ed.doc.objets.size(), n0, "annulé : décors d'origine revenus")
	assert_true(ed.doc.prefabs.has(pid), "bibliothèque gardée")
	assert_true(ed.prefab_tools.delete_prefab(pid), "plus posé : supprimé")
	assert_true(MapCatalog.item("prefab:" + MapPrefabLib.ref(pid)).is_empty(), "retiré du catalogue")
	# Import d'un modèle : réglages (échelle, collision) recalculent l'emprise.
	var src := ProjectSettings.globalize_path(TMP + "/src/statue.glb")
	_write(src, box_glb(Vector3(1, 1, 1)))
	var mid := ed.prefab_tools.import_file(src)
	assert_true(mid != "" and ed.doc.models.has(mid), "modèle importé")
	assert_true(ed.prefab_tools.update_prefab(mid, "Statue", 3.0, "non"), "réglé")
	var md: Dictionary = ed.doc.prefabs[mid]
	assert_eq(md.fp, [6, 6], "échelle 3 : 3 m de côté")
	assert_true((md.boxes as Array).is_empty(), "sans collision")
	assert_eq(MapCatalog.blocking({"type": "prefab", "prefab": MapPrefabLib.ref(mid)}), "non", "on marche dessus")
	ed.queue_free()
	await wait_frames(2)
