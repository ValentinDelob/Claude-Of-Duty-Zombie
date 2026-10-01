class_name NavGrid
extends MapNav
## Navigation des zombies (serveur uniquement) sur la grille de la carte.
##
## AStarGrid2D (natif, rapide) + lissage des chemins par ligne de vue. Les
## cellules proches des murs coûtent plus cher : les zombies passent au milieu
## des couloirs au lieu de raser les angles. Les portes fermées sont des
## cellules bloquées, débloquées à l'ouverture.

const WALL_PENALTY := 2.5

var data: MapData
var astar := AStarGrid2D.new()
var _blocked: Dictionary = {}  # Vector2i -> true (cellules bloquées dynamiquement)
## Copie « praticable » de la grille (1 octet par cellule) : les tests de ligne
## de vue, appelés très souvent, y lisent directement sans passer par AStarGrid2D.
var _walk := PackedByteArray()
var _w := 0
var _h := 0


func _init(map_data: MapData) -> void:
	data = map_data
	astar.region = Rect2i(0, 0, data.width, data.height)
	astar.cell_size = Vector2(MapData.CELL, MapData.CELL)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for y in data.height:
		for x in data.width:
			var c := Vector2i(x, y)
			if not data.is_floor(c):
				astar.set_point_solid(c, true)
			elif _near_wall(c):
				astar.set_point_weight_scale(c, WALL_PENALTY)
	_w = data.width
	_h = data.height
	_walk.resize(_w * _h)
	for y in _h:
		for x in _w:
			_walk[y * _w + x] = 0 if astar.is_point_solid(Vector2i(x, y)) else 1


func _near_wall(c: Vector2i) -> bool:
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if not data.is_floor(c + Vector2i(dx, dy)):
				return true
	return false


func is_walkable(c: Vector2i) -> bool:
	return astar.is_in_boundsv(c) and not astar.is_point_solid(c)


## Bloque / débloque des cellules (portes, barricades...).
func set_blocked(cells: Array, blocked: bool) -> void:
	for c in cells:
		if not astar.is_in_boundsv(c):
			continue
		if blocked:
			_blocked[c] = true
			astar.set_point_solid(c, true)
		else:
			_blocked.erase(c)
			astar.set_point_solid(c, not data.is_floor(c))
		_walk[c.y * _w + c.x] = 0 if astar.is_point_solid(c) else 1


## Cellule praticable la plus proche (recherche en spirale).
func nearest_walkable(c: Vector2i, max_radius := 4) -> Vector2i:
	if is_walkable(c):
		return c
	for r in range(1, max_radius + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var n := c + Vector2i(dx, dy)
				if is_walkable(n):
					return n
	return Vector2i(-1, -1)


## Chemin lissé en coordonnées monde (y = 0). Vide si inaccessible.
func find_path(from: Vector3, to: Vector3, _lane_bias := 0.0) -> PackedVector3Array:
	var a := nearest_walkable(MapData.world_to_cell(from))
	var b := nearest_walkable(MapData.world_to_cell(to))
	var out := PackedVector3Array()
	if a.x < 0 or b.x < 0:
		return out
	var cells := astar.get_id_path(a, b)
	if cells.is_empty():
		return out
	# Lissage : on saute les points intermédiaires visibles en ligne droite.
	var i := 0
	while i < cells.size() - 1:
		var j := cells.size() - 1
		while j > i + 1 and not line_clear(cells[i], cells[j]):
			j -= 1
		out.append(MapData.cell_to_world(cells[j]))
		i = j
	# Le dernier point est la position exacte de la cible.
	if not out.is_empty():
		out[out.size() - 1] = Vector3(to.x, 0.0, to.z)
	return out


## Vrai si une ligne entre deux cellules ne traverse que des cellules praticables
## (tracé « supercover » : toutes les cellules touchées sont testées).
func line_clear(a: Vector2i, b: Vector2i) -> bool:
	var x0 := a.x + 0.5
	var y0 := a.y + 0.5
	var dx := b.x - a.x
	var dy := b.y - a.y
	var steps := int(maxf(absi(dx), absi(dy)) * 3.0) + 1
	var w := _w
	var walk := _walk
	for s in steps + 1:
		var t := float(s) / steps
		var px := x0 + dx * t
		var py := y0 + dy * t
		# Marge d'un rayon de zombie autour de la ligne : les 4 coins d'un carré
		# de ±0,3 cellule (lecture directe du tableau, sans allocation).
		var xa := floori(px + 0.3)
		var xb := floori(px - 0.3)
		var ya := floori(py + 0.3)
		var yb := floori(py - 0.3)
		if xb < 0 or yb < 0 or xa >= w or ya >= _h:
			return false
		if walk[ya * w + xa] == 0 or walk[ya * w + xb] == 0 or walk[yb * w + xa] == 0 or walk[yb * w + xb] == 0:
			return false
	return true


## Ligne de vue au sol entre deux positions monde.
func world_line_clear(from: Vector3, to: Vector3) -> bool:
	return line_clear(MapData.world_to_cell(from), MapData.world_to_cell(to))
