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
	var boxes := l.box_spots()
	assert_eq(boxes.size(), 1, "une seule caisse au hasard")
	assert_near(boxes[0].pos.z, 10.65, 0.001, "posée 0,5 m devant la face du mur")
	assert_eq(boxes[0].zone, "a")
	var pw := l.power_switch()
	assert_true(pw != null)
	assert_near(pw.on_wall(0.02, 1.45).x, 29.98, 0.001, "interrupteur plaqué contre le mur")
	assert_true(l.teleporter().is_empty(), "pas de téléporteur")


## Ancienne description avec des objets supprimés (lot C) : elle se charge,
## ces marqueurs sont ignorés (avertissement), le reste est lu.
func test_removed_markers_ignored() -> void:
	var def: MapDef = load(Game.MAP_SCRIPTS["test_levels"]).new()
	var markers := {"power": {"p": [1, 0, 1], "wall": [1, 0, 0]},
		"wall_buys": [{"id": "R", "p": [0, 0, 0], "wall": [-1, 0, 0], "weapon": "m14"}],
		"perks": [{"id": "J", "p": [0, 0, 0], "wall": [0, 0, -1], "perk": "titan"}],
		"grenade_buys": [{"id": "g", "p": [0, 0, 0], "wall": [0, 0, -1]}],
		"pap": {"p": [0, 0, 0], "wall": [0, 0, -1]}, "box_boards": [{"p": [0, 0, 0], "wall": [0, 0, -1]}]}
	var l := MeshMapLayout.new(def, {"markers": markers})
	assert_true(l.power_switch() != null, "le reste de la description est lu")
	assert_eq(MeshMapLayout.REMOVED_KEYS.size(), 5)
	assert_false(l.has_method("wall_buys") or l.has_method("perks") or l.has_method("pack_a_punch"), "plus de lecteurs d'objets supprimés")


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


func test_collision_box_is_invisible_and_layered() -> void:
	var holder := Node3D.new()
	var b := CollisionBox.from_dict({"center": [1, 2, 3], "size": [4, 1, 2], "yaw": 0.5, "barrier": true, "surface": "wood"})
	holder.add_child(b)
	b._ready()
	assert_eq(b.collision_layer, Barricade.BARRIER_LAYER, "barrière : couche BARRIER")
	assert_eq(b.position, Vector3(1, 2, 3))
	assert_true(b.find_children("*", "MeshInstance3D", true, false).is_empty(), "aucun maillage : invisible")
	var shape := (b.get_child(0) as CollisionShape3D).shape as BoxShape3D
	assert_eq(shape.size, Vector3(4, 1, 2))
	var solid := CollisionBox.make(Vector3.ZERO, Vector3.ONE)
	solid._ready()
	assert_eq(solid.collision_layer, 1, "pavé plein : couche du décor")
	holder.free()
	solid.free()

