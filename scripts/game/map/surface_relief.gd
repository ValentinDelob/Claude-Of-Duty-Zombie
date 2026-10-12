class_name SurfaceRelief
extends RefCounted
## RELIEF des surfaces de l'architecture (docs/ART_DIRECTION.md « Relief des
## surfaces ») : carreaux manquants ou cassés, éclats, nids-de-poule, fissures
## et flaques en creux d'UN cube (5 cm) dans les sols ; plinthes, cimaises et
## couvre-joints en saillie d'un cube, plâtre tombé (briques dessous) et
## faïence manquante dans les murs ; ossature des faux plafonds et dalles
## tombées au plafond. Tout est en cubes de 5 cm sur la grille du monde
## (LayoutCheck), avec les matériaux pixel art de la carte (PixelSurfaces,
## posés en coordonnées monde : un creux montre exactement les pixels de la
## surface autour).
##
## * Construit À LA CONSTRUCTION de la carte (MapBuilder, MeshMapGeometry,
##   MenuBackdrop), jamais écrit dans un fichier de carte : cartes du jeu,
##   fond du menu et cartes du joueur en profitent sans changement.
## * DÉTERMINISTE : tirages hachés des coordonnées de la grille et de la
##   graine de la carte (seed_of(id)) : la même carte a le même relief sur
##   toutes les machines.
## * VISUEL SEULEMENT : les collisions restent les surfaces planes (sol plat
##   sous les pieds, murs à leur nu) : aucun accroc pour le joueur ni pour
##   les zombies, navmesh inchangé. Creux de 5 cm au plus dans les sols.
## * Jamais sur les endroits de jeu : les constructeurs passent les zones
##   réservées (seuils de portes, fenêtres barricadées, escaliers, évacuation,
##   station, apparitions, objets muraux) dans `ok` / `free`.
##
## Utilisation : plan_floor / plan_wall / plan_ceiling (repérage, avant de
## construire les faces), puis chaque face plane est découpée par cut()
## (rectangles restants) ou holes() (contours), et emit() ajoute les faces
## du relief (creux et saillies) au maillage du constructeur.

## Côté d'un cube de décor (m).
const CUBE := 0.05
## Relief activé (les tests de comptage de faces de l'architecture le coupent).
static var enabled := true

## Profils des SOLS (clé de surface PixelSurfaces) ; probabilités par site,
## multipliées par `density` :
##   type « tiles » : par carreau (ts pixels) : missing (manquant : tout le
##     carreau en creux, béton dessous ; les carreaux manquants peints par la
##     texture en font toujours partie), broken (morceau de coin en escalier),
##     chips (éclat d'un à trois cubes au coin) ;
##   type « concrete » : par site de 80 cm : holes (nid-de-poule) ; par site
##     de 1,6 m : cracks (fissure en escalier d'un cube de large) ;
##   type « planks » : par tronçon de 80 cm de lame : boards (morceau de lame
##     arraché, la lame d'à côté et le joint restent) ;
##   puddles (tous) : par site de 1,6 m, flaque en creux (eau dessous).
##   under : clé du fond des creux (dalle de béton).
const FLOOR := {
	"tiles": {"type": "tiles", "missing": 0.015, "broken": 0.025, "chips": 0.02, "puddles": 0.09, "under": "concrete"},
	"marble": {"type": "tiles", "missing": 0.01, "broken": 0.03, "chips": 0.03, "puddles": 0.0, "under": "concrete"},
	"floor": {"type": "concrete", "holes": 0.05, "cracks": 0.2, "puddles": 0.08, "under": "concrete"},
	"concrete": {"type": "concrete", "holes": 0.05, "cracks": 0.2, "puddles": 0.07, "under": "floor"},
	"concrete_dark": {"type": "concrete", "holes": 0.06, "cracks": 0.22, "puddles": 0.1, "under": "concrete"},
	"stone": {"type": "concrete", "holes": 0.05, "cracks": 0.16, "puddles": 0.0, "under": "concrete_dark"},
	"cobble": {"type": "concrete", "holes": 0.08, "cracks": 0.0, "puddles": 0.08, "under": "concrete_dark"},
	"wood": {"type": "planks", "boards": 0.06, "puddles": 0.0, "under": "void"},
	"stage_wood": {"type": "planks", "boards": 0.04, "puddles": 0.0, "under": "void"},
	"metal": {"type": "concrete", "holes": 0.0, "cracks": 0.0, "puddles": 0.1, "under": "concrete_dark"},
}

## Profils des MURS : base (plinthe : hauteur en cubes, saillie d'un cube),
## rail (cimaise : ligne de la texture ; -1 : bande peinte « band » de la
## clé), rail_h (hauteur de la cimaise en cubes) ; type « painted » : par site
## de 1,6 m, patches (plâtre tombé, briques dessous), cracks ; type « tiles » :
## faïence par carreau comme les sols (missing, broken, chips) ; under : clé
## du fond des creux.
const WALL := {
	"wall": {"type": "painted", "base": 3, "rail": -1, "rail_h": 2, "patches": 0.14, "cracks": 0.12, "under": "brick",
		"base_key": "concrete_dark", "rail_key": "dark_wood"},
	"wall_green": {"type": "painted", "base": 3, "rail": -1, "rail_h": 2, "patches": 0.14, "cracks": 0.12, "under": "brick",
		"base_key": "concrete_dark", "rail_key": "dark_wood"},
	"wall_cell": {"type": "painted", "base": 3, "rail": -1, "rail_h": 2, "patches": 0.16, "cracks": 0.16, "under": "brick",
		"base_key": "concrete_dark", "rail_key": "dark_wood"},
	"wall_loges": {"type": "painted", "base": 3, "rail": -1, "rail_h": 2, "patches": 0.08, "cracks": 0.08, "under": "brick",
		"base_key": "dark_wood", "rail_key": "dark_wood"},
	"plaster_theater": {"type": "painted", "base": 3, "rail": -1, "rail_h": 2, "patches": 0.08, "cracks": 0.08, "under": "brick",
		"base_key": "dark_wood", "rail_key": "dark_wood"},
	"wall_lab": {"type": "tiles", "base": 2, "rail": 22, "rail_h": 2, "missing": 0.015, "broken": 0.03, "chips": 0.015,
		"under": "wall_concrete", "base_key": "concrete_dark", "rail_key": "steel"},
	"wall_concrete": {"type": "painted", "base": 0, "rail": 0, "rail_h": 0, "patches": 0.1, "cracks": 0.16, "under": "concrete_dark"},
	"wall_theater": {"type": "painted", "base": 2, "rail": 18, "rail_h": 2, "patches": 0.0, "cracks": 0.0, "under": "brick",
		"base_key": "dark_wood", "rail_key": "dark_wood"},
	"wall_lobby": {"type": "painted", "base": 2, "rail": 18, "rail_h": 2, "patches": 0.0, "cracks": 0.0, "under": "brick",
		"base_key": "dark_wood", "rail_key": "dark_wood"},
	"wall_foyer": {"type": "painted", "base": 2, "rail": 18, "rail_h": 2, "patches": 0.0, "cracks": 0.0, "under": "brick",
		"base_key": "dark_wood", "rail_key": "dark_wood"},
	"brick": {"type": "painted", "base": 0, "rail": 0, "rail_h": 0, "patches": 0.06, "cracks": 0.0, "under": "concrete_dark"},
}

