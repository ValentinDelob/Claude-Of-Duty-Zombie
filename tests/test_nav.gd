extends TestCase

const ROWS := [
	"##########",
	"#....#...#",
	"#....#...#",
	"#....#...#",
	"#........#",
	"##########",
]


func _nav() -> NavGrid:
	return NavGrid.new(MapData.parse(PackedStringArray(ROWS)))


func test_path_goes_around_wall() -> void:
	var nav := _nav()
	var a := MapData.cell_to_world(Vector2i(2, 1))
	var b := MapData.cell_to_world(Vector2i(7, 1))
	var path := nav.find_path(a, b)
	assert_false(path.is_empty(), "chemin trouvé")
	# Le chemin doit descendre jusqu'à la rangée 4 pour contourner le mur.
	var lowest := 0.0
	for p in path:
		lowest = maxf(lowest, p.z)
	assert_true(lowest >= 4.0, "contourne le mur par le bas (z max %.1f)" % lowest)
	assert_true(path[path.size() - 1].distance_to(b) < 0.01, "finit sur la cible")


func test_smoothing_reduces_points() -> void:
	var nav := _nav()
	var path := nav.find_path(MapData.cell_to_world(Vector2i(1, 1)), MapData.cell_to_world(Vector2i(4, 4)))
	assert_eq(path.size(), 1, "ligne droite dans une pièce ouverte")


func test_blocked_cells_cut_path() -> void:
	var nav := _nav()
	nav.set_blocked([Vector2i(5, 4)], true)
	var path := nav.find_path(MapData.cell_to_world(Vector2i(2, 1)), MapData.cell_to_world(Vector2i(7, 1)))
	assert_true(path.is_empty(), "porte fermée : inaccessible")
	nav.set_blocked([Vector2i(5, 4)], false)
	path = nav.find_path(MapData.cell_to_world(Vector2i(2, 1)), MapData.cell_to_world(Vector2i(7, 1)))
	assert_false(path.is_empty(), "porte ouverte : accessible")


func test_line_of_sight() -> void:
	var nav := _nav()
	assert_true(nav.line_clear(Vector2i(1, 1), Vector2i(4, 3)))
	assert_false(nav.line_clear(Vector2i(2, 2), Vector2i(7, 2)))


func test_nearest_walkable() -> void:
	var nav := _nav()
	var c := nav.nearest_walkable(Vector2i(5, 2))
	assert_true(nav.is_walkable(c))
