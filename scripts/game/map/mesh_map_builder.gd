class_name MeshMapBuilder
extends MapProps
## Décor d'une carte en maillage : instancie le .glb produit par
## tools/blender/mesh_map.py (ou, pour les cartes de l'éditeur, l'architecture
## construite par le jeu : MeshMapGeometry) et le branche sur le rendu du jeu,
## puis pose le décor décrit par la carte (clés du layout.json) :
##   props     [{model, p, yaw, scale}]           objets uniques (avec collisions)
##   instances [{model, items [[x,y,z,yaw,tilt]]}] objets répétés (fauteuils) en
##                                                 MultiMesh : un appel de dessin par matériau
##   screens   [{p, w, h, yaw}]                   écran de cinéma (joue quand le courant est là)
##   beams     [{from, to, radius}]               faisceau de projecteur (courant)
##   blockers  [{center, size, yaw, barrier}]     pavés de collision invisibles (CollisionBox)
## Modèles : assets/models/<dossier>/<model>.glb (tools/blender/props/*.py).
##
## Objets des .glb : « <matériau>__<nom>__<type> » (visible) et « ...__col » /
## « ...__barrier » (collision, StaticBody3D créé à l'import par le suffixe
## -colonly). Le matériau est une clé de WorldLook.SURFACES (shader procédural
## BO1 du jeu) ou une clé spéciale (voir _special). Sols, plafonds et petits
## détails (« ns ») ne projettent pas d'ombre.

const NO_SHADOW_KINDS := ["floor", "ceil", "ns"]

var layout: Dictionary
var glb_path := ""
var models_dir := "res://assets/models/kino/"
var _scenes: Dictionary = {}


func _init(layout_data: Dictionary, glb: String) -> void:
	layout = layout_data
	glb_path = glb
	# Dossier des modèles : seulement sous res://assets/models/ (jamais un
	# chemin venu d'une description de carte qui sortirait de là).
	var md := String(layout_data.get("models_dir", models_dir))
	if md.begins_with("res://assets/models/") and not md.contains("..") and not md.contains("\\") and md.find(":", 6) < 0:
		models_dir = md if md.ends_with("/") else md + "/"
	else:
		push_warning("[MeshMapBuilder] dossier de modèles refusé : " + md.left(80))


func build(parent: Node3D) -> void:
	_make_root(parent, "Props")
	# Sans .glb (cartes de l'éditeur) : architecture construite par le jeu.
	var scene: Node3D
	if glb_path == "":
		scene = MeshMapGeometry.build(layout)
	else:
		var packed := load(glb_path) as PackedScene
		if packed == null:
			push_error("[MeshMap] architecture introuvable : " + glb_path)
			return
		scene = packed.instantiate()
	_add_architecture(scene)
	_build_decor_parts()
	_build_lamps()


# Les trois morceaux ci-dessous sont communs au jeu (build) et à l'aperçu 3D
# de l'éditeur (MapPreviewBuilder) : le test « même géométrie que le jeu »
# (tests/test_map_preview.gd) repose sur ce partage.

## Architecture (.glb ou MeshMapGeometry) sous la racine : matériaux, ombres
## et collisions, lambris posés sur le sol de référence de chaque salle.
## Les matériaux remplacés (_prop_mats) sont pris tels qu'ils sont à l'appel
## (vides en jeu : « prop_materials » ne vise que le décor posé).
func _add_architecture(scene: Node3D) -> void:
	scene.name = "Architecture"
	root.add_child(scene)
	# Tablier invisible au haut de chaque escalier (CollisionBox à fleur du
	# palier) : aucune fente entre la dernière marche et le sol d'arrivée.
	var stairs: Array = layout.get("stairs", [])
	for i in stairs.size():
		var cb := CollisionBox.from_dict(StairGen.apron(stairs[i]))
		cb.name = "StairApron_%d" % i
		scene.add_child(cb)
	var floors: Dictionary = {}
	for r in layout.get("rooms", []):
		floors[r.id] = _room_floor(r)
	_setup_nodes(scene, func(room: String) -> float: return float(floors.get(room, 0.0)))


