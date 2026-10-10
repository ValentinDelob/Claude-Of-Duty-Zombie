class_name VoxelBuild
extends RefCounted
## Modèles CUBIQUES construits par le jeu (cubes de 5 cm, GAME_CONCEPT.md
## § 4.19, docs/VOXEL_DECOR_PLAN.md lot 4) : objets de carte dont la taille
## vient de la carte (portes et débris de toute largeur, planches et portes
## à zombies des barricades, caisse et baril posés au centimètre). Même
## principe que tools/blender/voxel/voxel_lib.py, dans le repère Godot :
##   - une cellule (x, y, z) occupe [x, x+1] × [y, y+1] × [z, z+1] cubes de
##     CUBE m, décalés de `offset` (m) à la construction du maillage ;
##   - couleur PAR CELLULE (sRGB ; alpha 0 = face émissive, matière « glow »),
##     surchargée par face (`paint`) : étiquettes, bandes, chiffres peints ;
##   - seules les faces visibles sont créées ; faces coplanaires voisines de
##     même couleur fusionnées en rectangles (balayage glouton) ; normales
##     plates ; ombrage peint par direction (SHADE, comme voxel_lib.shade) ;
##   - matériau unique « voxel » (MeshMapBuilder.material_for) : couleur de
##     face telle quelle (convertie en linéaire, comme COLOR_0 d'un .glb).
## Les objets de taille fixe (caisse au hasard, levier du courant,
## téléporteur...) viennent de tools/blender/voxel_props/objets.py :
## assets/models/props/voxel/objets/<objet>.glb (parts()).

const CUBE := 0.05
## Directions des faces : +x, -x, +y, -y, +z, -z.
const DIRS: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const PX := 0
const NX := 1
const PY := 2
const NY := 3
const PZ := 4
const NZ := 5
## Ombrage peint par direction (repère Godot : dessus clair, dessous sombre,
## côtés un peu plus sombres ; voxel_lib.SHADE dans le repère Blender).
const SHADE := [0.86, 0.86, 1.06, 0.62, 1.0, 0.94]
## Modèles Blender des objets de carte (un .glb par objet, un nœud par pièce).
const OBJ_DIR := "res://assets/models/props/voxel/objets/"

## Teintes (sRGB) : celles de voxel_lib.DECOR_PALETTE, puis celles des objets
## de carte (univers hôpital / laboratoire / zombies).
const PAL := {
	"wood": Color(0.52, 0.36, 0.22),
	"wood_dark": Color(0.33, 0.22, 0.13),
	"charred": Color(0.12, 0.10, 0.09),
	"concrete": Color(0.58, 0.57, 0.54),
	"plaster": Color(0.80, 0.80, 0.76),
	"steel": Color(0.55, 0.57, 0.59),
	"metal_dark": Color(0.24, 0.25, 0.26),
	"rust": Color(0.45, 0.25, 0.14),
	"paint_white": Color(0.86, 0.86, 0.82),
	"medic_red": Color(0.72, 0.10, 0.10),
	"hazard_yellow": Color(0.88, 0.70, 0.12),
	"rubber": Color(0.07, 0.07, 0.07),
	# Objets de carte.
	"door_steel": Color(0.33, 0.37, 0.38),     # tôle de porte blindée (gris-vert)
	"door_edge": Color(0.20, 0.22, 0.23),      # cadre et rivets
	"price": Color(0.80, 0.66, 0.36),          # prix au pochoir (ocre)
	"plank_grey": Color(0.50, 0.44, 0.36),     # planche de barricade délavée
	"leaf_green": Color(0.36, 0.40, 0.33),     # battant peint vert-de-gris
	"door_frame": Color(0.24, 0.17, 0.11),     # bâti brun sombre
	"velvet": Color(0.42, 0.06, 0.07),         # rideau de velours
	"gold": Color(0.74, 0.58, 0.24),           # frange, laiton
	"barrel_red": Color(0.50, 0.13, 0.09),     # baril peint
	"crate_wood": Color(0.55, 0.40, 0.24),     # caisse en bois
}

