class_name MapData
extends RefCounted
## Grille de la carte décrite en ASCII (1 caractère = 1 cellule de CELL mètres).
##
## Légende de base :
##   ' '  vide (hors carte)
##   '#'  mur plein
##   a-z  sol, la lettre indique la zone (a = zone de départ)
##   '.'  sol de la zone 'a'
## Les autres caractères sont des « marqueurs » posés sur du sol : leur zone est
## déduite de la cellule de sol voisine la plus fréquente. Leur signification est
## donnée par la définition de carte (MapDef).

const CELL := 1.0

var width := 0
var height := 0
## Contenu brut : un octet par cellule.
var cells: PackedByteArray
## Zone (lettre) de chaque cellule de sol, 0 sinon.
var zones: PackedByteArray
## symbole -> Array[Vector2i]
var markers: Dictionary = {}


static func parse(rows: PackedStringArray) -> MapData:
	var m := MapData.new()
	m.height = rows.size()
	for r in rows:
		m.width = maxi(m.width, r.length())
	m.cells.resize(m.width * m.height)
	m.cells.fill(32)
	m.zones.resize(m.width * m.height)
	for y in m.height:
		var row: String = rows[y]
		for x in row.length():
			var c := row.unicode_at(x)
			m.cells[y * m.width + x] = c
			if c == 46:  # '.'
				m.zones[y * m.width + x] = 97  # 'a'
			elif c >= 97 and c <= 122:
				m.zones[y * m.width + x] = c
			elif c != 32 and c != 35:
				var key := String.chr(c)
				if not m.markers.has(key):
					m.markers[key] = []
				m.markers[key].append(Vector2i(x, y))
	# Les marqueurs sont du sol : on leur attribue la zone voisine majoritaire.
	# Un marqueur entouré d'autres marqueurs (centre d'un bloc de piège 3x3...)
	# hérite ensuite, de proche en proche, de la zone de ses voisins résolus.
	var pending: Array[Vector2i] = []
	for key in m.markers:
		for cell in m.markers[key]:
			var z := m._neighbour_zone(cell)
			m.zones[cell.y * m.width + cell.x] = z
			if z == 0:
				pending.append(cell)
	while not pending.is_empty():
		var left: Array[Vector2i] = []
		var solved := {}
		for cell in pending:
			var z := m._neighbour_zone(cell, true)
			if z == 0:
				left.append(cell)
			else:
				solved[cell] = z
		for cell in solved:
			m.zones[cell.y * m.width + cell.x] = solved[cell]
		if solved.is_empty():
			for cell in left:
				m.zones[cell.y * m.width + cell.x] = 97
			break
		pending = left
	return m


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height


func at(c: Vector2i) -> int:
	return cells[c.y * width + c.x] if in_bounds(c) else 32


func is_wall(c: Vector2i) -> bool:
	return at(c) == 35


func is_void(c: Vector2i) -> bool:
	return at(c) == 32


func is_floor(c: Vector2i) -> bool:
	var v := at(c)
	return v != 32 and v != 35


func zone_at(c: Vector2i) -> String:
	if not in_bounds(c):
		return ""
	var z := zones[c.y * width + c.x]
	return String.chr(z) if z != 0 else ""


static func cell_to_world(c: Vector2i, y := 0.0) -> Vector3:
	return Vector3((c.x + 0.5) * CELL, y, (c.y + 0.5) * CELL)


static func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


## Centre de plusieurs cellules (ex. un marqueur de 2 cases de large).
static func cells_center(list: Array, y := 0.0) -> Vector3:
	var acc := Vector3.ZERO
	for c in list:
		acc += cell_to_world(c, y)
	return acc / maxf(list.size(), 1)


## Zone majoritaire des 8 voisins (lettres de sol ; avec `resolved`, aussi les
## zones déjà attribuées aux marqueurs voisins). 0 si aucune.
func _neighbour_zone(c: Vector2i, resolved := false) -> int:
	var counts := {}
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		var n: Vector2i = c + d
		if not in_bounds(n):
			continue
		var v := cells[n.y * width + n.x]
		var z := 0
		if v == 46:
			z = 97
		elif v >= 97 and v <= 122:
			z = v
		elif resolved and v != 32 and v != 35:
			z = zones[n.y * width + n.x]
		if z != 0:
			counts[z] = counts.get(z, 0) + 1
	if counts.is_empty():
		return 0
	var best := 97
	var best_n := -1
	for z in counts:
		if counts[z] > best_n:
			best = z
			best_n = counts[z]
	return best


## Découpe un ensemble de cellules en rectangles (fusion gloutonne).
## `pred` : Callable(Vector2i) -> bool. Retourne Array[Rect2i].
func greedy_rects(pred: Callable) -> Array[Rect2i]:
	var used := PackedByteArray()
	used.resize(width * height)
	var out: Array[Rect2i] = []
	for y in height:
		for x in width:
			if used[y * width + x] or not pred.call(Vector2i(x, y)):
				continue
			var w := 1
			while x + w < width and not used[y * width + x + w] and pred.call(Vector2i(x + w, y)):
				w += 1
			var h := 1
			var grow := true
			while grow and y + h < height:
				for i in w:
					if used[(y + h) * width + x + i] or not pred.call(Vector2i(x + i, y + h)):
						grow = false
						break
				if grow:
					h += 1
			for yy in h:
				for xx in w:
					used[(y + yy) * width + x + xx] = 1
			out.append(Rect2i(x, y, w, h))
	return out