## Profils des PLAFONDS : grid (ossature en saillie d'un cube sous les
## joints des dalles de `grid` pixels), missing (dalle tombée : creux de
## `depth` cubes, vide sombre ; les dalles noires de la texture en font
## toujours partie), void : clé du vide au-dessus.
const CEIL := {
	"ceiling": {"grid": 16, "missing": 0.015, "depth": 2, "void": "void"},
	"vault_theater": {"grid": 32, "missing": 0.0, "depth": 2, "void": "void"},
	"ceiling_theater": {"grid": 16, "missing": 0.0, "depth": 2, "void": "void"},
}

## Pas des sites (cubes) : nids-de-poule, fissures / flaques / plâtre tombé,
## tronçons de lame.
const HOLE_SITE := 16
const BIG_SITE := 32
const BOARD_SITE := 16

## Graine de la carte (identique sur toutes les machines).
var seed := 0
## Multiplicateur de toutes les probabilités (0 : aucun relief).
var density := 1.0
## Finesse des zones (m) : `ok` ne change pas plus finement (cellules de
## 1 m d'une carte en grille ; 20 cm par défaut) ; un creux est testé à ses
## coins et tous les `granularity` m.
var granularity := 0.2
## Repère -> {frame, cells {Vector2i: true} (creux), holes [Rect2i], buckets}.
var _planes: Dictionary = {}
## Pièces à construire : {"pit": true, fid, cells, depth, bottom, side, tag}
## ou {"pit": false, fid, rect, h, key, tag, skip}.
var _pieces: Array = []


## Repère d'une face plane : normale sur l'axe `axis` (0 x, 1 y, 2 z), de
## signe `sgn`, plan à `plane` cubes. Coordonnées dans le plan (cubes) :
## sol / plafond u = x, v = z ; mur de normale ±x : u = z, v = y ; ±z : u = x,
## v = y. Profondeur d : vers l'intérieur de la matière (creux) si d > 0,
## saillie si d < 0.
class Frame:
	var axis := 1
	var sgn := 1
	var plane := 0
	var _n := Vector3.UP
	var _eu := Vector3.RIGHT
	var _ev := Vector3.BACK

	func _init(a: int, s: int, p: int) -> void:
		axis = a
		sgn = s
		plane = p
		_n = Vector3.ZERO
		_n[axis] = sgn
		_eu = Vector3(0, 0, 1) if axis == 0 else Vector3(1, 0, 0)
		_ev = Vector3(0, 1, 0) if axis != 1 else Vector3(0, 0, 1)

	func id() -> Vector3i:
		return SurfaceRelief.plane_id(axis, sgn, plane)

	func n() -> Vector3:
		return _n

	func eu() -> Vector3:
		return _eu

	func ev() -> Vector3:
		return _ev

	## Point (m) des coordonnées (u, v, d) en cubes.
	func world(u: float, v: float, d: float) -> Vector3:
		var p := _eu * u + _ev * v
		p[axis] = plane - sgn * d
		return p * CUBE

	## Colonne de la texture (shader pixel_surface : u le long du mur, vu de
	## face) inversée par rapport à u (murs de normale +x et -z).
	func mirrored() -> bool:
		return (axis == 0 and sgn > 0) or (axis == 2 and sgn < 0)


# ------------------------------------------------------------------ graine et hasard

## Graine stable d'une carte (FNV-1a 32 bits de son identifiant).
static func seed_of(id: String) -> int:
	var h := 2166136261
	for b in id.to_utf8_buffer():
		h = ((h ^ b) * 16777619) & 0xFFFFFFFF
	return h


## Tirage 0..1 déterministe d'un site (a, b) pour un usage `salt`.
func _rand(a: int, b: int, salt: int) -> float:
	var h := ((a * 73856093) ^ (b * 19349663) ^ (salt * 83492791) ^ (seed * 2654435761)) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	h = ((h ^ (h >> 16)) * 2246822519) & 0xFFFFFFFF
	return float((h ^ (h >> 15)) & 0xFFFFFF) / 16777216.0


static func cubes(m: float) -> int:
	return roundi(m / CUBE)


static func on_grid(m: float) -> bool:
	return absf(m - roundf(m / CUBE) * CUBE) < 0.0005


func _plane(f: Frame) -> Dictionary:
	var fid := f.id()
	if not _planes.has(fid):
		_planes[fid] = {"frame": f, "cells": {}, "holes": [], "buckets": {}}
	return _planes[fid]


static func frame_of(n: Vector3i, plane: float) -> Frame:
	var axis := 0 if n.x != 0 else (1 if n.y != 0 else 2)
	return Frame.new(axis, n[axis], cubes(plane))


## Identifiant d'un plan (axe de la normale, signe, plan en cubes).
static func plane_id(axis: int, sgn: int, plane: int) -> Vector3i:
	return Vector3i(axis * 2 + (1 if sgn > 0 else 0), plane, 0)


## Données du plan de normale `n` à `plane` m (null : rien de repéré).
func _plane_at(n: Vector3i, plane: float) -> Variant:
	if _planes.is_empty():
		return null
	var axis := 0 if n.x != 0 else (1 if n.y != 0 else 2)
	return _planes.get(plane_id(axis, n[axis], cubes(plane)))


# ------------------------------------------------------------------ pièces

## Creux de `cells` (Vector2i, repère `f`) profond de `depth` cubes. Refusé
## si une cellule touche (ou est) une cellule déjà creusée du même plan.
func _add_pit(f: Frame, cells: Array, depth: int, bottom: String, side: String, tag: String) -> bool:
	if cells.is_empty():
		return false
	var pl := _plane(f)
	var taken: Dictionary = pl.cells
	# Voisins déjà creusés : seulement si un creux du plan touche le pavé
	# englobant (élargi d'un cube) ; alors test cellule par cellule.
	var b := _bounds(cells)
	var near := Rect2i(b.position - Vector2i.ONE, b.size + Vector2i(3, 3))
	var close := false
	for bj in range(floori(near.position.y / 20.0), floori((near.end.y - 1) / 20.0) + 1):
		for bi in range(floori(near.position.x / 20.0), floori((near.end.x - 1) / 20.0) + 1):
			for k: int in pl.buckets.get(Vector2i(bi, bj), []):
				if (pl.holes[k] as Rect2i).intersects(near):
					close = true
	if close:
		for c: Vector2i in cells:
			for dj in range(-1, 2):
				for di in range(-1, 2):
					if taken.has(c + Vector2i(di, dj)):
						return false
	var set := {}
	for c: Vector2i in cells:
		set[c] = true
		taken[c] = true
	var piece := {"pit": true, "f": f, "cells": set, "depth": depth, "bottom": bottom, "side": side, "tag": tag}
	var rects: Array
	if set.size() == (b.size.x + 1) * (b.size.y + 1):
		# Creux rectangulaire : construit d'un bloc (_emit_pit).
		piece["rect"] = Rect2i(b.position, b.size + Vector2i.ONE)
		rects = [piece.rect]
	else:
		rects = _merge(set)
	for r: Rect2i in rects:
		var k: int = (pl.holes as Array).size()
		pl.holes.append(r)
		for bj in range(floori(r.position.y / 20.0), floori((r.end.y - 1) / 20.0) + 1):
			for bi in range(floori(r.position.x / 20.0), floori((r.end.x - 1) / 20.0) + 1):
				(pl.buckets.get_or_add(Vector2i(bi, bj), []) as Array).append(k)
	_pieces.append(piece)
	return true


