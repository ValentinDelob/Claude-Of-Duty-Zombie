extends TestCase
## Cohérence de la carte BUNKER K-7.

var def: MapDef
var data: MapData


func before_each() -> void:
	def = load("res://scripts/game/map/maps/bunker_k7.gd").new()
	data = MapData.parse(def.rows)


func test_every_door_links_two_zones() -> void:
	for id in def.doors:
		var groups := MapDef.group_cells(data.markers.get(id, []))
		assert_eq(groups.size(), 1, "porte %s : un seul bloc" % id)
		var d := Door.new()
		d.setup(id, groups[0], def.doors[id].cost, data)
		assert_eq(d.zones.size(), 2, "porte %s relie deux zones %s" % [id, d.zones])
		d.free()


func test_all_zones_reachable_when_doors_open() -> void:
	var nav := NavGrid.new(data)
	var blocked := MapDef.blocking_cells(data, def)
	var props_only := []
	for c in blocked:
		if not def.doors.has(String.chr(data.at(c))):
			props_only.append(c)
	nav.set_blocked(props_only, true)
	var start := MapData.cell_to_world(data.markers["P"][0])
	# Les poches derrière les fenêtres sont « dehors » : hors du calcul.
	var outside := BarricadeLayout.pocket_cells(BarricadeLayout.analyze(data))
	for z in ["a", "b", "c", "d", "e", "f"]:
		var target := Vector2i(-1, -1)
		for y in data.height:
			for x in data.width:
				if target.x < 0 and data.zone_at(Vector2i(x, y)) == z and nav.is_walkable(Vector2i(x, y)) and not outside.has(Vector2i(x, y)):
					target = Vector2i(x, y)
		assert_false(nav.find_path(start, MapData.cell_to_world(target)).is_empty(), "zone %s accessible" % z)


func test_pap_room_isolated() -> void:
	var nav := NavGrid.new(data)
	nav.set_blocked(MapDef.blocking_cells(data, def), false)
	var start := MapData.cell_to_world(data.markers["P"][0])
	var pap := MapData.cell_to_world(data.markers["F"][0])
	assert_true(nav.find_path(start, pap).is_empty(), "la salle du Pack-a-Punch n'est accessible que par téléporteur")


func test_objects_defined() -> void:
	for k in def.wall_buys:
		assert_true(data.markers.has(k), "achat mural %s placé" % k)
		assert_true(WeaponDB.exists(def.wall_buys[k]))
	for k in def.perks:
		assert_true(data.markers.has(k), "atout %s placé" % k)
	assert_eq(data.markers.get("X", []).size(), 3, "3 emplacements de boîte")
	assert_eq(data.markers.get("G", []).size(), 1, "un interrupteur de courant")
