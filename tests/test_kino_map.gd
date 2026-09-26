extends TestCase
## Cohérence de la carte KINO (théâtre).

var def: MapDef
var data: MapData


func before_each() -> void:
	def = load("res://scripts/game/map/maps/kino.gd").new()
	data = MapData.parse(def.rows)


func test_registered_in_game_and_menus() -> void:
	assert_true(Game.MAP_SCRIPTS.has("kino"), "KINO enregistrée dans Game.MAP_SCRIPTS")
	assert_true("kino" in Game.MENU_MAPS and "bunker_k7" in Game.MENU_MAPS, "proposée dans les menus")
	assert_eq(def.id, "kino")


func test_every_door_links_two_zones() -> void:
	assert_eq(def.doors.size(), 5, "5 portes payantes")
	for id in def.doors:
		var groups := MapDef.group_cells(data.markers.get(id, []))
		assert_eq(groups.size(), 1, "porte %s : un seul bloc" % id)
		var d := Door.new()
		d.setup(id, groups[0], def.doors[id].cost, data)
		assert_eq(d.zones.size(), 2, "porte %s relie deux zones %s" % [id, d.zones])
		d.free()


func test_lobby_doors_costs() -> void:
	# Deux portes depuis le hall : 1000 (foyer) et 750 (loges), comme à Kino.
	var from_lobby := {}
	for id in def.doors:
		var d := Door.new()
		d.setup(id, MapDef.group_cells(data.markers[id])[0], def.doors[id].cost, data)
		if "a" in d.zones:
			from_lobby[d.zones[0] if d.zones[1] == "a" else d.zones[1]] = d.cost
		d.free()
	assert_eq(from_lobby, {"b": 1000, "c": 750})


func _nav_props_only() -> NavGrid:
	var nav := NavGrid.new(data)
	var props_only := []
	for c in MapDef.blocking_cells(data, def):
		if not def.doors.has(String.chr(data.at(c))):
			props_only.append(c)
	nav.set_blocked(props_only, true)
	return nav


func _first_cell(zone: String, nav: NavGrid, outside: Dictionary) -> Vector2i:
	for y in data.height:
		for x in data.width:
			var c := Vector2i(x, y)
			if data.zone_at(c) == zone and nav.is_walkable(c) and not outside.has(c):
				return c
	return Vector2i(-1, -1)


func test_all_zones_reachable_when_doors_open() -> void:
	var nav := _nav_props_only()
	var start := MapData.cell_to_world(data.markers["P"][0])
	var outside := BarricadeLayout.pocket_cells(BarricadeLayout.analyze(data))
	for z in ["a", "b", "c", "d", "e", "f", "g"]:
		var target := _first_cell(z, nav, outside)
		assert_true(target.x >= 0, "zone %s présente" % z)
		assert_false(nav.find_path(start, MapData.cell_to_world(target)).is_empty(), "zone %s accessible" % z)


func test_zones_closed_until_doors_bought() -> void:
	var nav := NavGrid.new(data)
	nav.set_blocked(MapDef.blocking_cells(data, def), true)
	var start := MapData.cell_to_world(data.markers["P"][0])
	var outside := BarricadeLayout.pocket_cells(BarricadeLayout.analyze(data))
	for z in ["b", "c", "d", "e", "f", "g"]:
		var target := _first_cell(z, _nav_props_only(), outside)
		assert_true(nav.find_path(start, MapData.cell_to_world(target)).is_empty(), "zone %s fermée au départ" % z)


func test_projection_booth_isolated() -> void:
	var nav := _nav_props_only()
	var start := MapData.cell_to_world(data.markers["P"][0])
	var booth := MapData.cell_to_world(data.markers["F"][0])
	assert_eq(data.zone_at(data.markers["F"][0]), "p", "arrivée du téléporteur dans la cabine")
	assert_true(nav.find_path(start, booth).is_empty(), "cabine de projection accessible par téléporteur uniquement")


