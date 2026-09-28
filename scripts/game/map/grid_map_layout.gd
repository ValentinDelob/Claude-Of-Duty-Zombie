class_name GridMapLayout
extends MapLayout
## Carte plate décrite par une grille ASCII (MapDef.rows) : enveloppe MapData,
## NavGrid, MapBuilder, PropBuilder et BarricadeLayout sans rien changer à leur
## comportement (mêmes positions, mêmes identifiants réseau, mêmes graines).

var data: MapData
## Bloqueurs nommés -> cellules de la grille.
var _blockers: Dictionary = {}
var _open_points: Array[Vector3] = []
var _windows: Array = []
var _windows_done := false


func _init(map_def: MapDef) -> void:
	def = map_def
	data = MapData.parse(def.rows)


func create_nav() -> void:
	var grid := NavGrid.new(data)
	grid.set_blocked(MapDef.blocking_cells(data, def), true)
	nav = grid


func build(world: Node3D) -> RefCounted:
	var builder := MapBuilder.new(data, def)
	builder.materials = WorldLook.map_materials()
	builder.build(world)
	var props := PropBuilder.new(data, def)
	props.build(world)
	return props


func zone_at(pos: Vector3) -> String:
	return data.zone_at(MapData.world_to_cell(pos))


func set_blocked(key: String, blocked: bool) -> void:
	if nav and _blockers.has(key):
		(nav as NavGrid).set_blocked(_blockers[key], blocked)


func is_walkable_at(pos: Vector3) -> bool:
	return nav != null and (nav as NavGrid).is_walkable(MapData.world_to_cell(pos))


func player_spawns() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for c in data.markers.get(def.player_spawn_marker(), []):
		out.append(MapData.cell_to_world(c, 0.05))
	return out


func warm_point() -> Vector3:
	var spawns: Array = data.markers.get(def.player_spawn_marker(), [])
	return MapData.cell_to_world(spawns[0]) if not spawns.is_empty() else Vector3(2, 0, 2)


func zombie_spawns() -> Array:
	var out := []
	for c in data.markers.get("Z", []):
		out.append({"pos": MapData.cell_to_world(c), "zone": data.zone_at(c), "cell": c})
	return out


## Cellules praticables et dégagées tout autour (état de la navigation au
## premier appel, comme auparavant dans DogRound).
func open_floor_points() -> Array[Vector3]:
	if _open_points.is_empty() and nav:
		var grid := nav as NavGrid
		for y in data.height:
			for x in data.width:
				var c := Vector2i(x, y)
				if data.zone_at(c) == "" or not grid.is_walkable(c):
					continue
				var clear := true
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						if not grid.is_walkable(c + Vector2i(dx, dy)):
							clear = false
				if clear:
					_open_points.append(MapData.cell_to_world(c))
	return _open_points


func doors() -> Array[MapMarker]:
	var out: Array[MapMarker] = []
	for id in def.doors:
		for group in MapDef.group_cells(data.markers.get(id, [])):
			var m := door_marker(id, group, def.doors[id].cost, data)
			_blockers[m.block] = group
			out.append(m)
	return out


## Porte d'après ses cellules : ouverture, orientation et zones de part et
## d'autre (aussi utilisé par Door.setup pour les tests sur grille).
static func door_marker(id: String, cells: Array, cost: int, map_data: MapData) -> MapMarker:
	var minc := Vector2i(999, 999)
	var maxc := Vector2i(-999, -999)
	for c in cells:
		minc = Vector2i(mini(minc.x, c.x), mini(minc.y, c.y))
		maxc = Vector2i(maxi(maxc.x, c.x), maxi(maxc.y, c.y))
	# Porte dans un mur « vertical » (x constant) si les voisins en X sont du sol.
	var probe: Vector2i = cells[0]
	var along_z := map_data.is_floor(Vector2i(minc.x - 1, probe.y)) and map_data.is_floor(Vector2i(maxc.x + 1, probe.y))
	var span := (maxc - minc) + Vector2i.ONE
	var m := MapMarker.new()
	m.id = id
	m.block = "door_" + id
	m.cell = minc
	m.pos = (MapData.cell_to_world(minc) + MapData.cell_to_world(maxc)) * 0.5
	var zones := []
	var side_a := minc - (Vector2i(1, 0) if along_z else Vector2i(0, 1))
	var side_b := maxc + (Vector2i(1, 0) if along_z else Vector2i(0, 1))
	for c in [side_a, side_b]:
		var z := map_data.zone_at(c)
		if z != "" and not z in zones:
			zones.append(z)
	m.data = {
		"cost": cost,
		"width": float(span.y if along_z else span.x) * MapData.CELL,
		"depth": float(span.x if along_z else span.y) * MapData.CELL,
		"height": MapBuilder.WALL_HEIGHT,
		"yaw": PI * 0.5 if along_z else 0.0,
		"zones": zones,
		"cells": cells,
	}
	return m


