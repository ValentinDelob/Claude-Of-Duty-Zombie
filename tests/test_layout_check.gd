extends TestCase
## LayoutCheck (lot E, docs/VOXEL_ARCHITECTURE_PLAN.md) : toute l'architecture
## des cartes jouables est cubique (faces axiales, sommets et valeurs sur la
## grille de 5 cm) : cartes du jeu (BUNKER K-7 et l'arène de test en grille,
## DRAFT ARENA, test_levels), cartes d'essai des tests (murs en biais, salle
## ronde, murs libres, pente, escaliers de tous les types, escalier tourné,
## immeuble) et fixtures ; une architecture non cubique est bien refusée.

const Migration := preload("res://tests/test_voxel_archi_migration.gd")
const Diag := preload("res://tests/test_map_editor_diagonal.gd")
const Free := preload("res://tests/test_map_editor_freeform.gd")
const Walls := preload("res://tests/test_map_editor_walls.gd")
const Stairs := preload("res://tests/test_stairs.gd")
const Floors := preload("res://tests/test_stairs_floors.gd")


func _ok(rep: Dictionary, what: String) -> void:
	assert_true(rep.ok, "%s : %s" % [what, rep.fr])
	assert_true(rep.faces > 0, "%s : architecture vérifiée (%d faces)" % [what, rep.faces])


func test_built_in_maps_are_cubic() -> void:
	assert_true(Game.MAP_SCRIPTS.size() >= 4, "cartes du jeu (%d)" % Game.MAP_SCRIPTS.size())
	for id in Game.MAP_SCRIPTS:
		var def: MapDef = load(Game.MAP_SCRIPTS[id]).new()
		_ok(LayoutCheck.check_def(def), id)
	_ok(LayoutCheck.check_map(EditorMap.load_dir(EditorMap.EXAMPLES.draft_arena)), "DRAFT ARENA (éditeur)")


func test_test_maps_are_cubic() -> void:
	var stairs := Stairs.stairs_map()
	for o in stairs.objets:
		if o.get("type") == "escalier":
			o["garde_corps"] = true
	var rotated := Free.stairs_map()
	rotated.find("e1")["garde_corps"] = true
	for it in [["biais", Diag.diag_map()], ["ronde", Free.round_map()], ["murs_libres", Walls.free_walls_map()],
			["pente", Free.slanted_map()], ["escaliers", stairs], ["escalier_tourne", rotated],
			["immeuble", Floors.tower_with_stairs()]]:
		var t0 := Time.get_ticks_msec()
		var data: Dictionary = MapPreviewWorld.compute(it[1]).data
		var t1 := Time.get_ticks_msec()
		var rep := LayoutCheck.check(data)
		print("[layout_check] %s : export %d ms, contrôle %d ms, %d faces" % [it[0], t1 - t0, Time.get_ticks_msec() - t1, rep.faces])
		_ok(rep, it[0])


func test_fixtures_are_cubic() -> void:
	var all := Migration.fixtures()
	var n := 0
	for name in all:
		var rep := LayoutCheck.check_map(all[name])
		assert_true(rep.ok, "%s : %s" % [name, rep.fr])
		n += 1
	assert_true(n >= 20, "cartes d'essai contrôlées (%d)" % n)


## Refus : une valeur hors grille, un maillage tourné, un sommet hors grille.
func test_non_cubic_is_refused() -> void:
	var rep := LayoutCheck.check({"rooms": [{"id": "r", "outline": [[0, 0], [4.03, 0], [4.03, 4], [0, 4]], "floor": 0.0, "ceiling": 3.0}]})
	assert_false(rep.ok, "contour à 4,03 m refusé")
	assert_true(rep.values.size() >= 1 and String(rep.fr).contains("4.03"), rep.fr)
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.5, 0.5)
	mi.mesh = bm
	mi.rotation.y = deg_to_rad(30.0)
	root.add_child(mi)
	var r2 := LayoutCheck.check_nodes(root)
	assert_true(r2.oblique > 0, "pavé tourné de 30° : faces non axiales")
	mi.rotation.y = 0.0
	mi.position = Vector3(0.02, 0, 0)
	var r3 := LayoutCheck.check_nodes(root)
	assert_eq(r3.oblique, 0, "pavé droit : faces axiales")
	assert_true(r3.off_grid > 0, "décalé de 2 cm : sommets hors grille")
	root.free()
