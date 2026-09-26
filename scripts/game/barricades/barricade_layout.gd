class_name BarricadeLayout
extends RefCounted
## Analyse des fenêtres barricadées d'une carte (fonctions pures, testées).
##
## Une fenêtre est un marqueur « W » posé dans un mur, entre la zone et une
## petite « poche » extérieure fermée (le dehors) où apparaissent les zombies
## (marqueurs Z de la poche). Le côté intérieur est celui dont la région de
## sol est la plus grande.

const MARKER := "W"
## Au-delà de ce nombre de cellules, une région n'est plus une poche.
const POCKET_MAX := 40
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


class Opening:
	var index := 0
	var cell := Vector2i.ZERO
	## Direction (cellule) de la fenêtre vers l'intérieur de la zone.
	var inward := Vector2i.ZERO
	var zone := ""
	var pocket: Array = []  # Array[Vector2i]
	var spawns: Array = []  # cellules Z de la poche


## Fenêtres valides de la carte, dans l'ordre des marqueurs (déterministe).
static func analyze(data: MapData) -> Array:
	var out := []
	var windows: Array = data.markers.get(MARKER, [])
	var is_window := {}
	for c in windows:
		is_window[c] = true
	var z_cells := {}
	for c in data.markers.get("Z", []):
		z_cells[c] = true
	for c: Vector2i in windows:
		var best: Opening = null
		for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			var a := c + d
			var b := c - d
			if not (data.is_floor(a) and data.is_floor(b)) or is_window.has(a) or is_window.has(b):
				continue
			var ra := _region(data, a, is_window)
			var rb := _region(data, b, is_window)
			var small_a := ra.size() <= POCKET_MAX
			var small_b := rb.size() <= POCKET_MAX
			if small_a == small_b:
				continue
			best = Opening.new()
			best.cell = c
			best.inward = b - c if small_a else a - c
			best.pocket = ra if small_a else rb
			best.zone = data.zone_at(c + best.inward)
		if best == null:
			push_warning("[Barricade] fenêtre %s invalide (il faut du sol de part et d'autre, une poche fermée d'un côté)" % c)
			continue
		best.index = out.size()
		for pc in best.pocket:
			if z_cells.has(pc):
				best.spawns.append(pc)
		out.append(best)
	return out


## Région de sol connexe (4-connexité) à partir de `start`, sans traverser les
## fenêtres ; s'arrête dès POCKET_MAX + 1 cellules.
static func _region(data: MapData, start: Vector2i, is_window: Dictionary) -> Array:
	var seen := {start: true}
	var stack := [start]
	var out := []
	while not stack.is_empty() and out.size() <= POCKET_MAX:
		var c: Vector2i = stack.pop_back()
		out.append(c)
		for d in DIRS:
			var n: Vector2i = c + d
			if not seen.has(n) and data.is_floor(n) and not is_window.has(n):
				seen[n] = true
				stack.append(n)
	return out


## Toutes les cellules de poche (pour exclure le « dehors » d'un calcul).
static func pocket_cells(windows: Array) -> Dictionary:
	var out := {}
	for w: Opening in windows:
		for c in w.pocket:
			out[c] = true
	return out
