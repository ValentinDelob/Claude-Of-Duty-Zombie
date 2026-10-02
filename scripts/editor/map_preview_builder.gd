class_name MapPreviewBuilder
extends MeshMapBuilder
## Aperçu 3D de l'éditeur de cartes (MapPreviewWorld) : la carte construite
## par le CODE DU JEU (MeshMapBuilder, MeshMapGeometry, MapProps.add_lamp,
## EditorPrefabs), découpée en trois morceaux reconstruits séparément quand
## seule une partie de la carte change :
##   build_architecture : murs, sols, plafonds, escaliers, garde-corps (MeshMapGeometry)
##   build_decor        : décor posé, objets répétés, écrans, pavés de collision
##   build_lamps        : lampes automatiques et luminaires (courant, grésillement)
## Mêmes fonctions que MeshMapBuilder.build() (_add_architecture,
## _build_decor_parts, _build_lamps ; le test « même géométrie que
## le jeu » compare les deux sur DRAFT ARENA) ; chaque morceau a sa racine, son
## réseau électrique (PowerGrid) et son grésillement (LightFlicker).

## Clés de la description qui alimentent chaque morceau (reconstruit si
## l'une d'elles change).
const ARCH_KEYS := ["rooms", "walls", "blocks", "slabs", "stairs", "rails", "obliques", "prop_materials"]
const DECOR_KEYS := ["props", "instances", "screens", "beams", "shafts", "blockers", "prop_materials", "models_dir", "rooms", "effects"]


func _init(layout_data: Dictionary) -> void:
	super(layout_data, "")


func build_architecture(parent: Node3D) -> void:
	_make_root(parent, "Architecture")
	_prop_mats = layout.get("prop_materials", {})
	_add_architecture(MeshMapGeometry.build(layout))


func build_decor(parent: Node3D) -> void:
	_make_root(parent, "Decor")
	_build_decor_parts()
	_build_clip_views()


## Barrières invisibles (blockers « clip ») : un pavé translucide dans
## l'aperçu seulement (option « Montrer les barrières invisibles ») ; en jeu,
## MeshMapBuilder n'en construit que la CollisionBox. Format 9 : le prisme du
## polygone (« poly »), à la hauteur de la barrière (« size » y).
func _build_clip_views() -> void:
	for d in layout.get("blockers", []):
		if not bool(d.get("clip", false)):
			continue
		var mi := MeshInstance3D.new()
		mi.name = "ClipView_" + String(d.get("eid", ""))
		var sz := MeshMapLayout.vec(d.size)
		var poly := CollisionBox.poly_of(d)
		if poly.size() >= 3:
			mi.mesh = prism_mesh(poly, sz.y)
		else:
			var bm := BoxMesh.new()
			bm.size = sz
			mi.mesh = bm
		mi.material_override = _clip_material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.transform = Transform3D(Basis(Vector3.UP, float(d.get("yaw", 0.0))), MeshMapLayout.vec(d.center))
		root.add_child(mi)


## Prisme d'un contour (x, z, centré) de hauteur `h` (de -h/2 à +h/2) :
## dessus, dessous et côtés (matériau sans faces cachées).
static func prism_mesh(poly: PackedVector2Array, h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lo := -h * 0.5
	var hi := h * 0.5
	var idx := Geometry2D.triangulate_polygon(poly)
	for i in range(0, idx.size(), 3):
		for y in [lo, hi]:
			for j in 3:
				var v := poly[idx[i + j]]
				st.add_vertex(Vector3(v.x, y, v.y))
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		for v in [Vector3(a.x, lo, a.y), Vector3(b.x, lo, b.y), Vector3(b.x, hi, b.y), Vector3(a.x, lo, a.y), Vector3(b.x, hi, b.y), Vector3(a.x, hi, a.y)]:
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()


static var _clip_mat: StandardMaterial3D


static func _clip_material() -> StandardMaterial3D:
	if _clip_mat == null:
		_clip_mat = StandardMaterial3D.new()
		_clip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_clip_mat.albedo_color = Color(0.35, 0.85, 1.0, 0.22)
		_clip_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_clip_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_clip_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return _clip_mat


## Lampes : même boucle que le jeu (MeshMapBuilder._build_lamps : une lampe
## automatique sur cinq grésille ; les luminaires passent par _fixture_lamp).
func build_lamps(parent: Node3D) -> void:
	_make_root(parent, "Lamps")
	_prop_mats = layout.get("prop_materials", {})
	_build_lamps()


## Empreinte des données d'un morceau (reconstruit seulement si elle change).
static func part_hash(layout_data: Dictionary, keys: Array) -> int:
	var parts := []
	for k in keys:
		parts.append(layout_data.get(k))
	return hash(parts)


static func lamps_hash(layout_data: Dictionary) -> int:
	return hash(layout_data.get("markers", {}).get("lamps", []))


## Objets de jeu (portes, fenêtres, atouts, armes, boîte...) : tous les
## marqueurs sauf les lampes, avec les réglages de la carte.
static func markers_hash(layout_data: Dictionary) -> int:
	var m: Dictionary = layout_data.get("markers", {}).duplicate()
	m.erase("lamps")
	return hash([m, layout_data.get("map_def", {}), layout_data.get("zones", {})])
