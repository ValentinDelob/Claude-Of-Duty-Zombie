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


func test_ritual_room_isolated() -> void:
	var nav := NavGrid.new(data)
	nav.set_blocked(MapDef.blocking_cells(data, def), false)
	var start := MapData.cell_to_world(data.markers["P"][0])
	var exit := MapData.cell_to_world(data.markers["F"][0])
	assert_true(nav.find_path(start, exit).is_empty(), "la salle du rituel n'est accessible que par téléporteur")


## Carte de test depuis le lot C : une seule caisse au hasard (sur le quai),
## plus aucun marqueur d'objet supprimé (achats muraux, atouts, grenades,
## Pack-a-Punch) ; portes, courant, piège et téléporteur restent.
func test_objects_defined() -> void:
	assert_eq(data.markers.get("X", []).size(), 1, "une seule caisse")
	assert_eq(data.zone_at(data.markers["X"][0]), "f", "caisse sur le quai")
	assert_eq(def.box_start, 0)
	for k in ["A", "R", "U", "V", "+", "B", "!", "$", "&", "%", "Q", "J", "S", "D", "M", "(", ")", "K", "*"]:
		assert_false(data.markers.has(k), "marqueur supprimé absent : " + k)
	assert_eq(data.markers.get("G", []).size(), 1, "un interrupteur de courant")
	assert_true(data.markers.has("T") and data.markers.has("F"), "téléporteur")
	assert_true(data.markers.has("H") and data.markers.has("E"), "piège et levier")
