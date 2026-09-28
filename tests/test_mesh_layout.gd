extends TestCase
## Cartes en maillage : lecture de la description JSON (test_levels).


func _layout() -> MeshMapLayout:
	var def: MapDef = load(Game.MAP_SCRIPTS["test_levels"]).new()
	var l := def.create_layout() as MeshMapLayout
	assert_true(l != null and not l.data.is_empty(), "description JSON lue")
	return l


func test_markers() -> void:
	var l := _layout()
	assert_true(l.is_multilevel())
	assert_eq(l.player_spawns().size(), 4, "4 départs de joueurs")
	assert_eq(l.zombie_spawns().size(), 5, "5 apparitions")
	var doors := l.doors()
	assert_eq(doors.size(), 1)
	assert_eq(doors[0].block, "door_1")
	assert_eq(int(doors[0].data.cost), 500)
	assert_eq(doors[0].data.zones, ["a", "c"])
	var wb := l.wall_buys()[0]
	assert_eq(wb.id, "R")
	assert_near(wb.pos.x, 10.65, 0.001, "posé 0,5 m devant la face du mur")
	assert_near(wb.on_wall(0.02, 1.45).x, 10.17, 0.001, "plaqué contre le mur")
	assert_eq(wb.zone, "a")
	assert_eq(l.perks()[0].zone, "c", "atout dans la salle est")
	var boxes := l.box_spots()
	assert_eq(boxes.size(), 2)
	assert_eq(l.zone_at(boxes[1].pos), "b", "deuxième boîte sur la mezzanine")
	assert_true(l.power_switch() != null)
	assert_true(l.teleporter().is_empty(), "pas de téléporteur")


func test_zones_by_height() -> void:
	var l := _layout()
	assert_eq(l.zone_at(Vector3(15, 0, 12)), "a", "sous la mezzanine")
	assert_eq(l.zone_at(Vector3(15, 3, 12)), "b", "sur la mezzanine")
	assert_eq(l.zone_at(Vector3(16, -1.2, 30)), "d", "bas de la pente")
	assert_eq(l.zone_at(Vector3(31.5, 0, 16)), "", "dehors : aucune zone")


func test_windows() -> void:
	var l := _layout()
	var ws := l.windows()
	assert_eq(ws.size(), 1)
	var w: BarricadeLayout.Opening = ws[0]
	assert_eq(w.zone, "c")
	assert_eq(w.inward_dir, Vector3(-1, 0, 0))
	assert_near(w.height, 2.4)
	assert_eq(w.spawn_points.size(), 1)
	assert_eq(l.windows()[0], w, "même objet à chaque appel (ordre stable)")