## Saillie : pavé `rect` (cubes, repère `f`) épais de `h` cubes hors de la
## surface ; `skip` : côtés non construits (« u0 », « u1 », « v0 », « v1 »).
func _add_box(f: Frame, rect: Rect2i, h: int, key: String, tag: String, skip := []) -> void:
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	_pieces.append({"pit": false, "f": f, "rect": rect, "h": h, "key": key, "tag": tag, "skip": skip})


## Nombre de pièces repérées (mesures, tests).
func piece_count() -> int:
	return _pieces.size()


## Cellules creusées du plan de normale `n` à `plane` m ({Vector2i: true}).
func pit_cells(n: Vector3i, plane: float) -> Dictionary:
	var pl: Variant = _plane_at(n, plane)
	return {} if pl == null else pl.cells


# ------------------------------------------------------------------ découpe des faces

## Rectangle `r` (cubes, plan de normale `n` à `plane` m) moins les creux :
## rectangles restants (Rect2i, cubes). Sans creux : [r].
func cut(n: Vector3i, plane: float, r: Rect2i) -> Array:
	var pl: Variant = _plane_at(n, plane)
	if pl == null or (pl.holes as Array).is_empty():
		return [r]
	var hits := []
	var seen := {}
	for bj in range(floori(r.position.y / 20.0), floori((r.end.y - 1) / 20.0) + 1):
		for bi in range(floori(r.position.x / 20.0), floori((r.end.x - 1) / 20.0) + 1):
			for k: int in pl.buckets.get(Vector2i(bi, bj), []):
				if seen.has(k):
					continue
				seen[k] = true
				var h: Rect2i = pl.holes[k]
				if h.intersects(r):
					hits.append(h.intersection(r))
	if hits.is_empty():
		return [r]
	return rect_minus(r, hits)


## Creux du plan de normale `n` à `plane` m qui touchent `bb` (m, plan u-v) :
## rectangles en mètres (Rect2, repère u-v du plan).
func holes(n: Vector3i, plane: float, bb: Rect2) -> Array:
	var pl: Variant = _plane_at(n, plane)
	var out := []
	if pl == null:
		return out
	for h: Rect2i in pl.holes:
		var r := Rect2(Vector2(h.position) * CUBE, Vector2(h.size) * CUBE)
		if r.intersects(bb):
			out.append(r)
	return out


## Rectangle moins des rectangles (cubes) : compression des coordonnées puis
## fusion gloutonne (bandes, puis bandes identiques empilées).
static func rect_minus(r: Rect2i, hits: Array) -> Array:
	var xs := {r.position.x: true, r.end.x: true}
	var ys := {r.position.y: true, r.end.y: true}
	for h: Rect2i in hits:
		xs[h.position.x] = true
		xs[h.end.x] = true
		ys[h.position.y] = true
		ys[h.end.y] = true
	var xk: Array = xs.keys()
	var yk: Array = ys.keys()
	xk.sort()
	yk.sort()
	var nx := xk.size() - 1
	var ny := yk.size() - 1
	var full := PackedByteArray()
	full.resize(nx * ny)
	for j in ny:
		for i in nx:
			var p := Vector2(xk[i] + xk[i + 1], yk[j] + yk[j + 1]) * 0.5
			var inside := true
			for h: Rect2i in hits:
				if p.x > h.position.x and p.x < h.end.x and p.y > h.position.y and p.y < h.end.y:
					inside = false
					break
			full[j * nx + i] = 1 if inside else 0
	var out := []
	var used := PackedByteArray()
	used.resize(nx * ny)
	for j in ny:
		for i in nx:
			if full[j * nx + i] == 0 or used[j * nx + i] == 1:
				continue
			var i1 := i
			while i1 + 1 < nx and full[j * nx + i1 + 1] == 1 and used[j * nx + i1 + 1] == 0:
				i1 += 1
			var j1 := j
			var grow := true
			while grow and j1 + 1 < ny:
				for ii in range(i, i1 + 1):
					if full[(j1 + 1) * nx + ii] == 0 or used[(j1 + 1) * nx + ii] == 1:
						grow = false
						break
				if grow:
					j1 += 1
			for jj in range(j, j1 + 1):
				for ii in range(i, i1 + 1):
					used[jj * nx + ii] = 1
			out.append(Rect2i(xk[i], yk[j], xk[i1 + 1] - xk[i], yk[j1 + 1] - yk[j]))
	return out


## Coins (m) du rectangle `r` (cubes) du plan de normale `n` à `plane` m, dans
## le sens direct vu de la normale ((b - a) × (c - a) · n > 0).
static func quad_pts(n: Vector3i, plane: float, r: Rect2i, d := 0.0) -> Array:
	var axis := 0 if n.x != 0 else (1 if n.y != 0 else 2)
	var eu := Vector3(0, 0, 1) if axis == 0 else Vector3(1, 0, 0)
	var ev := Vector3(0, 1, 0) if axis != 1 else Vector3(0, 0, 1)
	var base := Vector3.ZERO
	base[axis] = cubes(plane) - n[axis] * d
	var pts := []
	for c: Vector2i in [r.position, Vector2i(r.end.x, r.position.y), r.end, Vector2i(r.position.x, r.end.y)]:
		pts.append((base + eu * c.x + ev * c.y) * CUBE)
	return _ccw(pts, Vector3(n))


static func _ccw(p: Array, n: Vector3) -> Array:
	if ((p[1] as Vector3) - p[0]).cross((p[2] as Vector3) - p[0]).dot(n) < 0.0:
		return [p[0], p[3], p[2], p[1]]
	return p


## Face de normale `n` (axe) du pavé lo..hi (m), moins les creux de son plan :
## out.call(points (sens direct vu de la normale), normale) par rectangle.
func box_face(n: Vector3i, lo: Vector3, hi: Vector3, out: Callable) -> void:
	var a := 0 if n.x != 0 else (1 if n.y != 0 else 2)
	var plane: float = hi[a] if n[a] > 0 else lo[a]
	var ua := 2 if a == 0 else 0
	var va := 1 if a != 1 else 2
	var r := Rect2i(cubes(lo[ua]), cubes(lo[va]), cubes(hi[ua]) - cubes(lo[ua]), cubes(hi[va]) - cubes(lo[va]))
	for rr: Rect2i in cut(n, plane, r):
		out.call(quad_pts(n, plane, rr), Vector3(n))