## Décor posé : objets, objets répétés, écrans et faisceaux, pavés de collision.
func _build_decor_parts() -> void:
	_prop_mats = layout.get("prop_materials", {})
	_build_props()
	_build_instances()
	_build_screens()
	_build_blockers()
	_build_effects()


## Effets de l'éditeur (format 10, clé « effects ») : particules, lumières
## vacillantes, arcs, AUCUN objet ni collision (MapEffects ; format 11 : zone,
## pas d'échelle). Budget de la carte :
## au plus MapCatalog.MAX_EFFECTS effets, MapEffects.LIGHT_BUDGET lumières et
## MapEffects.PARTICLE_BUDGET particules (au-delà, toutes réduites d'autant).
func _build_effects() -> void:
	var list: Array = layout.get("effects", [])
	if list.is_empty():
		return
	var made: Array[MapEffect] = []
	var lights := 0
	var total := 0
	for e in list.slice(0, MapCatalog.MAX_EFFECTS):
		if not e is Dictionary:
			continue
		var fx := MapEffects.build(String(e.get("fx", "")), e)
		if fx == null:
			continue
		fx.name = "Effect_" + String(e.get("eid", made.size()))
		fx.position = MeshMapLayout.vec(e.get("p", [0, 0, 0]))
		fx.rotation.y = float(e.get("yaw", 0.0))
		# Lumières des effets : au plus LIGHT_BUDGET par carte (les suivantes éteintes).
		lights = fx.limit_lights(MapEffects.LIGHT_BUDGET - lights) + lights
		total += fx.particle_count()
		root.add_child(fx)
		made.append(fx)
	if total > MapEffects.PARTICLE_BUDGET:
		var k := float(MapEffects.PARTICLE_BUDGET) / total
		for fx in made:
			fx.set_budget(k)


## Lampes automatiques (une sur cinq grésille) et luminaires de l'éditeur.
func _build_lamps() -> void:
	var lamps: Array = layout.get("markers", {}).get("lamps", [])
	for i in lamps.size():
		var l: Dictionary = lamps[i]
		if l.has("fixture"):
			_fixture_lamp(l)
			continue
		# Une lampe sur cinq grésille (déterministe).
		add_lamp(MeshMapLayout.vec(l.p), float(l.get("energy", 2.2)), float(l.get("range", 10.0)), i % 5 == 3)


## Luminaire de l'éditeur de cartes : lumière (code commun des lampes :
## courant, grésillement, RenderQuality) et son objet (EditorPrefabs.fixture).
func _fixture_lamp(l: Dictionary) -> void:
	var col := Color.html(String(l.get("color", "ffbd80"))) if Color.html_is_valid(String(l.get("color", ""))) else PowerGrid.ON_COLOR
	add_lamp(MeshMapLayout.vec(l.p), float(l.get("energy", 2.2)), float(l.get("range", 10.0)), bool(l.get("flicker", false)),
		col, bool(l.get("power", true)))
	var fx := EditorPrefabs.fixture(String(l.fixture), models_dir, _model)
	if fx == null:
		return
	fx.position = MeshMapLayout.vec(l.get("fixture_p", l.p))
	fx.rotation.y = float(l.get("yaw", 0.0))
	root.add_child(fx)
	_setup_nodes(fx, func(_room: String) -> float: return fx.position.y)
	for n in fx.find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Matériaux, ombres et collisions des nœuds d'un .glb. `floor_of(salle)` :
## hauteur du sol de référence (lambris des étages).
## Matériaux des objets remplacés par la carte (ex. plâtre de la salle au lieu
## du papier peint rouge) : clé « prop_materials » de la description.
var _prop_mats: Dictionary = {}