## Objet plaqué au mur le plus proche d'une cellule.
static func cell_marker(id: String, c: Vector2i, map_data: MapData) -> MapMarker:
	var m := MapMarker.new()
	m.id = id
	m.cell = c
	m.pos = MapData.cell_to_world(c)
	m.wall = MapDef.wall_normal(map_data, c)
	m.wall_gap = MapData.CELL * 0.5
	m.zone = map_data.zone_at(c)
	m.seed = c.x * 7 + c.y * 13
	return m


func wall_buys() -> Array[MapMarker]:
	var out: Array[MapMarker] = []
	for marker in def.wall_buys:
		for c in data.markers.get(marker, []):
			var m := cell_marker(marker, c, data)
			m.data = {"weapon": def.wall_buys[marker]}
			out.append(m)
	return out


func perks() -> Array[MapMarker]:
	var out: Array[MapMarker] = []
	for marker in def.perks:
		for c in data.markers.get(marker, []):
			var m := cell_marker(marker, c, data)
			m.data = {"perk": def.perks[marker]}
			out.append(m)
	return out


func grenade_buys() -> Array[MapMarker]:
	var out: Array[MapMarker] = []
	for c in data.markers.get(ThrowableSystem.GRENADE_BUY_MARKER, []):
		out.append(cell_marker("%d_%d" % [c.x, c.y], c, data))
	return out


func power_switch() -> MapMarker:
	var cells: Array = data.markers.get("G", [])
	return cell_marker("power", cells[0], data) if not cells.is_empty() else null


func box_spots() -> Array[MapMarker]:
	var out: Array[MapMarker] = []
	var cells: Array = data.markers.get("X", [])
	for i in cells.size():
		var m := cell_marker("box_%d" % i, cells[i], data)
		m.block = "box_%d" % i
		_blockers[m.block] = MysteryBox.spot_cells(cells[i], data)
		out.append(m)
	return out


func pack_a_punch() -> MapMarker:
	var cells: Array = data.markers.get("K", [])
	if cells.is_empty():
		return null
	var m := cell_marker("pap", cells[0], data)
	m.block = "pap"
	_blockers[m.block] = MysteryBox.spot_cells(cells[0], data)
	return m


func teleporter() -> Dictionary:
	var pad: Array = data.markers.get("T", [])
	var exit: Array = data.markers.get("F", [])
	if pad.is_empty() or exit.is_empty():
		return {}
	var mf: MapMarker = null
	var mf_cells: Array = data.markers.get("A", [])
	if not mf_cells.is_empty():
		mf = cell_marker("mainframe", mf_cells[0], data)
		mf.block = "mainframe"
		_blockers[mf.block] = MysteryBox.spot_cells(mf_cells[0], data)
	return {"pad": MapData.cells_center(pad), "exit": MapData.cell_to_world(exit[0], 0.05), "mainframe": mf}


func teleporter_exit_zone() -> String:
	var exit: Array = data.markers.get("F", [])
	return data.zone_at(exit[0]) if not exit.is_empty() else ""


## Chaque levier H commande le bloc de cases E le plus proche (le premier
## piège garde l'identifiant « trap »).
func traps() -> Array[MapMarker]:
	var out: Array[MapMarker] = []
	var groups := MapDef.group_cells(data.markers.get("E", []))
	var levers: Array = data.markers.get("H", [])
	for i in levers.size():
		var best := -1
		var best_d := INF
		for g in groups.size():
			var d := MapData.cells_center(groups[g]).distance_to(MapData.cell_to_world(levers[i]))
			if d < best_d:
				best_d = d
				best = g
		if best < 0:
			break
		var m := cell_marker("trap" if i == 0 else "trap_%d" % (i + 1), levers[i], data)
		var minc := Vector2i(9999, 9999)
		var maxc := Vector2i(-9999, -9999)
		for c in groups[best]:
			minc = Vector2i(mini(minc.x, c.x), mini(minc.y, c.y))
			maxc = Vector2i(maxi(maxc.x, c.x), maxi(maxc.y, c.y))
		var lo := Vector3(minc.x, 0, minc.y) * MapData.CELL
		var hi := Vector3(maxc.x + 1, MapBuilder.WALL_HEIGHT, maxc.y + 1) * MapData.CELL
		m.data = {"area": AABB(lo, hi - lo), "cells": groups[best]}
		out.append(m)
	return out


func windows() -> Array:
	if not _windows_done:
		_windows_done = true
		_windows = BarricadeLayout.analyze(data)
		for w: BarricadeLayout.Opening in _windows:
			_blockers["window_%d" % w.index] = [w.cell]
	return _windows