# ------------------------------------------------------------------ repérage : sols

## Profil de sol de `key` (vide : pas de relief).
static func floor_profile(key: String) -> Dictionary:
	return FLOOR.get(key, {})


## Sol plat de la surface `key` à la hauteur `y` (m), dans `bb` (Rect2 en x, z,
## m) : `ok(x, z)` vrai sur ce sol hors des zones réservées (un creux et sa
## bordure d'un cube y sont tout entiers). `tag` : rendu au constructeur.
func plan_floor(key: String, y: float, bb: Rect2, ok: Callable, tag := "") -> void:
	var p := floor_profile(key)
	if not enabled or p.is_empty() or density <= 0.0 or not on_grid(y):
		return
	var f := Frame.new(1, 1, cubes(y))
	var lo := Vector2i(floori(bb.position.x / CUBE), floori(bb.position.y / CUBE))
	var hi := Vector2i(ceili(bb.end.x / CUBE), ceili(bb.end.y / CUBE))
	# Flaques d'abord (les plus grandes) : les autres creux s'écartent d'elles.
	_plan_puddles(f, key, p, lo, hi, ok, tag)
	match String(p.type):
		"tiles":
			_plan_tiles(f, key, p, lo, hi, 0, ok, Callable(), tag)
		"concrete":
			_plan_blobs(f, key, p, lo, hi, ok, tag)
		"planks":
			_plan_boards(f, key, p, lo, hi, ok, tag)


## Le pavé de cellules [c0, c1] (cubes, sol ou plafond) et sa bordure d'un
## cube sont-ils tout entiers dans la zone `ok` ? Points testés tous les
## 20 cm au plus, bords compris.
func _area_ok(ok: Callable, c0: Vector2i, c1: Vector2i, margin := 1) -> bool:
	var x0 := (c0.x - margin) * CUBE + 0.01
	var z0 := (c0.y - margin) * CUBE + 0.01
	var x1 := (c1.x + 1 + margin) * CUBE - 0.01
	var z1 := (c1.y + 1 + margin) * CUBE - 0.01
	var nx := maxi(1, ceili((x1 - x0) / granularity))
	var nz := maxi(1, ceili((z1 - z0) / granularity))
	for j in nz + 1:
		for i in nx + 1:
			if not ok.call(lerpf(x0, x1, float(i) / nx), lerpf(z0, z1, float(j) / nz)):
				return false
	return true


static func _bounds(cells: Array) -> Rect2i:
	var a: Vector2i = cells[0]
	var b: Vector2i = cells[0]
	for c: Vector2i in cells:
		a = a.min(c)
		b = b.max(c)
	return Rect2i(a, b - a)


## Carrelage (sol, faïence d'un mur) : carreaux de `ts` pixels sur la grille
## de la texture (joint d'un pixel autour). `vrow` : décalage des lignes de
## la texture (mur : ligne 0 au sol de la salle) ; `wall_ok(c0, c1)` (mur) :
## carreau admis.
@warning_ignore("integer_division")
func _plan_tiles(f: Frame, key: String, p: Dictionary, lo: Vector2i, hi: Vector2i, vrow: int, ok: Callable,
		wall_ok: Callable, tag: String) -> void:
	var d := PixelSurfaces.def(key) if PixelSurfaces.has(key) else {}
	var ts := int(d.get("ts", 8))
	var tex_missing := float(d.get("missing", 0.0))
	var s := int(d.get("seed", 0)) * 101
	var mir := f.mirrored()
	# Colonnes de la texture couvertes (col = u, ou -u - 1 en miroir).
	var c_lo := (-hi.x - 1) if mir else lo.x
	var c_hi := (-lo.x - 1) if mir else hi.x
	var pm := float(p.get("missing", 0.0)) * density
	var pb := float(p.get("broken", 0.0)) * density
	var pc := float(p.get("chips", 0.0)) * density
	# Carreaux manquants peints par la texture (même tirage que
	# PixelSurfaces._tiles), par carreau de l'image (qui se répète).
	var per := maxi(1, PixelSurfaces.SIZE / ts)
	var painted_at := PackedByteArray()
	painted_at.resize(per * per)
	for j in per:
		for i in per:
			painted_at[j * per + i] = 1 if tex_missing > 0.0 and PixelSurfaces.noise(i, j, s + 19) > 1.0 - tex_missing else 0
	for ty in range(floori(float(lo.y - vrow) / ts), floori(float(hi.y - vrow) / ts) + 1):
		for tx in range(floori(float(c_lo) / ts), floori(float(c_hi) / ts) + 1):
			var painted := painted_at[posmod(ty, per) * per + posmod(tx, per)] == 1
			var r := _rand(tx, ty, 11 + f.axis * 7 + f.sgn)
			var kind := ""
			if painted or r < pm:
				kind = "missing"
			elif r < pm + pb:
				kind = "broken"
			elif r < pm + pb + pc:
				kind = "chips"
			if kind == "":
				continue
			var cells := []
			var n := ts - 1
			var corner := int(_rand(tx, ty, 12) * 4.0)
			var k := 2 + int(_rand(tx, ty, 13) * (n - 3))
			for ly in n:
				for lx in n:
					var ax := lx if corner % 2 == 0 else n - 1 - lx
					var ay := ly if corner < 2 else n - 1 - ly
					var take := false
					match kind:
						"missing":
							take = true
						"broken":
							# Morceau de coin en escalier, bord irrégulier.
							take = ax + ay <= k or (ax + ay == k + 1 and _rand(tx * 8 + lx, ty * 8 + ly, 14) > 0.5)
						"chips":
							take = (ax == 0 and ay == 0) or (ax + ay == 1 and _rand(tx * 8 + lx, ty * 8 + ly, 15) > 0.45)
					if take:
						var col := tx * ts + lx
						var u := (-col - 1) if mir else col
						cells.append(Vector2i(u, ty * ts + ly + vrow))
			if cells.is_empty():
				continue
			var b := _bounds(cells)
			if wall_ok.is_valid():
				if not wall_ok.call(b.position, b.end):
					continue
			elif not _area_ok(ok, b.position, b.end):
				continue
			_add_pit(f, cells, 1, String(p.under), key, tag)


