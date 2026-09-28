class_name MeshMapBuilder
extends MapProps
## Décor d'une carte en maillage : instancie le .glb produit par
## tools/blender/mesh_map.py et le branche sur le rendu du jeu, puis pose le
## décor décrit par la carte (clés du layout.json) :
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
	models_dir = String(layout_data.get("models_dir", models_dir))


func build(parent: Node3D) -> void:
	_make_root(parent, "Props")
	var scene: Node3D = (load(glb_path) as PackedScene).instantiate()
	scene.name = "Architecture"
	root.add_child(scene)
	var floors := {}
	for r in layout.get("rooms", []):
		floors[r.id] = _room_floor(r)
	_setup_nodes(scene, func(room: String) -> float: return float(floors.get(room, 0.0)))
	_prop_mats = layout.get("prop_materials", {})
	_build_props()
	_build_instances()
	_build_screens()
	_build_blockers()
	var lamps: Array = layout.get("markers", {}).get("lamps", [])
	for i in lamps.size():
		var l: Dictionary = lamps[i]
		# Une lampe sur cinq grésille (déterministe).
		add_lamp(MeshMapLayout.vec(l.p), float(l.get("energy", 2.2)), float(l.get("range", 10.0)), i % 5 == 3)


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
	if not _scenes.has(name):
		var path := models_dir + name + ".glb"
		_scenes[name] = load(path) if ResourceLoader.exists(path) else null
		if _scenes[name] == null:
			push_warning("[MeshMapBuilder] modèle absent : " + path)
	return _scenes[name]


static func _xf(p: Vector3, yaw: float, scale := 1.0, tilt := 0.0) -> Transform3D:
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt)
	return Transform3D(b.scaled(Vector3.ONE * scale), p)


func _build_props() -> void:
	for pr in layout.get("props", []):
		var ps := _model(String(pr.model))
		if ps == null:
			continue
		var inst: Node3D = ps.instantiate()
		inst.name = String(pr.get("id", pr.model))
		var pos := MeshMapLayout.vec(pr.p)
		inst.transform = _xf(pos, float(pr.get("yaw", 0.0)), float(pr.get("scale", 1.0)), float(pr.get("tilt", 0.0)))
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
			push_warning("[MeshMapBuilder] collision ignorée dans le modèle %s : utiliser %s.collision.json" % [pr.model, pr.model])
			body.free()
		# Collisions du modèle : pavés invisibles décrits à côté du .glb.
		for d in _collision_boxes(String(pr.model)):
			inst.add_child(CollisionBox.from_dict(d))


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
## papier, peintures, caoutchouc.
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
	if not _collisions.has(model):
		var path := models_dir + model + ".collision.json"
		var boxes := []
		if FileAccess.file_exists(path):
			var d = JSON.parse_string(FileAccess.get_file_as_string(path))
			if d is Dictionary:
				boxes = d.get("boxes", [])
		_collisions[model] = boxes
	return _collisions[model]