func _setup_nodes(scene: Node, floor_of: Callable) -> void:
	for n in scene.find_children("*", "", true, false):
		var parts := String(n.name).split("__")
		if parts.size() < 3:
			continue
		var mat: String = _prop_mats.get(parts[0], parts[0])
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			mi.material_override = material_for(mat)
			mi.set_instance_shader_parameter("floor_y", float(floor_of.call(parts[1])))
			if parts[2] == "biais":
				# Mur en biais (éditeur de cartes) : motif le long du mur.
				mi.set_instance_shader_parameter("oblique", 1.0)
			if parts[2] in NO_SHADOW_KINDS:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif n is StaticBody3D:
			var body := n as StaticBody3D
			# Barrière (vitres, fauteuils, gravats bas) : arrête joueurs et zombies, pas les balles.
			body.collision_layer = Barricade.BARRIER_LAYER if parts[2] == "barrier" else 1
			body.collision_mask = 0
			# Effets d'impact selon la matière (Fx.surface_of).
			for cs in body.get_children():
				if cs is CollisionShape3D:
					cs.set_meta("surface", mat)
			body.set_meta("surface", mat)


func _model(name: String) -> PackedScene:
	# Nom de modèle : lettres, chiffres, _ et - (pas de chemin).
	if not CustomMapGuard.asset_name_ok(name):
		push_warning("[MeshMapBuilder] nom de modèle refusé : " + name.left(64))
		return null
	if not _scenes.has(name):
		var path := models_dir + name + ".glb"
		_scenes[name] = load(path) if ResourceLoader.exists(path) else null
		if _scenes[name] == null:
			push_warning("[MeshMapBuilder] modèle absent : " + path)
	return _scenes[name]


static func _xf(p: Vector3, yaw: float, scale := 1.0, tilt := 0.0) -> Transform3D:
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt)
	return Transform3D(b.scaled(Vector3.ONE * scale), p)


## Base « basis » d'une entrée de la description (format 14 des cartes de
## l'éditeur : 9 nombres, colonnes x, y, z, rotation × échelle) ; null si elle
## manque ou ne se lit pas (nombres finis, base non dégénérée).
static func basis_of(v: Variant) -> Variant:
	if not (v is Array and v.size() == 9):
		return null
	for x in v:
		if not ((x is float or x is int) and is_finite(float(x)) and absf(float(x)) <= 1000.0):
			return null
	var b := Basis(Vector3(v[0], v[1], v[2]), Vector3(v[3], v[4], v[5]), Vector3(v[6], v[7], v[8]))
	if absf(b.determinant()) < 0.000001:
		return null
	return b


## Transformation d'un objet posé : « basis » en priorité, sinon lacet, échelle, bascule.
static func prop_xf(pr: Dictionary, pos: Vector3) -> Transform3D:
	var b: Variant = basis_of(pr.get("basis"))
	if b != null:
		return Transform3D(b, pos)
	return _xf(pos, float(pr.get("yaw", 0.0)), float(pr.get("scale", 1.0)), float(pr.get("tilt", 0.0)))