## Chiffres au pochoir (3 × 5 cubes, ligne du haut d'abord) : prix peints.
const DIGITS := {
	"0": ["###", "#.#", "#.#", "#.#", "###"],
	"1": [".#.", "##.", ".#.", ".#.", "###"],
	"2": ["###", "..#", "###", "#..", "###"],
	"3": ["###", "..#", ".##", "..#", "###"],
	"4": ["#.#", "#.#", "###", "..#", "..#"],
	"5": ["###", "#..", "###", "..#", "###"],
	"6": ["###", "#..", "###", "#.#", "###"],
	"7": ["###", "..#", ".#.", ".#.", ".#."],
	"8": ["###", "#.#", "###", "#.#", "###"],
	"9": ["###", "#.#", "###", "..#", "###"],
}

## Cellule -> couleur (sRGB, alpha 0 : émissive).
var cells: Dictionary = {}
## Vector4i(x, y, z, direction) -> couleur d'une face (peinture).
var faces: Dictionary = {}


static func col(name: String, f := 1.0) -> Color:
	return tone(PAL[name], f)


## Couleur multipliée par `f` (bornée), alpha gardé.
static func tone(c: Color, f: float) -> Color:
	return Color(clampf(c.r * f, 0.0, 1.0), clampf(c.g * f, 0.0, 1.0), clampf(c.b * f, 0.0, 1.0), c.a)


## Couleur émissive (alpha 0) : voyants, braises.
static func glow(c: Color) -> Color:
	return Color(c.r, c.g, c.b, 0.0)


## Bruit déterministe 0..1 d'une cellule (même hachage que voxel_lib.noise) :
## texture « un pixel = un cube », la même sur toutes les machines.
static func noise(x: int, y: int, z: int, s := 0) -> float:
	var h := ((x * 73856093) ^ (y * 19349663) ^ (z * 83492791) ^ (s * 2654435761)) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	return float((h ^ (h >> 16)) & 0xFFFF) / 65535.0


## Teinte `base` éclaircie ou assombrie par cube (`levels` paliers de ±amp).
static func grain(x: int, y: int, z: int, base: Color, s := 0, amp := 0.07, levels := 3) -> Color:
	var k := mini(levels - 1, int(noise(x, y, z, s) * levels))
	return tone(base, 1.0 + amp * (2.0 * k / maxf(1.0, levels - 1.0) - 1.0))


func put(x: int, y: int, z: int, c: Color) -> void:
	cells[Vector3i(x, y, z)] = c


func has(x: int, y: int, z: int) -> bool:
	return cells.has(Vector3i(x, y, z))


## Pavé [x0, x1) × [y0, y1) × [z0, z1) d'une couleur unie (écrase).
func box(x0: int, x1: int, y0: int, y1: int, z0: int, z1: int, c: Color) -> void:
	for x in range(x0, x1):
		for y in range(y0, y1):
			for z in range(z0, z1):
				cells[Vector3i(x, y, z)] = c


## Pavé texturé (grain par cube).
func fill(x0: int, x1: int, y0: int, y1: int, z0: int, z1: int, base: Color, s := 0, amp := 0.07, levels := 3) -> void:
	for x in range(x0, x1):
		for y in range(y0, y1):
			for z in range(z0, z1):
				cells[Vector3i(x, y, z)] = grain(x, y, z, base, s, amp, levels)


func clear(x0: int, x1: int, y0: int, y1: int, z0: int, z1: int) -> void:
	for x in range(x0, x1):
		for y in range(y0, y1):
			for z in range(z0, z1):
				cells.erase(Vector3i(x, y, z))


## Couleur d'une face de cube (aucune géométrie ajoutée).
func paint(x: int, y: int, z: int, d: int, c: Color) -> void:
	if cells.has(Vector3i(x, y, z)):
		faces[Vector4i(x, y, z, d)] = c