func test_windows_valid() -> void:
	var windows := BarricadeLayout.analyze(data)
	assert_eq(windows.size(), data.markers["W"].size(), "toutes les fenêtres sont valides")
	assert_true(windows.size() >= 12, "fenêtres barricadées nombreuses (%d)" % windows.size())
	var per_zone := {}
	for w: BarricadeLayout.Opening in windows:
		assert_false(w.spawns.is_empty(), "fenêtre %s : une apparition dans la poche" % w.cell)
		assert_true(def.zone_names.has(w.zone), "fenêtre %s dans une zone nommée (%s)" % [w.cell, w.zone])
		per_zone[w.zone] = per_zone.get(w.zone, 0) + 1
	assert_true(per_zone.get("a", 0) >= 3, "plusieurs fenêtres dans le hall (%d)" % per_zone.get("a", 0))


func test_required_markers() -> void:
	assert_eq(data.markers.get("P", []).size(), 4, "4 apparitions joueurs")
	for c in data.markers["P"]:
		assert_eq(data.zone_at(c), "a", "départ dans le hall")
	assert_eq(data.markers.get("G", []).size(), 1, "un interrupteur de courant")
	assert_eq(data.zone_at(data.markers["G"][0]), "e", "courant dans la salle des machines")
	assert_eq(data.markers.get("A", []).size(), 1, "un poste central")
	assert_eq(data.zone_at(data.markers["A"][0]), "a", "poste central dans le hall")
	assert_eq(MapDef.group_cells(data.markers.get("T", [])).size(), 1, "une plateforme de téléporteur")
	for c in data.markers["T"]:
		assert_eq(data.zone_at(c), "g", "plateforme sur la scène")
	assert_eq(data.markers.get("K", []).size(), 1, "un Pack-a-Punch")
	assert_eq(data.zone_at(data.markers["K"][0]), "g", "Pack-a-Punch sur la scène")
	assert_true(def.teleporter_link and def.pap_revealed_by_teleporter, "options Kino du téléporteur")
	assert_true(data.markers.get("=", []).size() >= 50, "rangées de fauteuils")
	assert_false(data.markers.get("]", []).is_empty(), "écran de cinéma")


func test_wall_objects_against_walls() -> void:
	var keys := def.wall_buys.keys() + def.perks.keys() + ["X", "G", "A", "H", "!", "+", "&", "$", "*"]
	for k in keys:
		for c: Vector2i in data.markers.get(k, []):
			var touches := false
			for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
				touches = touches or data.is_wall(c + d)
			assert_true(touches, "%s en %s contre un mur" % [k, c])


func test_objects_defined() -> void:
	# Arsenal mural de Kino der Toten, zone par zone.
	var expected := {"m14": "a", "olympia": "a", "mp5k": "b", "mpl": "b", "pm63": "c",
			"stakeout": "d", "m16": "f", "bowie": "e"}
	var placed := {}
	for k in def.wall_buys:
		var wid: String = def.wall_buys[k]
		assert_eq(data.markers.get(k, []).size(), 1, "achat mural %s placé une fois" % k)
		assert_true(WeaponDB.exists(wid) or KnifeDB.exists(wid), "objet %s connu" % wid)
		var cost := KnifeDB.wall_cost(wid) if KnifeDB.exists(wid) else WeaponDB.wall_cost(wid)
		assert_true(cost > 0, "%s achetable au mur (%d)" % [wid, cost])
		placed[wid] = data.zone_at(data.markers[k][0])
	assert_eq(placed, expected, "achats muraux dans leurs zones")
	assert_eq(KnifeDB.wall_cost("bowie"), 3000, "couteau de chasse à 3000")
	# Grenades (marqueur commun ThrowableSystem.GRENADE_BUY_MARKER) : hall et foyer.
	var nades: Array = data.markers.get(ThrowableSystem.GRENADE_BUY_MARKER, [])
	var nade_zones := []
	for c: Vector2i in nades:
		nade_zones.append(data.zone_at(c))
		assert_true(MapDef.wall_normal(data, c) != Vector3(0, 0, -1) or data.is_wall(c + Vector2i(0, -1)), "grenades %s contre un mur" % c)
	nade_zones.sort()
	assert_eq(nade_zones, ["a", "b"], "achats de grenades dans le hall et le foyer")
	# Aucun marqueur d'achat ne sert aussi au décor de théâtre.
	for k in def.wall_buys:
		assert_false("=~]?!+&$@|^".contains(k), "marqueur %s libre du décor" % k)
	var perk_zone := {"lazarus": "b", "twin": "c", "rapid": "d", "titan": "f", "nova": "e", "deadeye": "d"}
	for k in def.perks:
		assert_true(data.markers.has(k), "atout %s placé" % k)
		assert_true(PerkDB.exists(def.perks[k]))
		assert_eq(data.zone_at(data.markers[k][0]), perk_zone[def.perks[k]], "zone de %s" % def.perks[k])


