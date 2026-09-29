class_name MeshMapLayout
extends MapLayout
## Carte en maillage à plusieurs niveaux, décrite par un JSON
## (assets/maps/<id>/layout.json, repère Godot, mètres) et construite par
## tools/blender/mesh_map.py (<id>.glb). Le même JSON sert à Blender (géométrie)
## et au jeu (zones, emplacements, navigation).
##
## Marqueurs (clé « markers ») : un objet mural est donné par le point `p` de
## la FACE du mur, au niveau du sol, et `wall` = direction vers le mur ; le jeu
## le place à 0,5 m devant (MapMarker.wall_gap), comme sur une grille.
##   player_spawns [[x,y,z]], zombie_spawns [{p, zone}],
##   doors [{id, p (milieu de l'ouverture, au sol), yaw, w, h, depth, cost, zones, debris?}],
##   wall_buys [{id, p, wall, weapon}], perks [{id, p, wall, perk}],
##   grenade_buys [{id, p, wall}], power {p, wall}, box [{p, wall}], pap {p, wall},
##   teleporter {pad, exit, mainframe {p, wall}, exit_zone},
##   traps [{id, lever {p, wall}, area [x0,y0,z0,x1,y1,z1]}],
##   windows [{p (au sol, dans l'ouverture), in (vers l'intérieur), h, zone, spawns [[x,y,z]]}],
##   lamps [{p, range, energy}]
## Zones (clé « zones ») : {id: {boxes: [[x0,y0,z0,x1,y1,z1]...]}}, testées dans l'ordre.

const GAP := 0.5

var data: Dictionary
var glb_path := ""
var _markers: Dictionary
var _zones: Array = []  # [id, AABB]
var _door_markers: Array[MapMarker] = []
var _windows: Array = []
var _world: Node3D


func _init(map_def: MapDef, json_path: String, glb: String) -> void:
	def = map_def
	glb_path = glb
	var txt := FileAccess.get_file_as_string(json_path)
	data = JSON.parse_string(txt)
	if data == null:
		push_error("[MeshMapLayout] JSON illisible : " + json_path)
		data = {}
	_markers = data.get("markers", {})
	# Ordre de test des boîtes de zones : « zone_order » (les plus petites
	# d'abord : balcons et galeries avant la grande salle) s'il est fourni.
	if data.has("zone_order"):
		for zo in data.zone_order:
			_zones.append([String(zo.zone), box(zo.box)])
	else:
		var zones: Dictionary = data.get("zones", {})
		for id in zones:
			for b in zones[id].boxes:
				_zones.append([String(id), box(b)])


static func vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


static func box(b: Array) -> AABB:
	var lo := Vector3(b[0], b[1], b[2])
	var hi := Vector3(b[3], b[4], b[5])
	return AABB(lo, hi - lo)


func create_nav() -> void:
	# La cuisson attend la fin de la construction (finish_nav).
	var mn := MeshNav.new()
	nav = mn


func finish_nav(world: Node3D) -> void:
	var mn := nav as MeshNav
	if mn == null:
		return
	mn.setup(world)
	mn.bake()
	for m in _door_markers:
		var n := Basis(Vector3.UP, float(m.data.yaw)).z
		var reach := float(m.data.depth) * 0.5 + 1.0
		mn.add_link(m.block, m.pos - n * reach, m.pos + n * reach)
	NavigationServer3D.map_force_update(mn.map)


func build(world: Node3D) -> RefCounted:
	_world = world
	var b := MeshMapBuilder.new(data, glb_path)
	b.build(world)
	return b


func zone_at(pos: Vector3) -> String:
	for z in _zones:
		if (z[1] as AABB).has_point(pos + Vector3.UP * 0.05):
			return z[0]
	return ""


func set_blocked(key: String, blocked: bool) -> void:
	if nav:
		(nav as MeshNav).set_blocked(key, blocked)


func is_walkable_at(pos: Vector3) -> bool:
	return nav != null and (nav as MeshNav).is_walkable(pos)


## Sol sous une position (rayon vers le bas sur les collisions du décor).
func ground(pos: Vector3) -> Vector3:
	if _world == null:
		return pos
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.8, pos + Vector3.DOWN * 3.0, 1)
	var hit := _world.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else pos


func is_multilevel() -> bool:
	return true


func player_spawns() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p in _markers.get("player_spawns", []):
		out.append(vec(p))
	return out


func zombie_spawns() -> Array:
	var out := []
	for s in _markers.get("zombie_spawns", []):
		out.append({"pos": vec(s.p), "zone": String(s.get("zone", ""))})
	return out


func open_floor_points() -> Array[Vector3]:
	return (nav as MeshNav).random_points(600) if nav else ([] as Array[Vector3])