## Béton : nids-de-poule (taches de 3 à 7 cubes au bord irrégulier) et
## fissures (escalier d'un cube de large).
func _plan_blobs(f: Frame, key: String, p: Dictionary, lo: Vector2i, hi: Vector2i, ok: Callable, tag: String) -> void:
	var ph := float(p.get("holes", 0.0)) * density
	if ph > 0.0:
		for sy in range(floori(float(lo.y) / HOLE_SITE), floori(float(hi.y) / HOLE_SITE) + 1):
			for sx in range(floori(float(lo.x) / HOLE_SITE), floori(float(hi.x) / HOLE_SITE) + 1):
				if _rand(sx, sy, 21) >= ph:
					continue
				var c := Vector2i(sx * HOLE_SITE + 3 + int(_rand(sx, sy, 22) * 10), sy * HOLE_SITE + 3 + int(_rand(sx, sy, 23) * 10))
				var cells := _blob(c, 2.6 + _rand(sx, sy, 24) * 2.6, sx * 31 + sy, 25)
				var b := _bounds(cells)
				if _area_ok(ok, b.position, b.end):
					_add_pit(f, cells, 1, String(p.under), key, tag)
	var pk := float(p.get("cracks", 0.0)) * density
	if pk > 0.0:
		for sy in range(floori(float(lo.y) / BIG_SITE), floori(float(hi.y) / BIG_SITE) + 1):
			for sx in range(floori(float(lo.x) / BIG_SITE), floori(float(hi.x) / BIG_SITE) + 1):
				if _rand(sx, sy, 31) >= pk:
					continue
				var c := Vector2i(sx * BIG_SITE + 4 + int(_rand(sx, sy, 32) * 24), sy * BIG_SITE + 4 + int(_rand(sx, sy, 33) * 24))
				var cells := _crack(c, 7 + int(_rand(sx, sy, 34) * 12), sx * 17 + sy * 3, _rand(sx, sy, 35) > 0.5)
				var b := _bounds(cells)
				if _area_ok(ok, b.position, b.end):
					_add_pit(f, cells, 1, String(p.under), key, tag)


## Parquet : morceaux de lame arrachés (3 cubes de large, joint gardé, 4 à
## 11 cubes de long), sur les lames de la texture (bw pixels, le long de x).
func _plan_boards(f: Frame, key: String, p: Dictionary, lo: Vector2i, hi: Vector2i, ok: Callable, tag: String) -> void:
	var pb := float(p.get("boards", 0.0)) * density
	if pb <= 0.0:
		return
	var bw := int(PixelSurfaces.def(key).get("bw", 4)) if PixelSurfaces.has(key) else 4
	for row in range(floori(float(lo.y) / bw), floori(float(hi.y) / bw) + 1):
		for sx in range(floori(float(lo.x) / BOARD_SITE), floori(float(hi.x) / BOARD_SITE) + 1):
			if _rand(sx, row, 41) >= pb:
				continue
			var x0 := sx * BOARD_SITE + int(_rand(sx, row, 42) * 8)
			var length := 4 + int(_rand(sx, row, 43) * 8)
			var cells := []
			for j in bw - 1:
				# Bout cassé en escalier.
				var cut := int(_rand(sx, row * 8 + j, 44) * 3)
				for x in range(x0 + (cut if j % 2 == 0 else 0), x0 + length - (0 if j % 2 == 0 else cut)):
					cells.append(Vector2i(x, row * bw + j))
			var b := _bounds(cells)
			if _area_ok(ok, b.position, b.end):
				_add_pit(f, cells, 1, String(p.under), key, tag)


## Flaques : deux ou trois disques mêlés, en creux d'un cube, eau au fond.
func _plan_puddles(f: Frame, key: String, p: Dictionary, lo: Vector2i, hi: Vector2i, ok: Callable, tag: String) -> void:
	var pp := float(p.get("puddles", 0.0)) * density
	if pp <= 0.0:
		return
	for sy in range(floori(float(lo.y) / BIG_SITE), floori(float(hi.y) / BIG_SITE) + 1):
		for sx in range(floori(float(lo.x) / BIG_SITE), floori(float(hi.x) / BIG_SITE) + 1):
			if _rand(sx, sy, 51) >= pp:
				continue
			var c := Vector2i(sx * BIG_SITE + 8 + int(_rand(sx, sy, 52) * 16), sy * BIG_SITE + 8 + int(_rand(sx, sy, 53) * 16))
			var set := {}
			for k in 2 + int(_rand(sx, sy, 54) * 2):
				var o := Vector2i(int(_rand(sx, sy, 55 + k) * 9) - 4, int(_rand(sx, sy, 58 + k) * 7) - 3)
				for cc in _blob(c + o, 2.2 + _rand(sx, sy, 61 + k) * 2.8, sx * 13 + sy * 7 + k, 62):
					set[cc] = true
			var cells := set.keys()
			var b := _bounds(cells)
			if _area_ok(ok, b.position, b.end):
				_add_pit(f, cells, 1, "puddle", key, tag)


## Tache ronde de rayon `r` cubes autour de `c`, bord rongé (tirage `s`).
func _blob(c: Vector2i, r: float, s: int, salt: int) -> Array:
	var out := []
	var ri := ceili(r) + 1
	for j in range(-ri, ri + 1):
		for i in range(-ri, ri + 1):
			var dd := Vector2(i, j).length()
			if dd <= r - 0.6 or (dd <= r + 0.4 and _rand(s * 64 + i, j, salt) > 0.45):
				out.append(c + Vector2i(i, j))
	return out


## Fissure : marche de cellules (comme PixelSurfaces._cracks), le long de u ou v.
func _crack(c: Vector2i, length: int, s: int, along_u: bool) -> Array:
	var out := []
	var p := c
	var dx := 1 if _rand(s, 0, 71) > 0.5 else -1
	for i in length:
		out.append(p)
		var side := _rand(s, i, 72) > 0.45
		if along_u:
			p += Vector2i(1, 0) if not side else Vector2i(0, dx)
		else:
			p += Vector2i(0, 1) if not side else Vector2i(dx, 0)
	return out


# ------------------------------------------------------------------ repérage : murs

static func wall_profile(key: String) -> Dictionary:
	return WALL.get(key, {})