func test_mystery_box_spots() -> void:
	var spots: Array = data.markers.get("X", [])
	assert_true(spots.size() >= 4, "au moins 4 emplacements de boîte (%d)" % spots.size())
	assert_true(def.box_starts.size() >= 2 and def.box_starts.size() <= 3, "départ tiré parmi 2-3 emplacements")
	for i in def.box_starts:
		assert_true(i >= 0 and i < spots.size(), "départ %d valide" % i)
	var blocked := {}
	for c in MapDef.blocking_cells(data, def):
		blocked[c] = true
	for c in spots:
		for sc in MysteryBox.spot_cells(c, data):
			assert_true(data.is_floor(sc) and not blocked.has(sc), "emplacement %s : case %s libre" % [c, sc])


func test_two_traps_in_narrow_passages() -> void:
	var groups := MapDef.group_cells(data.markers.get("E", []))
	assert_eq(groups.size(), 2, "deux pièges électriques")
	assert_eq(data.markers.get("H", []).size(), 2, "deux leviers")
	var zones := []
	for g in groups:
		zones.append(data.zone_at(g[0]))
		# Passage étroit : 3 cases de large au plus.
		var xs := {}
		for c: Vector2i in g:
			xs[c.x] = true
		assert_true(xs.size() <= 3, "piège dans un passage étroit")
	zones.sort()
	assert_eq(zones, ["c", "d"], "pièges des loges et de l'allée")
	# Chaque levier commande le bloc le plus proche, et ce sont deux blocs distincts.
	var picked := {}
	for lever: Vector2i in data.markers["H"]:
		var best := -1
		var best_d := INF
		for i in groups.size():
			var d := MapData.cells_center(groups[i]).distance_to(MapData.cell_to_world(lever))
			if d < best_d:
				best_d = d
				best = i
		assert_true(best_d < 6.0, "levier %s proche de son piège" % lever)
		picked[best] = true
	assert_eq(picked.size(), 2, "un levier par piège")


## Zones qui se touchent sans porte : ouvrir l'une doit activer l'autre
## (sinon ses apparitions resteraient éteintes).
func test_open_links_cover_doorless_connections() -> void:
	for y in data.height:
		for x in data.width:
			var c := Vector2i(x, y)
			if not data.is_floor(c) or def.doors.has(String.chr(data.at(c))) or data.at(c) == 87:
				continue
			for d in [Vector2i(1, 0), Vector2i(0, 1)]:
				var n: Vector2i = c + d
				if not data.is_floor(n) or def.doors.has(String.chr(data.at(n))) or data.at(n) == 87:
					continue
				var za := data.zone_at(c)
				var zb := data.zone_at(n)
				if za != zb:
					var linked: bool = zb in def.open_links.get(za, []) or za in def.open_links.get(zb, [])
					assert_true(linked, "zones %s et %s reliées sans porte en %s" % [za, zb, c])


func test_ceiling_heights() -> void:
	assert_true(def.cell_height(data, data.markers["P"][0]) > MapBuilder.WALL_HEIGHT, "hall à double hauteur")
	assert_true(def.cell_height(data, data.markers["T"][0]) >= 6.0, "scène haute")
	for id in def.doors:
		for c in data.markers[id]:
			assert_eq(def.cell_height(data, c), MapBuilder.WALL_HEIGHT, "porte %s à hauteur standard" % id)
	for c in data.markers["W"]:
		assert_eq(def.cell_height(data, c), MapBuilder.WALL_HEIGHT, "fenêtre à hauteur standard")
	assert_true(def.max_height() >= 6.0)
