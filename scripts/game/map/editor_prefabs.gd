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