func _build_props() -> void:
	for pr in layout.get("props", []):
		var inst: Node3D = null
		if pr.has("map_model"):
			# Format 10 : modèle importé d'un prefab de la carte (son .glb,
			# chargé par GLTFDocument) ; illisible : une boîte à sa place.
			inst = _map_model(pr)
		elif pr.has("build"):
			# Objet construit par le jeu (décor de l'éditeur : sacs de sable, chariot...).
			inst = EditorPrefabs.build(String(pr.build))
		else:
			var ps := _model(String(pr.model))
			if ps != null:
				inst = ps.instantiate()
		if inst == null:
			continue
		inst.name = String(pr.get("id", pr.get("model", pr.get("build", "prop"))))
		var pos := MeshMapLayout.vec(pr.p)
		inst.transform = prop_xf(pr, pos)
		root.add_child(inst)
		# Matériaux propres à cet objet (« remap » de la description), en plus de ceux de la carte.
		var map_mats := _prop_mats
		if pr.has("remap"):
			_prop_mats = map_mats.merged(pr.remap, true)
		_setup_nodes(inst, func(_room: String) -> float: return pos.y)
		_prop_mats = map_mats
		# Règle : aucune collision ne vient d'un modèle Blender (seulement des
		# CollisionBox décrites à côté du .glb).
		for body in inst.find_children("*", "StaticBody3D", true, false):
			if body is CollisionBox:
				continue
			push_warning("[MeshMapBuilder] collision ignorée dans le modèle %s : utiliser %s.collision.json" % [pr.get("model", "?"), pr.get("model", "?")])
			body.free()
		# Collisions du modèle : pavés invisibles décrits à côté du .glb (sauf
		# « nocollide » : décor sans collision, ou collisions données à part
		# dans « blockers »).
		if pr.has("model") and not pr.get("nocollide", false):
			for d in _collision_boxes(String(pr.model)):
				inst.add_child(CollisionBox.from_dict(d))


## Modèles des prefabs de la carte déjà chargés : pid -> scène modèle (copiée
## pour chaque objet posé) ou null (illisible).
var _map_scenes: Dictionary = {}


## Objet d'un modèle importé (prefab de la carte, « map_model » : pid) ; une
## boîte grise de sa taille si le modèle manque ou ne se lit pas (journalisé,
## jamais d'arrêt du jeu).
func _map_model(pr: Dictionary) -> Node3D:
	var pid := String(pr.map_model)
	if not _map_scenes.has(pid):
		var tpl: Node3D = null
		var b64: Variant = (layout.get("map_models", {}) as Dictionary).get(pid)
		if b64 is String and MapPrefabLib.pid_ok(pid):
			tpl = MapPrefabLib.instantiate(Marshalls.base64_to_raw(b64))
		if tpl == null:
			push_warning("[MeshMapBuilder] modèle du prefab « %s » absent ou illisible : boîte à la place" % pid.left(32))
		_map_scenes[pid] = tpl
	var t: Node3D = _map_scenes[pid]
	if t != null:
		return t.duplicate() as Node3D
	return _placeholder(pr.get("aabb", []))


## Boîte grise à la place d'un modèle illisible (taille de sa boîte englobante).
static func _placeholder(aabb: Variant) -> Node3D:
	var size := Vector3.ONE
	var center := Vector3(0, 0.5, 0)
	if aabb is Array and aabb.size() == 6:
		var lo := Vector3(float(aabb[0]), float(aabb[1]), float(aabb[2]))
		var hi := Vector3(float(aabb[3]), float(aabb[4]), float(aabb[5]))
		size = (hi - lo).abs().clamp(Vector3.ONE * 0.05, Vector3.ONE * 30.0)
		center = (lo + hi) * 0.5
	var mi := MeshInstance3D.new()
	mi.name = "concrete__prefab__ns"
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = center
	var root := Node3D.new()
	root.add_child(mi)
	return root


## Modèles chargés (hors de l'arbre) libérés avec le constructeur.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for t in _map_scenes.values():
			if t != null and is_instance_valid(t):
				t.free()
		_map_scenes.clear()


## Objets répétés : un MultiMesh par maillage du modèle (sans collision : les
## rangées ont leurs propres blocs barrières dans la description).
func _build_instances() -> void:
	for group in layout.get("instances", []):
		var ps := _model(String(group.model))
		if ps == null:
			continue
		var items: Array = group.items
		var tmp: Node3D = ps.instantiate()
		for n in tmp.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			var parts := String(mi.name).split("__")
			var mat := parts[0] if parts.size() >= 3 else "wood"
			var local := _local_xf(mi, tmp)
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mi.mesh
			mm.instance_count = items.size()
			for i in items.size():
				var it: Array = items[i]
				var xf := _xf(Vector3(it[0], it[1], it[2]), float(it[3]) if it.size() > 3 else 0.0, 1.0, float(it[4]) if it.size() > 4 else 0.0)
				mm.set_instance_transform(i, xf * local)
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "%s_%s" % [group.model, mat]
			mmi.multimesh = mm
			mmi.material_override = material_for(mat)
			# Petits détails : pas d'ombre (les fauteuils eux-mêmes en projettent).
			if parts.size() >= 3 and parts[2] in NO_SHADOW_KINDS:
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mmi)
		tmp.free()


