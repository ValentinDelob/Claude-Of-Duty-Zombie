class_name EditorPrefabs
extends RefCounted
## Objets du décor des cartes de l'éditeur construits par le jeu (formes
## simples, sans modèle) : table et chaise renversées, chariot, épave de
## voiture ; objet d'un luminaire (son modèle). Les autres décors (gravats,
## caisses, sacs de sable, décors des effets, fauteuils...) et tous les
## luminaires sont des modèles de assets/models/props/ (MapCatalog.PREFABS et
## LIGHTS ; décors cubiques « voxel/<id> », docs/VOXEL_DECOR_PLAN.md).
##
## Aucune collision ici : elles viennent des pavés du catalogue (CollisionBox,
## clé « blockers » de la description de carte). Les nœuds visibles suivent la
## convention « <matériau>__<nom>__<type> » : MeshMapBuilder._setup_nodes leur
## donne les matériaux du jeu (WorldLook) ; les parties lumineuses ont leur
## propre matériau émissif (nom sans « __ »). Maillages et matériaux partagés
## entre tous les exemplaires (peu de mémoire, rendu groupé).

static var _meshes: Dictionary = {}
## Type des nœuds construits : « block » (décor : ombre portée) ou « ns »
## (luminaires : pas d'ombre, l'abat-jour ne doit pas masquer sa lampe).
static var _kind := "block"


## Boîte partagée de taille `s`.
static func _box_mesh(s: Vector3) -> BoxMesh:
	var key := "b" + var_to_str(s)
	if not _meshes.has(key):
		var m := BoxMesh.new()
		m.size = s
		_meshes[key] = m
	return _meshes[key]


static func _cyl_mesh(r_top: float, r_bottom: float, h: float, seg := 10) -> CylinderMesh:
	var key := "c%s_%s_%s_%d" % [r_top, r_bottom, h, seg]
	if not _meshes.has(key):
		var m := CylinderMesh.new()
		m.top_radius = r_top
		m.bottom_radius = r_bottom
		m.height = h
		m.radial_segments = seg
		m.rings = 1
		_meshes[key] = m
	return _meshes[key]


static func _part(parent: Node3D, mat: String, mesh: Mesh, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "%s__%s%d__%s" % [mat, parent.name.to_lower(), parent.get_child_count(), _kind] if mat != "" else "Glow%d" % parent.get_child_count()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func _box(parent: Node3D, mat: String, s: Vector3, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	return _part(parent, mat, _box_mesh(s), pos, rot)


static func _root(kind: String) -> Node3D:
	var n := Node3D.new()
	n.name = kind.capitalize().replace(" ", "")
	return n


# ------------------------------------------------------------------ décor

## Objet de décor `kind` (MapCatalog.PREFABS[..].build), origine au sol, au
## centre de son emprise ; null si inconnu.
static func build(kind: String) -> Node3D:
	_kind = "block"
	var n := _root(kind)
	match kind:
		"table_renversee":
			# Plateau dressé comme un bouclier, pieds vers l'arrière.
			_box(n, "wood", Vector3(1.6, 0.85, 0.06), Vector3(0, 0.43, 0.27), Vector3(0.06, 0, 0))
			for sx in [-0.7, 0.7]:
				for y in [0.12, 0.72]:
					_box(n, "dark_wood", Vector3(0.07, 0.07, 0.7), Vector3(sx, y, -0.08))
		"chaise_renversee":
			# Chaise tombée sur le dos : assise verticale, pieds en l'air.
			_box(n, "wood", Vector3(0.42, 0.42, 0.04), Vector3(0.12, 0.22, 0), Vector3(0, 0, 0.1))
			_box(n, "wood", Vector3(0.42, 0.04, 0.42), Vector3(-0.2, 0.04, 0))
			for sz in [-0.18, 0.18]:
				_box(n, "steel", Vector3(0.42, 0.03, 0.03), Vector3(0.33, 0.38, sz))
				_box(n, "steel", Vector3(0.03, 0.42, 0.03), Vector3(0.12, 0.22, sz))
		"chariot":
			_box(n, "metal", Vector3(1.2, 0.05, 0.7), Vector3(0, 0.3, 0))
			_box(n, "metal", Vector3(1.2, 0.05, 0.7), Vector3(0, 0.82, 0))
			for sx in [-0.57, 0.57]:
				for sz in [-0.32, 0.32]:
					_box(n, "steel", Vector3(0.04, 0.62, 0.04), Vector3(sx, 0.55, sz))
					_part(n, "rubber", _cyl_mesh(0.08, 0.08, 0.05), Vector3(sx, 0.08, sz), Vector3(PI / 2, 0, 0))
			_box(n, "steel", Vector3(0.04, 0.3, 0.7), Vector3(0.6, 1.0, 0))
			_box(n, "crate", Vector3(0.5, 0.3, 0.4), Vector3(-0.25, 1.0, 0.05), Vector3(0, 0.2, 0))
		"epave_voiture":
			# Berline des années 60 rouillée, sans roues à l'avant (affaissée).
			_box(n, "wall_rust", Vector3(4.2, 0.62, 1.75), Vector3(0, 0.55, 0), Vector3(0, 0, -0.03))
			_box(n, "wall_rust", Vector3(2.1, 0.52, 1.6), Vector3(-0.25, 1.12, 0))
			_box(n, "steel", Vector3(0.06, 0.4, 1.5), Vector3(0.83, 1.1, 0), Vector3(0, 0, -0.5))
			_box(n, "steel", Vector3(0.06, 0.4, 1.5), Vector3(-1.32, 1.1, 0), Vector3(0, 0, 0.4))
			for side in [-1.0, 1.0]:
				_box(n, "concrete_dark", Vector3(1.9, 0.36, 0.03), Vector3(-0.25, 1.15, side * 0.8))
			for wx in [-1.35, 1.35]:
				for side in [-0.82, 0.82]:
					var y := 0.3 if wx < 0 else 0.22
					_part(n, "rubber", _cyl_mesh(0.3, 0.3, 0.2, 14), Vector3(wx, y, side), Vector3(PI / 2, 0, 0))
			_box(n, "steel", Vector3(0.08, 0.2, 1.8), Vector3(2.12, 0.42, 0))
			_box(n, "steel", Vector3(0.08, 0.2, 1.8), Vector3(-2.12, 0.42, 0))
		_:
			n.free()
			return null
	return n


# ------------------------------------------------------------------ luminaires

## Objet d'un luminaire `kind` (MapCatalog.LIGHTS) : origine au point de
## montage (plafond : sous le plafond ; mur : face du mur, +z vers la pièce ;
## sol : au sol ou sur le meuble). `loader(model) -> PackedScene` charge les
## modèles de la carte. null si le luminaire n'a pas d'objet.
static func fixture(kind: String, _models_dir := "", loader := Callable()) -> Node3D:
	var d: Dictionary = MapCatalog.LIGHTS.get(kind, {})
	if d.is_empty():
		return null
	if d.has("model") and loader.is_valid():
		var ps: PackedScene = loader.call(String(d.model))
		if ps == null:
			return null
		var inst: Node3D = ps.instantiate()
		for body in inst.find_children("*", "StaticBody3D", true, false):
			body.free()
		var holder := _root(kind)
		holder.add_child(inst)
		return holder
	return null