## Face de mur plane de normale `n` (±x ou ±z), plan à `plane` m, de `u0` à
## `u1` (m, le long de z pour un mur de normale ±x, de x sinon) et de `y0` à
## `y1` (m) ; `floor_y` : sol de la salle (ligne 0 de la texture du mur).
## `free(x, z)` : point devant le mur hors zones réservées (objets muraux,
## portes, fenêtres) ; plinthe et cimaise s'y interrompent, aucun creux.
func plan_wall(key: String, n: Vector3i, plane: float, u0: float, u1: float, y0: float, y1: float, floor_y: float,
		free: Callable, tag := "") -> void:
	var p := wall_profile(key)
	if not enabled or p.is_empty() or density <= 0.0 or n.y != 0:
		return
	if not (on_grid(plane) and on_grid(u0) and on_grid(u1) and on_grid(y0) and on_grid(y1) and on_grid(floor_y)):
		return
	var f := frame_of(n, plane)
	var a := cubes(minf(u0, u1))
	var b := cubes(maxf(u0, u1))
	var fy := cubes(floor_y)
	var v0 := maxi(cubes(y0), fy)
	var v1 := cubes(y1)
	if b - a < 4 or v1 - v0 < 4:
		return
	# Morceaux du mur libres (zones réservées : rien), testés tous les 25 cm.
	var runs := _free_runs(f, a, b, fy, free)
	var base := int(p.get("base", 0))
	var rail := int(p.get("rail", 0))
	if rail < 0:
		rail = int(PixelSurfaces.def(key).get("band", 25)) if PixelSurfaces.has(key) else 25
	var rail_h := int(p.get("rail_h", 1))
	for run: Vector2i in runs:
		# Plinthe : seulement sur un mur qui part du sol de la salle.
		if base > 0 and v0 == fy and v1 >= fy + base + 2:
			_add_box(f, Rect2i(run.x, fy, run.y - run.x, base), 1, String(p.get("base_key", key)), tag, ["v0"])
		if rail > 0 and rail_h > 0 and v0 <= fy + rail and fy + rail + rail_h <= v1 - 2:
			_add_box(f, Rect2i(run.x, fy + rail, run.y - run.x, rail_h), 1, String(p.get("rail_key", key)), tag)
	# Creux : au-dessus de la plinthe, hors de la cimaise, loin des bords.
	var lo_v := maxi(v0, fy + base) + 2
	var hi_v := v1 - 3
	if hi_v - lo_v < 4:
		return
	var bands := []
	if rail > 0 and rail_h > 0:
		bands = [Vector2i(lo_v, fy + rail - 2), Vector2i(fy + rail + rail_h + 2, hi_v)]
	else:
		bands = [Vector2i(lo_v, hi_v)]
	var inside := func(c0: Vector2i, c1: Vector2i) -> bool:
		if c0.x < a + 3 or c1.x > b - 4:
			return false
		var in_band := false
		for bd: Vector2i in bands:
			if c0.y >= bd.x and c1.y <= bd.y:
				in_band = true
		if not in_band:
			return false
		for run: Vector2i in runs:
			if c0.x >= run.x + 2 and c1.x <= run.y - 3:
				return true
		return false
	match String(p.type):
		"tiles":
			_plan_tiles(f, key, p, Vector2i(a, v0), Vector2i(b, v1), fy, Callable(), inside, tag)
		"painted":
			_plan_patches(f, key, p, a, b, v0, v1, inside, tag)


## Morceaux [début, fin) (cubes) de [a, b) dont le devant est libre (`free`),
## testés tous les 5 cubes.
func _free_runs(f: Frame, a: int, b: int, fy: int, free: Callable) -> Array:
	if not free.is_valid():
		return [Vector2i(a, b)]
	var out := []
	var start := -1
	var u := a
	while u < b:
		var e := mini(u + 5, b)
		var p := f.world((u + e) * 0.5, fy + 20, -6)
		var ok: bool = free.call(p.x, p.z)
		if ok and start < 0:
			start = u
		elif not ok and start >= 0:
			out.append(Vector2i(start, u))
			start = -1
		u = e
	if start >= 0:
		out.append(Vector2i(start, b))
	return out.filter(func(r: Vector2i) -> bool: return r.y - r.x >= 2)


## Mur peint / béton : plâtre tombé (tache, briques dessous) et fissures.
func _plan_patches(f: Frame, key: String, p: Dictionary, a: int, b: int, v0: int, v1: int, inside: Callable, tag: String) -> void:
	var pp := float(p.get("patches", 0.0)) * density
	var pk := float(p.get("cracks", 0.0)) * density
	var salt := 81 + f.axis * 3 + f.sgn
	for sy in range(floori(float(v0) / BIG_SITE), floori(float(v1) / BIG_SITE) + 1):
		for sx in range(floori(float(a) / BIG_SITE), floori(float(b) / BIG_SITE) + 1):
			var r := _rand(sx + f.plane * 97, sy, salt)
			var cells := []
			if r < pp:
				var c := Vector2i(sx * BIG_SITE + 6 + int(_rand(sx, sy + f.plane, salt + 1) * 20), sy * BIG_SITE + 6 + int(_rand(sx, sy + f.plane, salt + 2) * 20))
				var set := {}
				for k in 1 + int(_rand(sx, sy, salt + 3) * 2):
					var o := Vector2i(int(_rand(sx, sy, salt + 4 + k) * 7) - 3, int(_rand(sx, sy, salt + 6 + k) * 5) - 2)
					for cc in _blob(c + o, 2.4 + _rand(sx, sy, salt + 8 + k) * 2.8, sx * 7 + sy * 5 + k + f.plane, salt + 9):
						set[cc] = true
				cells = set.keys()
			elif r < pp + pk:
				var c := Vector2i(sx * BIG_SITE + 4 + int(_rand(sx, sy + f.plane, salt + 11) * 24), sy * BIG_SITE + 8 + int(_rand(sx, sy + f.plane, salt + 12) * 16))
				cells = _crack(c, 6 + int(_rand(sx, sy, salt + 13) * 10), sx * 11 + sy + f.plane, false)
			if cells.is_empty():
				continue
			var bb := _bounds(cells)
			if inside.call(bb.position, bb.end):
				_add_pit(f, cells, 1, String(p.under), String(p.under), tag)


# ------------------------------------------------------------------ repérage : plafonds

static func ceiling_profile(key: String) -> Dictionary:
	return CEIL.get(key, {})


## Plafond plat de la surface `key` à la hauteur `y` (m), dans `bb` (x, z, m) :
## `ok(x, z)` vrai sous ce plafond ; `free(x, z)` : dalle tombée admise (pas
## au-dessus d'une lampe). `step` (m) : finesse des changements de `ok`
## ; on affine ensuite au cube par dichotomie) ; `aligned` : `ok` ne change
## qu'aux multiples de `step` (grille de cellules : aucun affinage).
@warning_ignore("integer_division")
func plan_ceiling(key: String, y: float, bb: Rect2, ok: Callable, free: Callable, tag := "", step := 0.25, aligned := false) -> void:
	var p := ceiling_profile(key)
	if not enabled or p.is_empty() or density <= 0.0 or not on_grid(y):
		return
	var f := Frame.new(1, -1, cubes(y))
	var ps := int(p.grid)
	var lo := Vector2i(floori(bb.position.x / CUBE), floori(bb.position.y / CUBE))
	var hi := Vector2i(ceili(bb.end.x / CUBE), ceili(bb.end.y / CUBE))
	# Ossature : lignes de joints de la texture (pixel ps - 1 de chaque dalle),
	# profilés continus dans les deux sens. Aux croisements, les dessous des
	# deux profilés se confondent (même plan, même matériau posé en
	# coordonnées monde : mêmes pixels, aucun scintillement) : un pavé par
	# ligne au lieu d'un par dalle.
	for col in range(lo.x, hi.x):
		if posmod(col, ps) != ps - 1:
			continue
		for run: Vector2i in _line_runs(ok, true, col, lo.y, hi.y, step, aligned):
			_add_box(f, Rect2i(col, run.x, 1, run.y - run.x), 1, key, tag)
	for row in range(lo.y, hi.y):
		if posmod(row, ps) != ps - 1:
			continue
		for run: Vector2i in _line_runs(ok, false, row, lo.x, hi.x, step, aligned):
			_add_box(f, Rect2i(run.x, row, run.y - run.x, 1), 1, key, tag)
	# Dalles tombées : creux sombres (les dalles noires de la texture aussi).
	var d := PixelSurfaces.def(key) if PixelSurfaces.has(key) else {}
	var s := int(d.get("seed", 0)) * 101
	var pm := float(p.get("missing", 0.0)) * density
	# Dalles noires de la texture (PixelSurfaces._ceiling), par dalle de
	# l'image (qui se répète).
	var per := maxi(1, PixelSurfaces.SIZE / ps)
	var dark := String(d.get("gen", "")) == "ceiling" and not bool(d.get("coffer", false))
	var painted_at := PackedByteArray()
	painted_at.resize(per * per)
	for j in per:
		for i in per:
			painted_at[j * per + i] = 1 if dark and PixelSurfaces.noise(i, j, s + 3) > 0.975 else 0
	for py in range(floori(float(lo.y) / ps), floori(float(hi.y) / ps) + 1):
		for px in range(floori(float(lo.x) / ps), floori(float(hi.x) / ps) + 1):
			var painted := painted_at[posmod(py, per) * per + posmod(px, per)] == 1
			if not painted and _rand(px, py, 91) >= pm:
				continue
			var c0 := Vector2i(px * ps, py * ps)
			var c1 := c0 + Vector2i(ps - 2, ps - 2)
			if not _area_ok(ok, c0, c1, 1) or (free.is_valid() and not _area_ok(free, c0, c1, 2)):
				continue
			var cells := []
			for j in ps - 1:
				for i in ps - 1:
					cells.append(c0 + Vector2i(i, j))
			_add_pit(f, cells, int(p.depth), String(p.void), String(p.void), tag)