## Peint la face `d` (+z ou -z) de la colonne de cellules la plus proche en
## (x, y) : premier cube rencontré depuis ce côté, entre z0 et z1.
func paint_front(x: int, y: int, z0: int, z1: int, d: int, c: Color) -> void:
	var zs := range(z1 - 1, z0 - 1, -1) if d == PZ else range(z0, z1)
	for z in zs:
		if cells.has(Vector3i(x, y, z)):
			faces[Vector4i(x, y, z, d)] = c
			return


## Nombre au pochoir (DIGITS) centré en x = `cx` (cubes), bas en `y0`, peint
## sur la face `d` (PZ : lisible de +z ; NZ : lisible de -z, miroir) de la
## première cellule rencontrée entre z0 et z1. Largeur : 4 cubes par chiffre.
func paint_number(text: String, cx: int, y0: int, z0: int, z1: int, d: int, c: Color) -> void:
	var w := text.length() * 4 - 1
	var left := cx - (w >> 1)
	for i in text.length():
		var g: Array = DIGITS.get(text[i], [])
		for row in g.size():
			var line: String = g[row]
			for k in line.length():
				if line[k] != "#":
					continue
				var u := i * 4 + k
				# Vu de -z, la gauche du lecteur est vers +x : chiffres en miroir.
				var x := left + u if d == PZ else left + w - 1 - u
				paint_front(x, y0 + 4 - row, z0, z1, d, c)


## Bornes [min, max) des cellules (cubes).
func bounds() -> AABB:
	var lo := Vector3i(1 << 30, 1 << 30, 1 << 30)
	var hi := -lo
	for c: Vector3i in cells:
		lo = lo.min(c)
		hi = hi.max(c + Vector3i.ONE)
	return AABB(Vector3(lo), Vector3(hi - lo))


# ------------------------------------------------------------------ maillage

## Maillage des faces visibles (rectangles fusionnés), en mètres, décalé de
## `offset`. `shade` : ombrage peint par direction.
func mesh(offset := Vector3.ZERO, shade := true) -> ArrayMesh:
	var groups := {}
	for c: Vector3i in cells:
		for d in 6:
			if cells.has(c + DIRS[d]):
				continue
			var cc: Color = faces.get(Vector4i(c.x, c.y, c.z, d), cells[c])
			if shade:
				cc = tone(cc, SHADE[d])
			var axis := d >> 1
			var plane := c[axis] + (1 if d % 2 == 0 else 0)
			var a := c[(axis + 1) % 3]
			var b := c[(axis + 2) % 3]
			var key := "%d|%d|%s" % [d, plane, cc.to_html(true)]
			if not groups.has(key):
				groups[key] = {"d": d, "plane": plane, "col": cc, "cells": {}}
			groups[key].cells[Vector2i(a, b)] = true
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var cs := PackedColorArray()
	var keys := groups.keys()
	keys.sort()
	for key in keys:
		var g: Dictionary = groups[key]
		var d: int = g.d
		var lin: Color = (g.col as Color).srgb_to_linear()
		lin.a = (g.col as Color).a
		var left: Dictionary = g.cells
		var order: Array = left.keys()
		order.sort()
		for ab: Vector2i in order:
			if not left.has(ab):
				continue
			var a1 := ab.x + 1
			while left.has(Vector2i(a1, ab.y)):
				a1 += 1
			var b1 := ab.y + 1
			var ok := true
			while ok:
				for i in range(ab.x, a1):
					if not left.has(Vector2i(i, b1)):
						ok = false
						break
				if ok:
					b1 += 1
			for i in range(ab.x, a1):
				for j in range(ab.y, b1):
					left.erase(Vector2i(i, j))
			_quad(v, n, cs, d, int(g.plane), ab.x, a1, ab.y, b1, offset, lin)
	var m := ArrayMesh.new()
	if v.is_empty():
		return m
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_COLOR] = cs
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


