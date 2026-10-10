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
##   power {p, wall}, box [{p, wall, floor?}] (caisse au hasard : le jeu ne
##   garde que l'entrée MapDef.box_start ; « floor » : caisse posée au sol,
##   format 15 de l'éditeur ; `wall` = son arrière, `p` à
##   MysteryBox.SPOT_WALL_GAP derrière son centre),
##   evac {p, wall} (porte d'évacuation, EvacDoor),
##   (clés d'objets supprimés, ignorées avec un avertissement : REMOVED_KEYS)
##   teleporter {pad, exit, mainframe {p, wall}, exit_zone},
##   traps [{id, lever {p, wall}, area [x0,y0,z0,x1,y1,z1], yaw? (zone tournée autour de son centre)}],
##   windows [{p (au sol, dans l'ouverture), in (vers l'intérieur), h, zone, spawns [[x,y,z]],
##            kind? (« porte », « porte_double » ; absent : fenêtre), w? (largeur)}],
##   lamps [{p, range, energy}]
## Zones (clé « zones ») : {id: {boxes: [[x0,y0,z0,x1,y1,z1]...]}}, testées dans l'ordre.

const GAP := 0.5
## Marqueurs d'objets supprimés du jeu (achats muraux, atouts, achats de
## grenades, Pack-a-Punch, tableaux à la craie de la boîte) : une ancienne
## description qui en contient se charge encore, ils sont ignorés.
const REMOVED_KEYS := ["wall_buys", "perks", "grenade_buys", "pap", "box_boards"]

var data: Dictionary
var glb_path := ""
var _markers: Dictionary
var _zones: Array = []  # [id, AABB]
var _door_markers: Array[MapMarker] = []
var _windows: Array = []
var _world: Node3D
## Rayon de sol réutilisé par ground().
var _ground_q: PhysicsRayQueryParameters3D


## `source` : chemin du layout.json, ou la description déjà en mémoire (cartes
## de l'éditeur, MapLayoutExport). `glb` vide : architecture construite par le
## jeu (MeshMapGeometry) au lieu du .glb de Blender.
func _init(map_def: MapDef, source: Variant, glb: String) -> void:
	def = map_def
	glb_path = glb
	if source is Dictionary:
		data = source
	else:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(source)))
		if parsed is Dictionary:
			data = parsed
		else:
			push_error("[MeshMapLayout] JSON illisible : " + String(source))
			data = {}
	_markers = data.get("markers", {})
	for k in REMOVED_KEYS:
		if _markers.has(k):
			push_warning("[MeshMapLayout] objets « %s » ignorés : supprimés du jeu" % k)
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
	mn.bake(data.get("nav_blocks", []))
	for m in _door_markers:
		var n := Basis(Vector3.UP, float(m.data.yaw)).z
		var reach := float(m.data.depth) * 0.5 + 1.0
		mn.add_link(m.block, m.pos - n * reach, m.pos + n * reach)
	NavigationServer3D.map_force_update(mn.map)
	# Couloirs d'ancres des escaliers (StairGen) : posés sur le navmesh cuit.
	mn.set_stairs(data.get("stairs", []))


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
	# Requête réutilisée (seuls les deux points changent) : sol des particules
	# (Fx.floor_under : flammes des chiens, gerbes) et des bonus, même rayon.
	if _ground_q == null:
		_ground_q = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.DOWN, 1)
	_ground_q.from = pos + Vector3.UP * 0.8
	_ground_q.to = pos + Vector3.DOWN * 3.0
	var hit := _world.get_world_3d().direct_space_state.intersect_ray(_ground_q)
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
			"variant": String(d.get("variant", "")),
		}
		_door_markers.append(mk)
	return _door_markers


func power_switch() -> MapMarker:
	return _wall_marker("power", _markers.power) if _markers.has("power") else null


func box_spots() -> Array[MapMarker]:
	var out: Array[MapMarker] = []
	var spots: Array = _markers.get("box", [])
	for i in spots.size():
		var mk := _wall_marker("box_%d" % i, spots[i])
		# Format 15 (éditeur) : caisse posée au sol, « wall » = son arrière
		# (mur fictif) ; utilisable de tous les côtés (MysteryBox.interact_point).
		if bool(spots[i].get("floor", false)):
			mk.data["floor"] = true
		out.append(mk)
	return out


## Porte d'évacuation : marqueur « evac » {p, wall}, comme un objet mural.
func evac_door() -> MapMarker:
	return _wall_marker("evac", _markers.evac) if _markers.get("evac") is Dictionary else null


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
		if t.has("yaw"):
			# Zone tournée (éditeur de cartes) : `area` avant rotation, tournée de
			# `yaw` autour de son centre.
			mk.data["yaw"] = float(t.yaw)
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
			# Format 8 : porte à zombies (simple ou double) ; absent : fenêtre.
			var kind := String(w.get("kind", BarricadeRules.WINDOW))
			o.kind = kind if BarricadeRules.KINDS.has(kind) else BarricadeRules.WINDOW
			o.width = float(w.get("w", BarricadeRules.width(o.kind)))
			for s in w.get("spawns", []):
				o.spawn_points.append(vec(s))
			_windows.append(o)
		# Barrière de collision ajustée au mur percé (épaisseur, découpe) :
		# rien ne dépasse du nu du mur (BarricadeFit).
		BarricadeFit.fit(data, _windows)
	return _windows


func floor_y(pos: Vector3) -> float:
	return ground(pos).y


func player_spawn_yaw() -> float:
	return float(_markers.get("player_yaw", PI))