## Morceaux [début, fin) (cubes) de la ligne `line` (colonne si `along_z`)
## entre a et b où `ok` est vrai au milieu de chaque cube : échantillons tous
## les `step` m, affinés au cube près là où `ok` change.
static func _line_runs(ok: Callable, along_z: bool, line: int, a: int, b: int, step: float, aligned := false) -> Array:
	var stride := maxi(1, roundi(step / CUBE))
	var w := (line + 0.5) * CUBE
	var out := []
	var start := -1
	if aligned:
		# `ok` ne change qu'aux multiples de `step` (cellules d'une grille) :
		# un test au milieu de chaque bloc suffit.
		var k0 := floori(float(a) / stride)
		var k1 := ceili(float(b) / stride)
		for k in range(k0, k1):
			var q := (k + 0.5) * stride * CUBE
			var cur: bool = ok.call(w, q) if along_z else ok.call(q, w)
			var t := maxi(k * stride, a)
			if cur and start < 0:
				start = t
			elif not cur and start >= 0:
				out.append(Vector2i(start, t))
				start = -1
		if start >= 0:
			out.append(Vector2i(start, b))
		return out.filter(func(r: Vector2i) -> bool: return r.y - r.x >= 2)
	var t := a
	var prev: bool = ok.call(w, (a + 0.5) * CUBE) if along_z else ok.call((a + 0.5) * CUBE, w)
	if prev:
		start = a
	while t < b:
		var nt := mini(t + stride, b - 1)
		if nt <= t:
			break
		var cur: bool = ok.call(w, (nt + 0.5) * CUBE) if along_z else ok.call((nt + 0.5) * CUBE, w)
		if cur != prev:
			# Changement entre t et nt : premier cube du nouvel état, par
			# dichotomie.
			var lo := t
			var hi := nt
			while hi - lo > 1:
				var m := (lo + hi) >> 1
				var v: bool = ok.call(w, (m + 0.5) * CUBE) if along_z else ok.call((m + 0.5) * CUBE, w)
				if v == prev:
					lo = m
				else:
					hi = m
			if cur:
				start = hi
			else:
				out.append(Vector2i(start, hi))
				start = -1
			prev = cur
		t = nt
	if start >= 0:
		out.append(Vector2i(start, b))
	return out.filter(func(r: Vector2i) -> bool: return r.y - r.x >= 2)


# ------------------------------------------------------------------ construction

## Faces du relief : out.call(clé, tag, points (sens direct vu de la normale),
## normale) pour chaque rectangle (tests, petites scènes ; les constructeurs
## prennent emit_groups). Creux : fond (clé `bottom`) et parois (clé
## `side`) ; saillies : devant et côtés.
func emit(out: Callable) -> void:
	var groups := emit_groups()
	for key: String in groups:
		for tag: String in groups[key]:
			var v: PackedVector3Array = groups[key][tag][0]
			var nn: PackedVector3Array = groups[key][tag][1]
			for i in range(0, v.size(), 6):
				# Triangles avant (sens horaire) -> rectangle en sens direct.
				if v[i + 4].is_equal_approx(v[i + 2]):
					out.call(key, tag, [v[i], v[i + 5], v[i + 2], v[i + 1]], nn[i])
				else:
					out.call(key, tag, [v[i], v[i + 2], v[i + 1], v[i + 4]], nn[i])


## Faces du relief rangées par clé et par `tag` :
## {clé: {tag: [sommets, normales] (PackedVector3Array, triangles avant de
## Godot, sens horaire)}}. Avec `tile` > 0 (m), le tag est la tuile de la
## pièce : « x_z » (tuiles de rendu d'une carte en grille).
func emit_groups(tile := 0.0) -> Dictionary:
	var groups := {}
	for pc: Dictionary in _pieces:
		var f: Frame = pc.f
		if tile > 0.0:
			var c := _piece_center(pc)
			pc.tag = "%d_%d" % [floori(c.x / tile), floori(c.z / tile)]
		if pc.pit:
			_emit_pit(f, pc, groups)
		else:
			_emit_box(f, pc, groups)
	# Tableaux -> tableaux compacts (une conversion par groupe).
	for key: String in groups:
		for tag: String in groups[key]:
			var g: Array = groups[key][tag]
			groups[key][tag] = [PackedVector3Array(g[0]), PackedVector3Array(g[1])]
	return groups


## Groupe [sommets, normales] (Array) de `key` / `tag` dans `groups`.
static func _group_of(groups: Dictionary, key: String, tag: String) -> Array:
	var bt: Dictionary = groups.get(key, {})
	if bt.is_empty():
		groups[key] = bt
	var g: Variant = bt.get(tag)
	if g == null:
		g = [[], []]
		bt[tag] = g
	return g


