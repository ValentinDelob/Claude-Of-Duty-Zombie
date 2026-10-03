class_name CollisionBox
extends StaticBody3D
## Pavé de collision plein et invisible (aucun maillage) : ruines
## infranchissables, rangées de fauteuils, collisions des objets du décor.
## Toujours créé par le jeu à partir de données (layout.json, fichiers
## <modèle>.collision.json), jamais exporté depuis Blender.
##
## barrier = true : couche BARRIER (arrête joueurs et zombies, les balles
## passent : fauteuils, gravats bas) ; false : couche du décor (arrête aussi
## les balles et les grenades).
##
## Prisme (format 9 des cartes de l'éditeur : barrière invisible tracée en
## polygone) : `polygon` = contour en x, z (m, repère du nœud, centré), de
## hauteur size.y ; découpé en morceaux convexes
## (Geometry2D.decompose_polygon_in_convex), une ConvexPolygonShape3D chacun.
## Contour vide : le pavé `size` d'avant.

var size := Vector3.ONE
var barrier := false
var surface := "concrete"
var polygon := PackedVector2Array()


## `center` et `yaw` dans le repère du parent ; `size` en mètres.
static func make(center: Vector3, box_size: Vector3, yaw := 0.0, is_barrier := false, surf := "concrete") -> CollisionBox:
	return make_basis(center, box_size, Basis(Vector3.UP, yaw), is_barrier, surf)


## Pavé orienté (format 14 : décor incliné) : `basis` est une rotation (remise
## orthonormée : la taille porte l'échelle, jamais la base).
static func make_basis(center: Vector3, box_size: Vector3, basis: Basis, is_barrier := false, surf := "concrete") -> CollisionBox:
	var b := CollisionBox.new()
	b.size = box_size
	b.barrier = is_barrier
	b.surface = surf
	b.transform = Transform3D(basis.orthonormalized(), center)
	return b


## D'après une entrée de données : {center, size, yaw, barrier, surface} et,
## pour un prisme, « poly » [[x, z], ...] autour du centre.
static func from_dict(d: Dictionary) -> CollisionBox:
	var basis: Variant = MeshMapBuilder.basis_of(d.get("basis"))
	if basis == null:
		basis = Basis(Vector3.UP, float(d.get("yaw", 0.0)))
	var b := make_basis(MeshMapLayout.vec(d.center), MeshMapLayout.vec(d.size), basis,
			bool(d.get("barrier", false)), String(d.get("surface", "concrete")))
	b.polygon = poly_of(d)
	return b


## Contour « poly » d'une entrée de données (x, z autour du centre) ; vide
## s'il manque ou s'il a moins de 3 points lisibles.
static func poly_of(d: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	var p: Variant = d.get("poly")
	if p is Array:
		for q in p:
			if q is Array and q.size() >= 2 and (q[0] is float or q[0] is int) and (q[1] is float or q[1] is int):
				out.append(Vector2(float(q[0]), float(q[1])))
	return out if out.size() >= 3 else PackedVector2Array()


## Morceaux convexes d'un contour (repère x, z) ; [] s'il est illisible.
static func convex_parts(poly: PackedVector2Array) -> Array:
	if poly.size() < 3:
		return []
	var parts := Geometry2D.decompose_polygon_in_convex(poly)
	if parts.is_empty():
		# Contour qui ne se découpe pas (côtés qui se croisent) : ses triangles.
		var idx := Geometry2D.triangulate_polygon(poly)
		for i in range(0, idx.size(), 3):
			parts.append(PackedVector2Array([poly[idx[i]], poly[idx[i + 1]], poly[idx[i + 2]]]))
	return parts


## Sommets 3D d'un morceau convexe extrudé sur `h` (de -h/2 à +h/2).
static func prism_points(part: PackedVector2Array, h: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for v in part:
		pts.append(Vector3(v.x, -h * 0.5, v.y))
		pts.append(Vector3(v.x, h * 0.5, v.y))
	return pts


func _init() -> void:
	collision_mask = 0


func _ready() -> void:
	collision_layer = Barricade.BARRIER_LAYER if barrier else 1
	set_meta("surface", surface)  # effets d'impact (Fx.surface_of)
	var parts := convex_parts(polygon)
	if not parts.is_empty():
		for part in parts:
			var pcs := CollisionShape3D.new()
			var convex := ConvexPolygonShape3D.new()
			convex.points = prism_points(part, size.y)
			pcs.shape = convex
			pcs.set_meta("surface", surface)
			add_child(pcs)
		return
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.set_meta("surface", surface)
	add_child(cs)