func _wall_marker(id: String, m: Dictionary) -> MapMarker:
	var mk := MapMarker.new()
	mk.id = id
	mk.wall = vec(m.wall).normalized() if m.has("wall") else Vector3(0, 0, -1)
	mk.pos = vec(m.p) - mk.wall * GAP
	mk.wall_gap = GAP
	mk.zone = zone_at(mk.pos)
	mk.seed = int(absf(mk.pos.x * 7.0 + mk.pos.z * 13.0))
	return mk


func doors() -> Array[MapMarker]:
	_door_markers.clear()
	for d in _markers.get("doors", []):
		var mk := MapMarker.new()
		mk.id = String(d.id)
		mk.block = "door_" + mk.id
		mk.pos = vec(d.p)
		mk.data = {
			"cost": int(d.get("cost", def.doors.get(mk.id, {}).get("cost", 1000))),
			"width": float(d.w), "height": float(d.h), "depth": float(d.get("depth", 0.3)),
			"yaw": float(d.get("yaw", 0.0)), "zones": d.get("zones", []),
			"power": bool(d.get("power", false)), "link": String(d.get("link", "")),
			"curtain": bool(d.get("curtain", false)), "debris": bool(d.get("debris", false)),
		}
		_door_markers.append(mk)
	return _door_markers


func wall_buys() -> Array[MapMarker]:
	var out: Array[MapMarker] = []
	for w in _markers.get("wall_buys", []):
		var mk := _wall_marker(String(w.id), w)
		mk.data = {"weapon": String(w.weapon)}
		out.append(mk)
	return out


func perks() -> Array[MapMarker]:
	var out: Array[MapMarker] = []
	for w in _markers.get("perks", []):
		var mk := _wall_marker(String(w.id), w)
		mk.data = {"perk": String(w.perk)}
		out.append(mk)
	return out


func grenade_buys() -> Array[MapMarker]:
	var out: Array[MapMarker] = []
	for w in _markers.get("grenade_buys", []):
		out.append(_wall_marker(String(w.id), w))
	return out


func power_switch() -> MapMarker:
	return _wall_marker("power", _markers.power) if _markers.has("power") else null


func box_spots() -> Array[MapMarker]:
	var out: Array[MapMarker] = []
	var spots: Array = _markers.get("box", [])
	for i in spots.size():
		out.append(_wall_marker("box_%d" % i, spots[i]))
	return out


func pack_a_punch() -> MapMarker:
	return _wall_marker("pap", _markers.pap) if _markers.has("pap") else null


func teleporter() -> Dictionary:
	if not _markers.has("teleporter"):
		return {}
	var t: Dictionary = _markers.teleporter
	var mf: MapMarker = null
	if t.has("mainframe"):
		mf = _wall_marker("mainframe", t.mainframe)
		if t.mainframe.get("floor", false):
			# Disque au sol (Kino) : centré sur le point relevé.
			mf.pos = vec(t.mainframe.p)
			mf.zone = zone_at(mf.pos)
			mf.data = {"floor": true}
	return {"pad": vec(t.pad), "exit": vec(t.exit), "mainframe": mf}


func teleporter_exit_zone() -> String:
	return String(_markers.get("teleporter", {}).get("exit_zone", ""))


func traps() -> Array[MapMarker]:
	var out: Array[MapMarker] = []
	for t in _markers.get("traps", []):
		var mk := _wall_marker(String(t.id), t.lever)
		mk.data = {"area": box(t.area), "cells": [], "fire": bool(t.get("fire", false))}
		for k in ["active", "cooldown"]:
			if t.has(k):
				mk.data[k] = float(t[k])
		if t.has("lever2"):
			mk.data["lever2"] = _wall_marker(String(t.id) + "_b", t.lever2)
		out.append(mk)
	return out


func windows() -> Array:
	if _windows.is_empty():
		var list: Array = _markers.get("windows", [])
		for i in list.size():
			var w: Dictionary = list[i]
			var o := BarricadeLayout.Opening.new()
			o.index = i
			o.pos = vec(w.p)
			o.inward_dir = vec(w["in"]).normalized()
			o.height = float(w.get("h", 2.4))
			o.seed = hash(Vector3i(roundi(o.pos.x * 10.0), roundi(o.pos.y * 10.0), roundi(o.pos.z * 10.0)))
			o.zone = String(w.get("zone", zone_at(o.pos + o.inward_dir)))
			for s in w.get("spawns", []):
				o.spawn_points.append(vec(s))
			_windows.append(o)
	return _windows


func floor_y(pos: Vector3) -> float:
	return ground(pos).y


func player_spawn_yaw() -> float:
	return float(_markers.get("player_yaw", PI))


func box_boards() -> Array[MapMarker]:
	var out: Array[MapMarker] = []
	var list: Array = _markers.get("box_boards", [])
	for i in list.size():
		out.append(_wall_marker("board_%d" % i, list[i]))
	return out


func room_outlines() -> Array:
	var out := []
	for r in data.get("rooms", []):
		if not String(r.id).begins_with("dehors"):
			out.append(r.outline)
	return out