## Rectangle a, b, c, d de normale `n` ajouté à `g` en deux triangles avant
## (Godot : sens horaire vu de la normale), quel que soit son sens.
static func _push(g: Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	var v: Array = g[0]
	var nn: Array = g[1]
	if (b - a).cross(c - a).dot(n) > 0.0:
		v.append_array([a, c, b, a, d, c])
	else:
		v.append_array([a, b, c, a, c, d])
	nn.append_array([n, n, n, n, n, n])


## Milieu (m) d'une pièce, au nu de sa surface.
static func _piece_center(pc: Dictionary) -> Vector3:
	var f: Frame = pc.f
	if pc.pit:
		var cells: Dictionary = pc.cells
		var c: Vector2i = cells.keys()[0]
		return f.world(c.x + 0.5, c.y + 0.5, 0)
	var r: Rect2i = pc.rect
	return f.world(r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.5, 0)


func _emit_pit(f: Frame, pc: Dictionary, groups: Dictionary) -> void:
	var cells: Dictionary = pc.cells
	var d := float(pc.depth)
	var n := f.n()
	var tag: String = pc.tag
	var gb := _group_of(groups, String(pc.bottom), tag)
	var gs := _group_of(groups, String(pc.side), tag)
	var full: Variant = pc.get("rect")
	if full != null:
		# Creux rectangulaire (carreau, dalle) : un fond, quatre parois.
		var r: Rect2i = full
		var u0 := r.position.x
		var u1 := r.end.x
		var v0 := r.position.y
		var v1 := r.end.y
		_push(gb, f.world(u0, v0, d), f.world(u1, v0, d), f.world(u1, v1, d), f.world(u0, v1, d), n)
		_push(gs, f.world(u0, v0, 0), f.world(u0, v1, 0), f.world(u0, v1, d), f.world(u0, v0, d), f.eu())
		_push(gs, f.world(u1, v0, 0), f.world(u1, v1, 0), f.world(u1, v1, d), f.world(u1, v0, d), -f.eu())
		_push(gs, f.world(u0, v0, 0), f.world(u1, v0, 0), f.world(u1, v0, d), f.world(u0, v0, d), f.ev())
		_push(gs, f.world(u0, v1, 0), f.world(u1, v1, 0), f.world(u1, v1, d), f.world(u0, v1, d), -f.ev())
		return
	for r: Rect2i in _merge(cells):
		_push(gb, f.world(r.position.x, r.position.y, d), f.world(r.end.x, r.position.y, d),
			f.world(r.end.x, r.end.y, d), f.world(r.position.x, r.end.y, d), n)
	# Parois : bords des cellules dont la voisine n'est pas creusée, réunis
	# en bandes le long de chaque ligne.
	var edges := {}   # Vector3i(dir, ligne, 0) -> [positions le long]
	for c: Vector2i in cells:
		if not cells.has(c + Vector2i(1, 0)):
			(edges.get_or_add(Vector3i(0, c.x + 1, 0), []) as Array).append(c.y)
		if not cells.has(c + Vector2i(-1, 0)):
			(edges.get_or_add(Vector3i(1, c.x, 0), []) as Array).append(c.y)
		if not cells.has(c + Vector2i(0, 1)):
			(edges.get_or_add(Vector3i(2, c.y + 1, 0), []) as Array).append(c.x)
		if not cells.has(c + Vector2i(0, -1)):
			(edges.get_or_add(Vector3i(3, c.y, 0), []) as Array).append(c.x)
	for k: Vector3i in edges:
		var list: Array = edges[k]
		list.sort()
		var runs := []
		for t: int in list:
			if not runs.is_empty() and runs[-1].y == t:
				runs[-1].y = t + 1
			else:
				runs.append(Vector2i(t, t + 1))
		var ln := k.y
		for run: Vector2i in runs:
			if k.x < 2:
				_push(gs, f.world(ln, run.x, 0), f.world(ln, run.y, 0), f.world(ln, run.y, d), f.world(ln, run.x, d),
					-f.eu() if k.x == 0 else f.eu())
			else:
				_push(gs, f.world(run.x, ln, 0), f.world(run.y, ln, 0), f.world(run.y, ln, d), f.world(run.x, ln, d),
					-f.ev() if k.x == 2 else f.ev())


func _emit_box(f: Frame, pc: Dictionary, groups: Dictionary) -> void:
	var r: Rect2i = pc.rect
	var h := -float(pc.h)
	var g := _group_of(groups, String(pc.key), String(pc.tag))
	var skip: Array = pc.skip
	# Huit coins : a.. au nu de la surface, b.. au devant de la saillie.
	var a00 := f.world(r.position.x, r.position.y, 0)
	var a10 := f.world(r.end.x, r.position.y, 0)
	var a11 := f.world(r.end.x, r.end.y, 0)
	var a01 := f.world(r.position.x, r.end.y, 0)
	var off := f.n() * (-h * CUBE)
	var b00 := a00 + off
	var b10 := a10 + off
	var b11 := a11 + off
	var b01 := a01 + off
	_push(g, b00, b10, b11, b01, f.n())
	if not "u0" in skip:
		_push(g, a00, a01, b01, b00, -f.eu())
	if not "u1" in skip:
		_push(g, a10, a11, b11, b10, f.eu())
	if not "v0" in skip:
		_push(g, a00, a10, b10, b00, -f.ev())
	if not "v1" in skip:
		_push(g, a01, a11, b11, b01, f.ev())


## Cellules {Vector2i: true} -> rectangles (bandes le long de u, puis bandes
## identiques des rangées voisines réunies).
static func _merge(cells: Dictionary) -> Array:
	var rows := {}
	for c: Vector2i in cells:
		(rows.get_or_add(c.y, []) as Array).append(c.x)
	var ys := rows.keys()
	ys.sort()
	var open := {}   # Vector2i(u0, u1) -> Rect2i en cours
	var out := []
	for y: int in ys:
		var xs: Array = rows[y]
		xs.sort()
		var bands := []
		for x: int in xs:
			if not bands.is_empty() and bands[-1].y == x:
				bands[-1].y = x + 1
			else:
				bands.append(Vector2i(x, x + 1))
		var next := {}
		for bd: Vector2i in bands:
			var r: Variant = open.get(bd)
			if r != null and (r as Rect2i).end.y == y:
				next[bd] = (r as Rect2i).grow_side(SIDE_BOTTOM, 1)
				open.erase(bd)
			else:
				next[bd] = Rect2i(bd.x, y, bd.y - bd.x, 1)
		out.append_array(open.values())
		open = next
	out.append_array(open.values())
	return out


# ------------------------------------------------------------------ matériau de l'eau

static var _puddle_mat: StandardMaterial3D


static var _void_mat: StandardMaterial3D


## Vide sous un plancher arraché ou au-dessus d'une dalle tombée : presque
## noir, mat.
static func void_material() -> StandardMaterial3D:
	if _void_mat == null:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.035, 0.03, 0.028)
		m.roughness = 1.0
		_void_mat = m
	return _void_mat


## Matériau d'une clé du relief : l'eau des flaques, le vide, sinon la
## surface pixel art (WorldLook.surface).
static func material(key: String) -> Material:
	match key:
		"puddle":
			return puddle_material()
		"void":
			return void_material()
	return WorldLook.surface(key)


## Eau des flaques : presque noire, très lisse (reflets des lampes).
static func puddle_material() -> StandardMaterial3D:
	if _puddle_mat == null:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.17, 0.22, 0.26)
		m.roughness = 0.07
		m.metallic_specular = 1.0
		_puddle_mat = m
	return _puddle_mat