static func _local_xf(n: Node3D, top: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != top:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func _build_screens() -> void:
	for s in layout.get("screens", []):
		var mi := MeshInstance3D.new()
		mi.name = "CinemaScreen"
		var q := QuadMesh.new()
		q.size = Vector2(float(s.w), float(s.h))
		mi.mesh = q
		mi.position = MeshMapLayout.vec(s.p)
		mi.rotation.y = float(s.get("yaw", 0.0))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := TheaterLook.screen_material()
		warmup_materials.append(mat)
		mi.material_override = mat
		root.add_child(mi)
		power.add_hook(func(on: bool): mat.set_shader_parameter("playing", 1.0 if on else 0.0))
	for b in layout.get("beams", []) + layout.get("shafts", []):
		var shaft: bool = b.get("shaft", false)
		var from := MeshMapLayout.vec(b.from)
		var to := MeshMapLayout.vec(b.to)
		var beam := MeshInstance3D.new()
		beam.name = "LightShaft" if shaft else "ProjectorBeam"
		var cm := CylinderMesh.new()
		# Cône : étroit à la source (`from`, rayon `top`), large à l'arrivée (`radius`).
		# Le haut du cylindre (+Y local) est orienté vers `to`.
		cm.bottom_radius = float(b.get("top", 0.15))
		cm.top_radius = float(b.get("radius", 3.0))
		cm.height = from.distance_to(to)
		cm.radial_segments = 16
		cm.cap_top = false
		cm.cap_bottom = false
		beam.mesh = cm
		beam.material_override = TheaterLook.shaft_material() if shaft else TheaterLook.beam_material()
		warmup_materials.append(beam.material_override)
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var up := (to - from).normalized()
		var bx := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
		beam.transform = Transform3D(Basis(bx, up, bx.cross(up)).orthonormalized(), (from + to) * 0.5)
		root.add_child(beam)
		if not shaft:  # le faisceau du projecteur ne s'allume qu'avec le courant
			beam.visible = false
			power.add_hook(func(on: bool): beam.visible = on)


## Matériau d'une clé : WorldLook.SURFACES, ou clé spéciale.
static func material_for(key: String) -> Material:
	var sp := _special(key)
	return sp if sp != null else WorldLook.surface(key)


static var _specials: Dictionary = {}


## Clés hors WorldLook : vitres, ampoules, lueur électrique, cristal, craie,
## papier, peintures, caoutchouc ; format 11 : bois en braises, eau, cuivre,
## porcelaine (décors des effets).
static func _special(key: String) -> Material:
	if _specials.has(key):
		return _specials[key]
	var m: StandardMaterial3D = null
	match key:
		"glass":
			m = StandardMaterial3D.new()
			m.albedo_color = Color(0.55, 0.62, 0.6, 0.18)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.15
			m.metallic_specular = 0.8
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"bulb":
			m = PropBuilder._emissive(Color(1.0, 0.82, 0.55), 4.0)
		"glow_blue":
			m = PropBuilder._emissive(Color(0.45, 0.62, 1.0), 5.0)
		"crystal":
			m = StandardMaterial3D.new()
			m.albedo_color = Color(0.85, 0.9, 0.95, 0.75)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.05
			m.metallic = 0.3
			m.emission_enabled = true
			m.emission = Color(1.0, 0.9, 0.75)
			m.emission_energy_multiplier = 0.35
		"chalk", "paper", "paint_teal", "paint_red", "paint_blue", "cable_blue", "rubber":
			m = StandardMaterial3D.new()
			m.albedo_color = {"chalk": Color(0.85, 0.84, 0.78), "paper": Color(0.78, 0.75, 0.66),
					"paint_teal": Color(0.3, 0.5, 0.5), "paint_red": Color(0.42, 0.07, 0.05),
					"paint_blue": Color(0.1, 0.22, 0.5), "cable_blue": Color(0.04, 0.07, 0.19),
					"rubber": Color(0.035, 0.035, 0.035)}[key]
			m.roughness = {"paint_teal": 0.5, "paint_red": 0.55, "paint_blue": 0.5, "cable_blue": 0.6}.get(key, 0.9)
			m.metallic = 0.25 if key in ["paint_teal", "paint_blue"] else 0.0
		"plank":
			return WorldLook.surface("wood")
		# Format 11 : décors des effets (EditorPrefabs._effect_decor).
		"embers_wood", "charred", "tar_glow":
			# Bois brûlé : braises qui rougeoient dans la masse.
			m = StandardMaterial3D.new()
			m.albedo_color = {"embers_wood": Color(0.06, 0.045, 0.035), "charred": Color(0.06, 0.05, 0.045), "tar_glow": Color(0.05, 0.04, 0.03)}[key]
			m.roughness = 0.95
			m.emission_enabled = true
			m.emission = {"embers_wood": Color(0.9, 0.22, 0.04), "charred": Color(1.0, 0.28, 0.05), "tar_glow": Color(1.0, 0.35, 0.08)}[key]
			m.emission_energy_multiplier = {"embers_wood": 0.07, "charred": 0.12, "tar_glow": 0.8}[key]
		"water":
			# Eau immobile : sombre, très brillante, à moitié transparente.
			m = StandardMaterial3D.new()
			m.albedo_color = Color(0.1, 0.12, 0.14, 0.5)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.metallic = 0.6
			m.roughness = 0.03
		"copper", "porcelain", "paint_olive":
			m = StandardMaterial3D.new()
			m.albedo_color = {"copper": Color(0.55, 0.32, 0.18), "porcelain": Color(0.85, 0.82, 0.75), "paint_olive": Color(0.26, 0.29, 0.25)}[key]
			m.metallic = {"copper": 0.9, "porcelain": 0.0, "paint_olive": 0.3}[key]
			m.roughness = {"copper": 0.35, "porcelain": 0.6, "paint_olive": 0.7}[key]
	if m != null:
		_specials[key] = m
	return m


## Sol de référence d'une salle (bas de la pente s'il y en a une).
static func _room_floor(r: Dictionary) -> float:
	if r.has("slope"):
		var y := INF
		for p in r.slope:
			y = minf(y, float(p[1]))
		return y
	return float(r.get("floor", 0.0))


## Vitre (compatibilité : voir _special("glass")).
static func _glass() -> StandardMaterial3D:
	return _special("glass") as StandardMaterial3D


## Pavés invisibles de la carte (ruines infranchissables, rangées de fauteuils).
func _build_blockers() -> void:
	var list: Array = layout.get("blockers", [])
	if list.is_empty():
		return
	var holder := Node3D.new()
	holder.name = "Blockers"
	root.add_child(holder)
	for d in list:
		holder.add_child(CollisionBox.from_dict(d))


var _collisions: Dictionary = {}


## Collision d'un modèle : <modèle>.collision.json à côté du .glb,
## {"boxes": [{center, size, yaw, barrier, surface}]} en coordonnées du modèle.
func _collision_boxes(model: String) -> Array:
	if not CustomMapGuard.asset_name_ok(model):
		return []
	if not _collisions.has(model):
		var path := models_dir + model + ".collision.json"
		var boxes := []
		if FileAccess.file_exists(path):
			var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if d is Dictionary:
				boxes = d.get("boxes", [])
		_collisions[model] = boxes
	return _collisions[model]