## Rectangle de la face `d` au plan `plane`, [a0, a1] × [b0, b1] sur les
## deux autres axes (cubes) : deux triangles, faces avant dans le sens
## horaire (Godot), normale plate.
static func _quad(v: PackedVector3Array, n: PackedVector3Array, cs: PackedColorArray, d: int, plane: int, a0: int, a1: int, b0: int, b1: int, offset: Vector3, c: Color) -> void:
	var axis := d >> 1
	var nrm := Vector3(DIRS[d])
	var pts: Array[Vector3] = []
	for ab in [Vector2i(a0, b0), Vector2i(a1, b0), Vector2i(a1, b1), Vector2i(a0, b1)]:
		var p := Vector3.ZERO
		p[axis] = plane
		p[(axis + 1) % 3] = ab.x
		p[(axis + 2) % 3] = ab.y
		pts.append(p * CUBE + offset)
	for t in [[0, 1, 2], [0, 2, 3]]:
		var p0 := pts[t[0]]
		var p1 := pts[t[1]]
		var p2 := pts[t[2]]
		if (p1 - p0).cross(p2 - p0).dot(nrm) > 0.0:
			var tmp := p1
			p1 = p2
			p2 = tmp
		v.append_array([p0, p1, p2])
		n.append_array([nrm, nrm, nrm])
		cs.append_array([c, c, c])


static func material() -> Material:
	return MeshMapBuilder.material_for(MeshMapBuilder.VOXEL_MAT)


## Nœud du modèle (matériau « voxel »), décalé de `offset` (m).
func node(node_name: String, offset := Vector3.ZERO, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh(offset)
	mi.material_override = material()
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Nombre de cubes (entier) d'une longueur `m` (mètres), au moins `at_least`.
static func cubes(m: float, at_least := 1) -> int:
	return maxi(at_least, roundi(m / CUBE))


# ------------------------------------------------------------------ modèles Blender

static var _scenes: Dictionary = {}


## Pièces d'un objet de carte modélisé sous Blender (OBJ_DIR/<objet>.glb,
## nœuds « voxel__<objet>_<pièce>__<type> ») : {pièce: MeshInstance3D} hors
## de l'arbre, matériau « voxel », sans ombre pour le type « ns ». Chaque
## pièce est modélisée dans le repère de l'objet (origine de l'objet) ; vide
## si le modèle manque.
static func parts(obj: String) -> Dictionary:
	var out := {}
	if not _scenes.has(obj):
		var path := OBJ_DIR + obj + ".glb"
		_scenes[obj] = load(path) if ResourceLoader.exists(path) else null
		if _scenes[obj] == null:
			push_warning("[VoxelBuild] modèle absent : " + path)
	var ps: PackedScene = _scenes[obj]
	if ps == null:
		return out
	var scene := ps.instantiate()
	var prefix := MeshMapBuilder.VOXEL_MAT + "__" + obj + "_"
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var nm := String(mi.name)
		if not nm.begins_with(prefix):
			continue
		var bits := nm.substr(prefix.length()).split("__")
		var part := bits[0]
		var xf := _to_root(mi, scene)
		mi.get_parent().remove_child(mi)
		mi.transform = xf
		mi.name = part
		mi.material_override = material()
		if bits.size() > 1 and bits[1] == "ns":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		out[part] = mi
	scene.free()
	return out


static func _to_root(n: Node, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur := n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


## Pose la pièce `mi` (modélisée dans le repère de l'objet) sous `parent`, un
## pivot placé à `pivot` (repère de l'objet, sans rotation au repos) : elle
## garde sa place, puis suit le pivot quand il tourne ou glisse.
static func attach(parent: Node3D, mi: Node3D, pivot := Vector3.ZERO) -> Node3D:
	if mi == null:
		return null
	mi.transform = Transform3D(Basis.IDENTITY, -pivot) * mi.transform
	parent.add_child(mi)
	return mi
